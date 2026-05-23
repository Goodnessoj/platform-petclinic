# Platform Petclinic Infrastructure

This repository contains the infrastructure and GitOps configuration for running
the Spring Petclinic microservices platform on AWS EKS.

Repository name: `Goodnessoj/platform-petclinic`.

The active deployment path is:

1. Terraform creates the AWS platform: remote state, GitHub OIDC, VPC, EKS, ECR,
   RDS MySQL, Secrets Manager entries, platform add-ons, DNS, and observability.
2. Helm charts describe the Petclinic services and shared runtime secrets.
3. Argo CD applies one Helm release per service from this repository.
4. GitHub Actions applies Terraform, updates image tags, dispatches Argo CD
   deploys, and can deploy selected services in dependency order.

## Repository Layout

| Path | Purpose |
| --- | --- |
| [`.github/`](.github/README.md) | GitHub Actions workflows for Terraform, Argo CD, image tag updates, and service deployment. |
| [`terraform/`](terraform/README.md) | Terraform roots and reusable modules for AWS infrastructure. |
| [`helm/`](helm/README.md) | Helm charts for service workloads and shared ExternalSecret resources. |
| [`helm-values/`](helm-values/README.md) | Environment and service-specific values consumed by Helm and Argo CD. |
| [`k8s/`](k8s/README.md) | Raw Kubernetes/Kustomize reference manifests plus the active Argo CD Application definitions. |
| [`scripts/`](scripts/README.md) | Local helper scripts for Terraform backend and AWS/ECR tasks. |
| [`runbook.md`](runbook.md) | Day-2 operations runbook for deploys, health checks, rollback, and teardown. |

## Platform Components

- **AWS account and region:** the current defaults target `us-east-2`.
- **Terraform state:** S3 backend bucket `petclinic-tfstate-974263620909`,
  created by the durable bootstrap root.
- **GitHub identity:** GitHub Actions assumes `petclinic-github-actions-role`
  through AWS OIDC.
- **Networking:** one VPC with public subnets tagged for EKS load balancers.
- **Compute:** EKS cluster and managed node group.
- **Images:** one ECR repository per service.
- **Database:** RDS MySQL with generated credentials stored in Secrets Manager.
- **Secrets:** External Secrets Operator reads AWS Secrets Manager into
  Kubernetes secrets such as `mysql-secret`. The OpenAI runtime secret is
  created directly by GitHub Actions from the `OPENAI_API_KEY` GitHub secret
  when runtime secret bootstrap or the Argo CD deploy workflow runs.
- **Ingress and DNS:** AWS Load Balancer Controller, optional ExternalDNS, ACM,
  Route 53 records, and ALB-backed ingresses for the app, Argo CD, Grafana,
  Prometheus, and selected dev service dashboards.
- **Observability:** CloudWatch log groups, kube-prometheus-stack, Grafana,
  Loki, Fluent Bit, Zipkin, Prometheus alert rules, and a Petclinic Grafana
  dashboard.
- **GitOps:** Argo CD manages service Helm releases for dev and prod.

## Prerequisites

For local platform work, install and configure:

- AWS CLI with credentials that can manage IAM, EKS, ECR, RDS, S3, ACM, Route 53,
  Secrets Manager, and related networking resources.
- Terraform `>= 1.5.0`.
- `kubectl`.
- Helm 3.
- Access to the target Route 53 hosted zone when DNS ingress is enabled.

GitHub Actions also expects:

- `AWS_ROLE_ARN` or `AWS_ROLE_TO_ASSUME` as a secret or variable.
- `OPENAI_API_KEY` for GenAI runtime deployments.
- Optional `ARGOCD_REPO_TOKEN` or `GITOPS_PAT` when private repository access or
  tag update pushes need a token beyond the default `GITHUB_TOKEN`.

The AWS role used by GitHub Actions is created by the bootstrap Terraform root.
Keep that bootstrap root applied before running `platform.yaml`; the role needs
platform permissions such as `iam:GetRole` and `iam:CreateServiceLinkedRole` so
EKS can create managed node groups.

## Bootstrap Order

Run the durable bootstrap root first. It creates the remote state bucket and the
GitHub Actions role:

```bash
terraform -chdir=terraform/environments/bootstrap init
terraform -chdir=terraform/environments/bootstrap plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/bootstrap apply -var-file=terraform.tfvars
```

Then apply the environment platform:

```bash
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=terraform.tfvars
```

Local Terraform apply creates the AWS and Kubernetes platform, but it cannot
read GitHub Secrets. To create `openai-secret` and install the shared
application secrets chart during platform apply, run the `Platform` workflow
with `action=apply` and `bootstrap_runtime_secrets=true`. The platform workflow
does not apply Petclinic Argo CD Applications; `deploy-argocd.yml` owns that
deploy and health gate after image tag updates.

After the dev platform is available, configure local Kubernetes access:

```bash
aws eks update-kubeconfig --region us-east-2 --name petclinic-dev-eks
kubectl get nodes
```

## Deploying Applications

This repo keeps the raw Kubernetes manifests that were built before the
deployment moved to Helm. They live under `k8s/base` with dev/prod overlays
under `k8s/overlays`. They are useful for review and for understanding the
Kubernetes shape, but the active deployment path is Helm through Argo CD.

Argo CD is installed by Terraform through the add-ons module. The dev
applications can also be applied manually:

```bash
kubectl apply -f k8s/argocd/applications/project.yaml
kubectl apply -k k8s/argocd/applications/dev
```

Dev Argo CD applications sync automatically with prune and self-heal enabled.
Prod applications are configured for manual sync.

The service image tags live in `helm-values/<service>.yaml`. The
`Update Image Tags` workflow receives build notifications, updates those values,
commits the change to `main`, and dispatches the Argo CD deploy workflow. The
Argo CD deploy workflow can also be run manually, but it is not triggered
directly by pushes to `main`.

The workflow definitions live under `.github/workflows`:

- `platform.yaml`
- `deploy-argocd.yml`
- `update-image-tags.yaml`
- `deploy-services.yaml`

## Useful Commands

Format and validate Terraform:

```bash
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev validate -no-color
```

Render a service Helm chart:

```bash
helm template api-gateway helm/petclinic-service \
  --namespace petclinic-dev \
  -f helm-values/dev.yaml \
  -f helm-values/api-gateway.yaml
```

Inspect Argo CD applications:

```bash
kubectl get applications -n argocd -o wide
```

Inspect Petclinic workloads:

```bash
kubectl get pods,svc,ingress -n petclinic-dev
```

Dev DNS endpoints, when DNS ingress is enabled:

```text
https://petclinic.phoniex.site
https://petclinic.phoniex.site/admin
https://eureka.phoniex.site
https://discovery.phoniex.site
https://argocd.phoniex.site
https://grafana.phoniex.site
https://prometheus.phoniex.site
https://zipkin.phoniex.site
```

Verify alerting without port-forwarding:

```bash
kubectl get prometheusrule -n monitoring petclinic-alert-rules
kubectl get --raw /api/v1/namespaces/monitoring/services/http:prometheus:9090/proxy/api/v1/rules
kubectl get --raw /api/v1/namespaces/monitoring/services/http:alertmanager:9093/proxy/api/v2/status
kubectl get --raw /api/v1/namespaces/monitoring/services/http:alertmanager:9093/proxy/api/v2/alerts
```

## Safety Notes

- Do not destroy `terraform/environments/bootstrap` during normal environment
  rebuilds. It owns the Terraform state bucket and GitHub Actions OIDC role.
- For dev destroy/reapply, prefer the `Platform` workflow. It performs
  Kubernetes cleanup before Terraform destroys EKS and VPC resources, then the
  apply path can bootstrap GitOps with GitHub-only secrets.
- If Terraform reports `Failed to persist state to backend` and writes
  `errored.tfstate`, do not run apply again first. Restore the backend bucket,
  then run `terraform state push errored.tfstate` from the affected root.
- `terraform.tfvars` files are no longer ignored by Git. Commit only sanitized
  values; keep credentials in GitHub secrets, your local shell, or another
  controlled secret source.
- Terraform state files such as `terraform.tfstate` and `errored.tfstate` are
  ignored by Git because they can contain secrets.
- The `terraform/modules/ecr` module uses `force_delete = true`; repository
  destruction will remove images.
- The prod Terraform root now has production-oriented variable defaults and
  outputs, but you should still review capacity, DNS names, and secret handling
  before a real production apply.
