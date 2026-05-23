# Add-Ons Module

This module installs Kubernetes platform add-ons into the EKS cluster.

## What It Installs

- Application namespace from the root environment.
- External Secrets Operator.
- `ClusterSecretStore` named `aws-secrets-manager`.
- AWS Load Balancer Controller.
- Optional ExternalDNS.
- Argo CD.
- Optional ALB ingress and Route 53 record for Argo CD.
- kube-prometheus-stack.
- Grafana service alias, optional ALB ingress, and Route 53 record.
- Prometheus service alias, optional ALB ingress, and Route 53 record.
- Alertmanager service alias.
- Loki deployment and service.
- Fluent Bit log collection into Loki.
- Zipkin deployment, service, optional ALB ingress, and Route 53 record.
- Grafana datasource and Petclinic dashboard ConfigMaps.
- Petclinic Prometheus alert rules.
- Optional Argo CD repository credentials secret.

## Required Inputs

Key inputs:

- `cluster_name`
- `aws_region`
- `vpc_id`
- `application_namespace`
- `oidc_provider_arn`
- `oidc_provider_url`
- `external_secrets_role_arn`
- `aws_load_balancer_controller_role_arn`

When platform ingress is enabled:

- `root_domain_name`
- `argocd_hostname`
- `grafana_hostname`
- `prometheus_hostname`
- `zipkin_hostname`
- `platform_certificate_arn`
- `platform_alb_group_name`
- `platform_alb_name`

Optional chart version inputs can pin External Secrets, AWS Load Balancer
Controller, ExternalDNS, kube-prometheus-stack, and Argo CD.

## Helm Apply Behavior

External Secrets, Argo CD, and kube-prometheus-stack are CRD-heavy charts. Their
Helm releases disable OpenAPI validation so a slow EKS `/openapi/v2` response
does not fail an otherwise valid apply. Helm still renders the charts, submits
the resources to Kubernetes, and waits for release readiness.

## Namespaces

The module uses these namespaces:

- `external-secrets`
- `kube-system`
- `argocd`
- `monitoring`
- `tracing`
- application namespace from `application_namespace`

## External Secrets

The module installs External Secrets Operator and creates a
`ClusterSecretStore` that reads AWS Secrets Manager in the configured region
using IRSA.

The shared `helm/petclinic-secrets` chart creates application-level
`ExternalSecret` resources that point to this store.

When the OpenAI API key lives only in GitHub Secrets, the platform workflow
creates the Kubernetes `openai-secret` directly and installs the shared secrets
chart with `openai.enabled=false`. That keeps the OpenAI key out of Terraform
state-managed secret versions.

## Monitoring

The module installs kube-prometheus-stack and configures Prometheus selectors so
`PodMonitor` resources with label `release=monitoring` can be discovered in the
application namespace.

It also deploys a lightweight Loki instance and configures Grafana datasources
for Prometheus and Loki. Fluent Bit tails Kubernetes container logs and sends
them to Loki.

Alertmanager is configured with a visible `petclinic-alerts` receiver for
Petclinic application alerts. The receiver does not send external notifications
until a real webhook, Slack, email, or pager integration is added, but alerts
are grouped and visible in Alertmanager instead of being routed to `null`.

The module manages five Petclinic alert rules:

- `PetclinicHighErrorRate`: HTTP 5xx ratio above 5% for 5 minutes.
- `PetclinicPodRestartLoop`: more than 5 restarts in 15 minutes.
- `PetclinicHighMemoryUsage`: container memory above 80% of its limit.
- `PetclinicServiceDown`: no successful Prometheus scrape for 2 minutes.
- `PetclinicSlowP99ResponseTime`: P99 latency above 2 seconds for 5 minutes.

The module also deploys Zipkin at `zipkin.tracing:9411`, which matches the
tracing environment variables in the service values files. When platform
ingress is enabled, the Zipkin UI is also exposed through `zipkin_hostname`.

## Outputs

- `external_secrets_role_arn`
- `aws_load_balancer_controller_role_arn`
- `external_dns_role_arn`
- `monitoring_namespace`
- `argocd_namespace`
- `argocd_hostname`
- `grafana_hostname`
- `prometheus_hostname`
- `zipkin_hostname`
- `application_namespace`

## Destroy Behavior

The application namespace depends on External Secrets Operator so Terraform
destroys application ExternalSecret resources before uninstalling the controller.
The platform workflow also removes GitOps Applications, ingresses, stale
ExternalSecret finalizers, and TargetGroupBindings before Terraform destroys the
cluster. It can also force-delete leftover cluster ALBs and VPC dependencies,
then waits for platform ACM certificates to detach from ALB listeners so
certificate deletion does not race the AWS Load Balancer Controller cleanup.

## Verification

```bash
kubectl get pods -n external-secrets
kubectl get clustersecretstore aws-secrets-manager
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get prometheusrule -n monitoring petclinic-alert-rules
kubectl get --raw /api/v1/namespaces/monitoring/services/http:prometheus:9090/proxy/api/v1/rules
kubectl get --raw /api/v1/namespaces/monitoring/services/http:alertmanager:9093/proxy/api/v2/status
kubectl get --raw /api/v1/namespaces/monitoring/services/http:alertmanager:9093/proxy/api/v2/alerts
```
