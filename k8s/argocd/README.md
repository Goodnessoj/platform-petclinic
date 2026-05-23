# Argo CD GitOps

This folder contains the GitOps configuration for the Petclinic services.

## Structure

| Path | Purpose |
| --- | --- |
| [`applications`](applications/README.md) | AppProject and Argo CD Applications for dev and prod. |
| [`install`](install/README.md) | Fallback Argo CD installation layer for clusters that are not Helm-managed by Terraform. |

## Installation Model

For this EKS cluster, Argo CD is installed by the Terraform `addons` module with
the `argo-cd` Helm chart. Re-apply Terraform when you need to install or upgrade
the Terraform-managed Argo CD release.

The `install/` folder vendors a fallback install manifest. Do not apply that
layer over the Terraform-managed `argocd` Helm release.

## Applications

The applications layer registers one Argo CD Application per service:

- `config-server`
- `discovery-server`
- `customers-service`
- `vets-service`
- `visits-service`
- `genai-service`
- `api-gateway`
- `admin-server`

Dev Applications sync automatically with prune and self-heal enabled. Prod
Applications use manual sync.

## Value File Order

The Helm value files are intentionally ordered as environment first, service
second:

```yaml
valueFiles:
  - ../../helm-values/dev.yaml
  - ../../helm-values/customers-service.yaml
```

Argo CD and Helm merge later files last. This repository stores service image
repositories and tags in the per-service values files.

## Runtime Prerequisites

Before services become healthy:

- `mysql-secret` must exist in the target namespace, normally created by
  External Secrets from AWS Secrets Manager.
- `openai-secret` must exist in the target namespace for `genai-service`.
- `ClusterSecretStore/aws-secrets-manager` must exist.
- The AWS Load Balancer Controller must exist when ingress is enabled.

The GitHub `Platform` workflow with `bootstrap_runtime_secrets=true` creates
`openai-secret` from the `OPENAI_API_KEY` GitHub secret and installs the shared
database secrets chart, but it does not apply these Argo CD Applications.
`deploy-argocd.yml` applies them after image tag updates. If you apply this
folder manually after a local Terraform apply, create `openai-secret` first or
leave `genai-service` unsynced until the secret exists.

## Manual Apply

Apply only the dev GitOps layer:

```bash
kubectl apply -f k8s/argocd/applications/project.yaml
kubectl apply -k k8s/argocd/applications/dev
```

Apply only the prod GitOps layer:

```bash
kubectl apply -f k8s/argocd/applications/project.yaml
kubectl apply -k k8s/argocd/applications/prod
```

## UI Access

Open the Argo CD UI through DNS after the Terraform add-ons layer applies:

```text
https://argocd.phoniex.site
```

Local fallback:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Then browse to:

```text
https://localhost:8080
```

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```
