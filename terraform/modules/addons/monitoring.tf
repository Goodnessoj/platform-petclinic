locals {
  monitoring_namespace = "monitoring"
  tracing_namespace    = "tracing"

  instrumented_services = [
    "admin-server",
    "api-gateway",
    "config-server",
    "customers-service",
    "discovery-server",
    "visits-service",
    "vets-service",
    "genai-service",
  ]

  observability_labels = {
    "app.kubernetes.io/part-of" = "petclinic-observability"
  }

  petclinic_dashboard = {
    uid           = "petclinic-observability"
    title         = "Petclinic Observability"
    schemaVersion = 39
    version       = 1
    refresh       = "15s"
    time = {
      from = "now-30m"
      to   = "now"
    }
    tags = ["petclinic", "eks"]
    templating = {
      list = []
    }
    panels = [
      {
        id    = 1
        type  = "timeseries"
        title = "HTTP Request Rate"
        datasource = {
          type = "prometheus"
          uid  = "prometheus"
        }
        targets = [
          {
            expr         = "sum by (pod) (rate(http_server_requests_seconds_count{namespace=\"${local.application_namespace}\"}[5m]))"
            legendFormat = "{{pod}}"
            refId        = "A"
          }
        ]
        gridPos = { h = 8, w = 12, x = 0, y = 0 }
      },
      {
        id    = 2
        type  = "timeseries"
        title = "HTTP 5xx Rate"
        datasource = {
          type = "prometheus"
          uid  = "prometheus"
        }
        targets = [
          {
            expr         = "sum by (pod) (rate(http_server_requests_seconds_count{namespace=\"${local.application_namespace}\",status=~\"5..\"}[5m]))"
            legendFormat = "{{pod}}"
            refId        = "A"
          }
        ]
        gridPos = { h = 8, w = 12, x = 12, y = 0 }
      },
      {
        id    = 3
        type  = "timeseries"
        title = "P99 Response Time"
        datasource = {
          type = "prometheus"
          uid  = "prometheus"
        }
        targets = [
          {
            expr         = "histogram_quantile(0.99, sum by (le, pod) (rate(http_server_requests_seconds_bucket{namespace=\"${local.application_namespace}\"}[5m])))"
            legendFormat = "{{pod}}"
            refId        = "A"
          }
        ]
        gridPos = { h = 8, w = 12, x = 0, y = 8 }
      },
      {
        id    = 4
        type  = "timeseries"
        title = "Memory Usage"
        datasource = {
          type = "prometheus"
          uid  = "prometheus"
        }
        targets = [
          {
            expr         = "sum by (pod) (container_memory_working_set_bytes{namespace=\"${local.application_namespace}\",container!=\"\",image!=\"\"})"
            legendFormat = "{{pod}}"
            refId        = "A"
          }
        ]
        gridPos = { h = 8, w = 12, x = 12, y = 8 }
      },
      {
        id    = 5
        type  = "timeseries"
        title = "Pod Restarts"
        datasource = {
          type = "prometheus"
          uid  = "prometheus"
        }
        targets = [
          {
            expr         = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"${local.application_namespace}\"}[15m]))"
            legendFormat = "{{pod}}"
            refId        = "A"
          }
        ]
        gridPos = { h = 8, w = 12, x = 0, y = 16 }
      },
      {
        id    = 6
        type  = "logs"
        title = "Application Logs"
        datasource = {
          type = "loki"
          uid  = "loki"
        }
        targets = [
          {
            expr  = "{kubernetes_namespace_name=\"${local.application_namespace}\"}"
            refId = "A"
          }
        ]
        gridPos = { h = 10, w = 12, x = 12, y = 16 }
      }
    ]
  }

  petclinic_alert_rules_manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "petclinic-alert-rules"
      namespace = local.monitoring_namespace
      labels = merge(local.observability_labels, {
        "app.kubernetes.io/name" = "petclinic-alert-rules"
        release                  = "monitoring"
      })
    }

    spec = {
      groups = [
        {
          name = "petclinic.rules"
          rules = [
            {
              alert = "PetclinicHighErrorRate"
              expr  = <<-EOT
                (
                  sum by (pod) (rate(http_server_requests_seconds_count{namespace="${local.application_namespace}",status=~"5.."}[5m]))
                  /
                  sum by (pod) (rate(http_server_requests_seconds_count{namespace="${local.application_namespace}"}[5m]))
                ) > 0.05
                and on (pod)
                sum by (pod) (rate(http_server_requests_seconds_count{namespace="${local.application_namespace}"}[5m])) > 0.1
              EOT
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "petclinic"
              }
              annotations = {
                summary     = "High HTTP 5xx error rate"
                description = "{{ $labels.pod }} has more than 5% HTTP 5xx responses for 5 minutes."
              }
            },
            {
              alert = "PetclinicPodRestartLoop"
              expr  = "sum by (namespace, pod, container) (increase(kube_pod_container_status_restarts_total{namespace=\"${local.application_namespace}\"}[15m])) > 5"
              labels = {
                severity = "warning"
                team     = "petclinic"
              }
              annotations = {
                summary     = "Pod restart loop"
                description = "{{ $labels.pod }} restarted more than 5 times in 15 minutes."
              }
            },
            {
              alert = "PetclinicHighMemoryUsage"
              expr  = <<-EOT
                (
                  sum by (pod, container) (container_memory_working_set_bytes{namespace="${local.application_namespace}",container!="",image!=""})
                  /
                  sum by (pod, container) (kube_pod_container_resource_limits{namespace="${local.application_namespace}",resource="memory",unit="byte"} > 0)
                ) > 0.8
              EOT
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "petclinic"
              }
              annotations = {
                summary     = "High pod memory usage"
                description = "{{ $labels.pod }}/{{ $labels.container }} is using more than 80% of its memory limit."
              }
            },
            {
              alert = "PetclinicServiceDown"
              expr  = <<-EOT
                kube_deployment_spec_replicas{namespace="${local.application_namespace}",deployment=~"(${join("|", local.instrumented_services)})"} > 0
                unless on (namespace, deployment)
                label_replace(
                  max_over_time(up{namespace="${local.application_namespace}",pod=~"(${join("|", local.instrumented_services)})-.*"}[2m]) == 1,
                  "deployment",
                  "$1",
                  "pod",
                  "(.+)-[a-z0-9]+-[a-z0-9]+"
                )
              EOT
              for   = "2m"
              labels = {
                severity = "critical"
                team     = "petclinic"
              }
              annotations = {
                summary     = "Service metrics target is down"
                description = "{{ $labels.deployment }} has no successful Prometheus scrape for 2 minutes."
              }
            },
            {
              alert = "PetclinicSlowP99ResponseTime"
              expr  = <<-EOT
                histogram_quantile(
                  0.99,
                  sum by (le, pod) (rate(http_server_requests_seconds_bucket{namespace="${local.application_namespace}"}[5m]))
                ) > 2
              EOT
              for   = "5m"
              labels = {
                severity = "warning"
                team     = "petclinic"
              }
              annotations = {
                summary     = "Slow P99 response time"
                description = "{{ $labels.pod }} has P99 latency above 2s for 5 minutes."
              }
            }
          ]
        }
      ]
    }
  }
}

resource "helm_release" "monitoring" {
  name                       = "monitoring"
  chart                      = "https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-${var.kube_prometheus_stack_chart_version}/kube-prometheus-stack-${var.kube_prometheus_stack_chart_version}.tgz"
  namespace                  = local.monitoring_namespace
  create_namespace           = true
  wait                       = true
  timeout                    = 900
  disable_openapi_validation = true

  values = [
    file("${path.module}/values/monitoring.yaml"),
    yamlencode({
      grafana = {
        service = {
          type = var.grafana_service_type
        }
        sidecar = {
          dashboards = {
            enabled         = true
            label           = "grafana_dashboard"
            labelValue      = "1"
            searchNamespace = local.monitoring_namespace
          }
          datasources = {
            enabled         = true
            label           = "grafana_datasource"
            labelValue      = "1"
            searchNamespace = local.monitoring_namespace
          }
        }
      }
      prometheus = {
        prometheusSpec = {
          podMonitorNamespaceSelector = {
            matchNames = [
              local.application_namespace,
              local.monitoring_namespace,
            ]
          }
          podMonitorSelector = {
            matchLabels = {
              release = "monitoring"
            }
          }
          ruleNamespaceSelector = {
            matchNames = [
              local.monitoring_namespace,
            ]
          }
          ruleSelector = {
            matchLabels = {
              release = "monitoring"
            }
          }
          podMonitorSelectorNilUsesHelmValues     = false
          serviceMonitorSelectorNilUsesHelmValues = false
          ruleSelectorNilUsesHelmValues           = false
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.application]
}

resource "kubernetes_namespace_v1" "tracing" {
  metadata {
    name = local.tracing_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "tracing"
    })
  }
}

resource "kubernetes_service_v1" "prometheus_alias" {
  metadata {
    name      = "prometheus"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "prometheus-alias"
    })
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"      = "prometheus"
      "operator.prometheus.io/name" = "monitoring-kube-prometheus-prometheus"
    }

    port {
      name        = "http"
      port        = 9090
      target_port = "9090"
      protocol    = "TCP"
    }
  }

  depends_on = [helm_release.monitoring]
}

resource "kubernetes_service_v1" "grafana_alias" {
  metadata {
    name      = "grafana"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "grafana-alias"
    })
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name"     = "grafana"
      "app.kubernetes.io/instance" = "monitoring"
    }

    port {
      name        = "http"
      port        = 3000
      target_port = "3000"
      protocol    = "TCP"
    }
  }

  depends_on = [helm_release.monitoring]
}

resource "kubernetes_ingress_v1" "grafana" {
  count = var.enable_platform_ingress ? 1 : 0

  metadata {
    name      = "grafana"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "grafana"
    })

    annotations = local.platform_ingress_annotations
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.grafana_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.grafana_alias.metadata[0].name

              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = true

  timeouts {
    delete = "45m"
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_service_v1.grafana_alias,
  ]
}

resource "kubernetes_ingress_v1" "prometheus" {
  count = var.enable_platform_ingress ? 1 : 0

  metadata {
    name      = "prometheus"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "prometheus"
    })

    annotations = local.platform_ingress_annotations
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.prometheus_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.prometheus_alias.metadata[0].name

              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = true

  timeouts {
    delete = "45m"
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_service_v1.prometheus_alias,
  ]
}

resource "aws_route53_record" "grafana" {
  count = var.enable_platform_ingress ? 1 : 0

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.platform[0].zone_id
  name            = var.grafana_hostname
  type            = "CNAME"
  ttl             = 60
  records         = [kubernetes_ingress_v1.grafana[0].status[0].load_balancer[0].ingress[0].hostname]
}

resource "aws_route53_record" "prometheus" {
  count = var.enable_platform_ingress ? 1 : 0

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.platform[0].zone_id
  name            = var.prometheus_hostname
  type            = "CNAME"
  ttl             = 60
  records         = [kubernetes_ingress_v1.prometheus[0].status[0].load_balancer[0].ingress[0].hostname]
}

resource "kubernetes_service_v1" "alertmanager_alias" {
  metadata {
    name      = "alertmanager"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "alertmanager-alias"
    })
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = "alertmanager"
      alertmanager             = "monitoring-kube-prometheus-alertmanager"
    }

    port {
      name        = "http"
      port        = 9093
      target_port = "9093"
      protocol    = "TCP"
    }
  }

  depends_on = [helm_release.monitoring]
}

resource "kubernetes_config_map_v1" "grafana_datasources" {
  metadata {
    name      = "petclinic-grafana-datasources"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "petclinic-grafana-datasources"
      grafana_datasource       = "1"
    })
  }

  data = {
    "datasources.yaml" = yamlencode({
      apiVersion = 1
      deleteDatasources = [
        {
          name  = "Prometheus"
          orgId = 1
        },
        {
          name  = "Loki"
          orgId = 1
        }
      ]
      datasources = [
        {
          name     = "Prometheus"
          type     = "prometheus"
          uid      = "prometheus"
          access   = "proxy"
          url      = "http://prometheus:9090"
          editable = true
        },
        {
          name     = "Loki"
          type     = "loki"
          uid      = "loki"
          access   = "proxy"
          url      = "http://loki:3100"
          editable = true
        }
      ]
    })
  }

  depends_on = [
    helm_release.monitoring,
    kubernetes_service_v1.prometheus_alias,
    kubernetes_service_v1.loki,
  ]
}

resource "kubernetes_config_map_v1" "grafana_dashboard" {
  metadata {
    name      = "petclinic-observability-dashboard"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "petclinic-observability-dashboard"
      grafana_dashboard        = "1"
    })
  }

  data = {
    "petclinic-observability.json" = jsonencode(local.petclinic_dashboard)
  }

  depends_on = [
    helm_release.monitoring,
    kubernetes_config_map_v1.grafana_datasources,
  ]
}

resource "kubernetes_config_map_v1" "loki" {
  metadata {
    name      = "loki-config"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "loki"
    })
  }

  data = {
    "loki.yaml" = <<-YAML
      auth_enabled: false

      server:
        http_listen_port: 3100

      common:
        path_prefix: /var/loki
        storage:
          filesystem:
            chunks_directory: /var/loki/chunks
            rules_directory: /var/loki/rules
        replication_factor: 1
        ring:
          kvstore:
            store: inmemory

      query_range:
        results_cache:
          cache:
            embedded_cache:
              enabled: true
              max_size_mb: 100

      schema_config:
        configs:
          - from: "2024-01-01"
            store: tsdb
            object_store: filesystem
            schema: v13
            index:
              prefix: index_
              period: 24h

      limits_config:
        retention_period: 24h
        allow_structured_metadata: false

      compactor:
        working_directory: /var/loki/compactor
        retention_enabled: true
        delete_request_store: filesystem

      ruler:
        alertmanager_url: http://alertmanager:9093
    YAML
  }

  depends_on = [helm_release.monitoring]
}

resource "kubernetes_deployment_v1" "loki" {
  metadata {
    name      = "loki"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "loki"
    })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "loki"
      }
    }

    template {
      metadata {
        labels = merge(local.observability_labels, {
          "app.kubernetes.io/name" = "loki"
        })
      }

      spec {
        container {
          name              = "loki"
          image             = "grafana/loki:2.9.8"
          image_pull_policy = "IfNotPresent"

          args = ["-config.file=/etc/loki/loki.yaml"]

          port {
            name           = "http"
            container_port = 3100
            protocol       = "TCP"
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = "http"
            }

            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = "http"
            }

            initial_delay_seconds = 30
            period_seconds        = 20
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/loki"
          }

          volume_mount {
            name       = "storage"
            mount_path = "/var/loki"
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map_v1.loki.metadata[0].name
          }
        }

        volume {
          name = "storage"

          empty_dir {}
        }
      }
    }
  }

  depends_on = [kubernetes_config_map_v1.loki]
}

resource "kubernetes_service_v1" "loki" {
  metadata {
    name      = "loki"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "loki"
    })
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = "loki"
    }

    port {
      name        = "http"
      port        = 3100
      target_port = "http"
      protocol    = "TCP"
    }
  }

  depends_on = [kubernetes_deployment_v1.loki]
}

resource "kubernetes_service_account_v1" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "fluent-bit"
    })
  }

  depends_on = [helm_release.monitoring]
}

resource "kubernetes_cluster_role_v1" "fluent_bit" {
  metadata {
    name = "petclinic-fluent-bit"

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "fluent-bit"
    })
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "pods/log"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "fluent_bit" {
  metadata {
    name = "petclinic-fluent-bit"

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "fluent-bit"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.fluent_bit.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.fluent_bit.metadata[0].name
    namespace = local.monitoring_namespace
  }
}

resource "kubernetes_config_map_v1" "fluent_bit" {
  metadata {
    name      = "fluent-bit-config"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "fluent-bit"
    })
  }

  data = {
    "fluent-bit.conf" = <<-CONF
      [SERVICE]
          Flush         1
          Daemon        Off
          Log_Level     info
          Parsers_File  parsers.conf
          HTTP_Server   On
          HTTP_Listen   0.0.0.0
          HTTP_Port     2020

      [INPUT]
          Name              tail
          Tag               kube.*
          Path              /var/log/containers/*.log
          multiline.parser  docker, cri
          Mem_Buf_Limit     50MB
          Skip_Long_Lines   On
          Refresh_Interval  10

      [FILTER]
          Name                kubernetes
          Match               kube.*
          Kube_URL            https://kubernetes.default.svc:443
          Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
          Merge_Log           On
          Keep_Log            Off
          K8S-Logging.Parser  On
          K8S-Logging.Exclude On

      [OUTPUT]
          Name                  loki
          Match                 kube.*
          Host                  loki
          Port                  3100
          Labels                job=fluent-bit
          Label_Keys            $kubernetes['namespace_name'],$kubernetes['pod_name'],$kubernetes['container_name']
          Auto_Kubernetes_Labels On
          Line_Format           json
    CONF

    "parsers.conf" = <<-CONF
      [PARSER]
          Name        docker
          Format      json
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L
          Time_Keep   On

      [PARSER]
          Name        cri
          Format      regex
          Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
          Time_Key    time
          Time_Format %Y-%m-%dT%H:%M:%S.%L%z
    CONF
  }

  depends_on = [helm_release.monitoring]
}

resource "kubernetes_daemon_set_v1" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = local.monitoring_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "fluent-bit"
    })
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = merge(local.observability_labels, {
          "app.kubernetes.io/name" = "fluent-bit"
        })
      }

      spec {
        service_account_name             = kubernetes_service_account_v1.fluent_bit.metadata[0].name
        termination_grace_period_seconds = 10

        container {
          name              = "fluent-bit"
          image             = "cr.fluentbit.io/fluent/fluent-bit:3.2.10"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = 2020
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc"
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map_v1.fluent_bit.metadata[0].name
          }
        }

        volume {
          name = "varlog"

          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"

          host_path {
            path = "/var/lib/docker/containers"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_cluster_role_binding_v1.fluent_bit,
    kubernetes_config_map_v1.fluent_bit,
    kubernetes_service_v1.loki,
  ]
}

resource "kubernetes_deployment_v1" "zipkin" {
  metadata {
    name      = "zipkin"
    namespace = local.tracing_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "zipkin"
    })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "zipkin"
      }
    }

    template {
      metadata {
        labels = merge(local.observability_labels, {
          "app.kubernetes.io/name" = "zipkin"
        })
      }

      spec {
        container {
          name              = "zipkin"
          image             = "openzipkin/zipkin:3.4"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = 9411
            protocol       = "TCP"
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }

            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }

            initial_delay_seconds = 30
            period_seconds        = 20
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "768Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.tracing]
}

resource "kubernetes_service_v1" "zipkin" {
  metadata {
    name      = "zipkin"
    namespace = local.tracing_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "zipkin"
    })
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/name" = "zipkin"
    }

    port {
      name        = "http"
      port        = 9411
      target_port = "http"
      protocol    = "TCP"
    }
  }

  depends_on = [kubernetes_deployment_v1.zipkin]
}

resource "kubernetes_ingress_v1" "zipkin" {
  count = var.enable_platform_ingress ? 1 : 0

  metadata {
    name      = "zipkin"
    namespace = local.tracing_namespace

    labels = merge(local.observability_labels, {
      "app.kubernetes.io/name" = "zipkin"
    })

    annotations = merge(local.platform_ingress_annotations, {
      "alb.ingress.kubernetes.io/certificate-arn"  = coalesce(var.zipkin_certificate_arn, var.platform_certificate_arn)
      "alb.ingress.kubernetes.io/healthcheck-path" = "/health"
      "alb.ingress.kubernetes.io/success-codes"    = "200-399"
    })
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.zipkin_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.zipkin.metadata[0].name

              port {
                number = 9411
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = true

  timeouts {
    delete = "45m"
  }

  depends_on = [
    helm_release.aws_load_balancer_controller,
    kubernetes_service_v1.zipkin,
  ]
}

resource "aws_route53_record" "zipkin" {
  count = var.enable_platform_ingress ? 1 : 0

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.platform[0].zone_id
  name            = var.zipkin_hostname
  type            = "CNAME"
  ttl             = 60
  records         = [kubernetes_ingress_v1.zipkin[0].status[0].load_balancer[0].ingress[0].hostname]
}

resource "helm_release" "monitoring_rules" {
  name      = "petclinic-monitoring-rules"
  chart     = local.raw_manifests_chart
  namespace = local.monitoring_namespace
  wait      = true
  timeout   = 300

  values = [
    yamlencode({
      objects = [
        local.petclinic_alert_rules_manifest
      ]
    })
  ]

  depends_on = [helm_release.monitoring]
}
