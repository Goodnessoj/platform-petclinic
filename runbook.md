# Petclinic Platform Runbook

This runbook covers day-2 operation of the `platform-petclinic` repository:
Terraform-managed AWS infrastructure, EKS add-ons, Helm charts, Argo CD
Applications, and the GitHub Actions workflows that connect them.

## Quick Facts

| Item | Value |
| --- | --- |
| AWS account | `974263620909` |
| Default AWS region | `us-east-2` |
| Terraform version in CI | `1.10.5` |
| Dev cluster | `petclinic-dev-eks` |
| Prod cluster | `petclinic-prod-eks` |
| Dev namespace | `petclinic-dev` |
| Prod namespace | `petclinic-prod` |
| Argo CD namespace | `argocd` |
| Terraform state bucket | `petclinic-tfstate-974263620909` |
| GitHub Actions role | `arn:aws:iam::974263620909:role/petclinic-github-actions-role` |
| Preferred GitHub secret | `AWS_ROLE_ARN` |

Supported Petclinic services:

```text
config-server discovery-server customers-service vets-service visits-service genai-service api-gateway admin-server
```

## Before You Start

Required local tools for manual operations:

- `aws`
- `terraform`
- `kubectl`
- `helm`
- `jq`

Confirm AWS identity before changing infrastructure:

```bash
aws sts get-caller-identity
```

Configure kubeconfig:

```bash
aws eks update-kubeconfig --region us-east-2 --name petclinic-dev-eks
kubectl config current-context
kubectl get nodes
```

Use `petclinic-prod-eks` for production.

## GitHub Actions Configuration

Required repository or environment settings:

| Name | Type | Purpose |
| --- | --- | --- |
| `AWS_ROLE_ARN` | Secret preferred, variable also works | IAM role assumed by GitHub Actions through OIDC. |
| `AWS_REGION` | Variable | AWS region. Defaults to `us-east-2` when unset. |
| `OPENAI_API_KEY` | Secret | Creates `openai-secret` for `genai-service`. |
| `ARGOCD_REPO_TOKEN` | Secret, optional | Lets Argo CD access a private repository. |
| `GITOPS_PAT` | Secret, optional | Used when the default `GITHUB_TOKEN` cannot push tag updates or dispatch workflows. |
| `EKS_CLUSTER_NAME` | Variable, optional | Overrides the default service deployment cluster name. |
| `K8S_NAMESPACE` | Variable, optional | Overrides the default service deployment namespace. |
| `DOMAIN_NAME` or `APP_DOMAIN_NAME` | Variable, optional | Public app hostname for service deployment. |
| `ACM_CERTIFICATE_ARN` | Variable, optional | Certificate for `api-gateway` ingress in service deployment. |

The workflows use `AWS_ROLE_ARN`, falling back to `AWS_ROLE_TO_ASSUME`, then
`vars.AWS_ROLE_ARN`.

## Normal Operations

### Plan Infrastructure

Use the `Platform` workflow:

- File: `.github/workflows/platform.yaml`
- Input `environment`: `dev` or `prod`
- Input `action`: `plan`

Local equivalent:

```bash
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev validate -no-color
terraform -chdir=terraform/environments/dev plan -var-file=terraform.tfvars
```

### Apply Infrastructure

Use the `Platform` workflow:

- Input `environment`: `dev` or `prod`
- Input `action`: `apply`
- Input `bootstrap_runtime_secrets`: `true` for initial cluster bootstrapping or
  when runtime secrets should be refreshed.

The workflow also ensures the GitHub Actions IAM role has EKS access, creates
or updates runtime secrets, and installs the shared secrets chart. It does not
apply Petclinic Argo CD Applications.

### Deploy Argo CD Applications

Use the `Deploy ArgoCD Applications` workflow:

- File: `.github/workflows/deploy-argocd.yml`
- Trigger: image tag update dispatch or manual dispatch

This verifies the Terraform-managed Argo CD install, applies the Petclinic
AppProject and Applications, and waits for selected apps to become `Synced` and
`Healthy`.

Manual apply:

```bash
kubectl apply -f k8s/argocd/applications/project.yaml
kubectl apply -k k8s/argocd/applications/dev
```

Use `k8s/argocd/applications/prod` for production.

### Deploy Services Imperatively

Use the `Deploy Changed Petclinic Services` workflow when GitOps needs a manual
push or recovery path:

- File: `.github/workflows/deploy-services.yaml`
- Input `environment`: `dev` or `prod`
- Input `services`: `all` or a space-separated list, for example
  `customers-service vets-service`

Services deploy in dependency order:

```text
config-server discovery-server customers-service vets-service visits-service genai-service api-gateway admin-server
```

### Image Tag Flow

The normal application release path is:

1. Application CI builds and pushes service images to ECR.
2. Application CI sends a `repository_dispatch` event with type
   `app-image-built`.
3. `.github/workflows/update-image-tags.yaml` updates `helm-values/<service>.yaml`.
4. The workflow commits the tag change to `main`.
5. The workflow dispatches `Deploy ArgoCD`.
6. Argo CD reconciles the service Applications.

Check the committed image tag:

```bash
rg -n "tag:" helm-values
```

## Health Checks

Cluster and namespace:

```bash
kubectl get nodes
kubectl get ns
kubectl get pods -n petclinic-dev -o wide
kubectl get svc -n petclinic-dev
kubectl get ingress -n petclinic-dev
```

Argo CD:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd -o wide
kubectl describe application api-gateway-dev -n argocd
```

External Secrets:

```bash
kubectl get pods -n external-secrets
kubectl get crd externalsecrets.external-secrets.io
kubectl get crd clustersecretstores.external-secrets.io
kubectl get clustersecretstore aws-secrets-manager
kubectl get externalsecret -n petclinic-dev
kubectl get secret mysql-secret -n petclinic-dev
kubectl get secret openai-secret -n petclinic-dev
```

Helm releases:

```bash
helm list -n petclinic-dev --all
helm status api-gateway -n petclinic-dev
helm status petclinic-secrets -n petclinic-dev
```

Events and logs:

```bash
kubectl get events -n petclinic-dev --sort-by=.lastTimestamp
kubectl logs -n petclinic-dev deploy/api-gateway --tail=100
kubectl describe pod -n petclinic-dev -l app.kubernetes.io/instance=api-gateway
```

## Troubleshooting

### GitHub Actions Cannot Assume AWS Role

Symptoms:

- `configure-aws-credentials` fails.
- `aws sts get-caller-identity` never runs or returns an unexpected identity.

Checks:

```bash
rg -n "AWS_ROLE_ARN|AWS_ROLE_TO_ASSUME|role-to-assume" .github/workflows
```

Fixes:

- Confirm GitHub secret `AWS_ROLE_ARN` is set to
  `arn:aws:iam::974263620909:role/petclinic-github-actions-role`.
- Confirm workflow permissions include `id-token: write`.
- Confirm the bootstrap Terraform root still owns the GitHub OIDC provider and
  role.

### EKS Access Denied

Symptoms:

- `kubectl auth can-i get namespaces` fails.
- Terraform or Argo CD deploy workflows can assume AWS but cannot administer the
  cluster.

Checks:

```bash
aws eks describe-cluster --region us-east-2 --name petclinic-dev-eks \
  --query 'cluster.accessConfig.authenticationMode'

aws eks list-access-entries --region us-east-2 --cluster-name petclinic-dev-eks
```

The `Platform` and `Deploy ArgoCD` workflows create or update an EKS access
entry for the current GitHub Actions role. Rerun the relevant workflow after
confirming `AWS_ROLE_ARN`.

### Terraform State Or Lock Problems

Do not destroy the bootstrap root during routine rebuilds. It owns the durable
state bucket and GitHub OIDC resources.

If Terraform reports `Failed to persist state to backend`, do not run another
apply first. Restore the backend bucket if needed, then push the recovery state:

```bash
terraform -chdir=terraform/environments/dev state push errored.tfstate
```

If a lock is stuck, inspect it before force-unlocking:

```bash
terraform -chdir=terraform/environments/dev force-unlock <LOCK_ID>
```

Use `prod` only when the stuck lock definitely belongs to the production root.

### External Secrets Or Database Secret Missing

Symptoms:

- `mysql-secret` is missing.
- Services fail startup because database credentials are unavailable.
- `petclinic-secrets` Helm release fails.

Checks:

```bash
kubectl get clustersecretstore aws-secrets-manager -o yaml
kubectl get externalsecret petclinic-db-secret -n petclinic-dev -o yaml
kubectl describe externalsecret petclinic-db-secret -n petclinic-dev
kubectl get secret mysql-secret -n petclinic-dev
```

Fixes:

- Apply the Terraform platform/addons layer if External Secrets CRDs or
  `ClusterSecretStore/aws-secrets-manager` are missing.
- Confirm the secrets values file points to the expected AWS Secrets Manager
  name:

```bash
cat helm-values/secrets-dev.yaml
```

### OpenAI Secret Missing

Symptoms:

- `genai-service` is unhealthy.
- `openai-secret` is missing or empty.

Checks:

```bash
kubectl get secret openai-secret -n petclinic-dev
kubectl describe pod -n petclinic-dev -l app.kubernetes.io/instance=genai-service
```

Fixes:

- Confirm GitHub secret `OPENAI_API_KEY` is set.
- Rerun `Platform` apply with `bootstrap_runtime_secrets=true`, `Deploy ArgoCD
  Applications`, or `Deploy Changed Petclinic Services`.

### Argo CD Application Degraded Or Out Of Sync

Checks:

```bash
kubectl get application -n argocd -o wide
kubectl describe application api-gateway-dev -n argocd
kubectl get pods -n petclinic-dev -o wide
kubectl get events -n petclinic-dev --sort-by=.lastTimestamp
```

Refresh one Application:

```bash
kubectl annotate application api-gateway-dev \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```

Dev Applications auto-sync. Prod Applications are manual by design; sync prod
only after reviewing the diff.

### Helm Release Stuck

Symptoms:

- Helm status is `failed`, `pending-install`, `pending-upgrade`,
  `pending-rollback`, `uninstalling`, or `uninstalled`.

Checks:

```bash
helm status api-gateway -n petclinic-dev
kubectl get secret -n petclinic-dev -l owner=helm,name=api-gateway
```

Recovery:

```bash
helm uninstall api-gateway -n petclinic-dev --no-hooks
kubectl delete secret -n petclinic-dev -l owner=helm,name=api-gateway
```

Then rerun the service deploy or let Argo CD reconcile.

### Public Endpoint Missing

Checks:

```bash
kubectl get ingress -n petclinic-dev
kubectl describe ingress api-gateway -n petclinic-dev
kubectl get pods -n kube-system | rg "aws-load-balancer|external-dns"
```

Common causes:

- AWS Load Balancer Controller is not installed or unhealthy.
- `ACM_CERTIFICATE_ARN` is missing when ingress is enabled.
- DNS is not enabled or ExternalDNS is not managing the hostname.
- The service deployed as `LoadBalancer` because `DOMAIN_NAME` and
  `ACM_CERTIFICATE_ARN` were not set for the imperative deploy workflow.

### Image Tag Did Not Deploy

Checks:

```bash
rg -n "tag:" helm-values/<service>.yaml
kubectl get application <service>-dev -n argocd -o yaml
kubectl describe pod -n petclinic-dev -l app.kubernetes.io/instance=<service>
```

Fixes:

- Confirm the application pipeline sent `repository_dispatch` type
  `app-image-built`.
- Confirm `update-image-tags.yaml` committed the expected tag.
- Refresh or sync the Argo CD Application.
- Use `Deploy Changed Petclinic Services` as a recovery path if GitOps is
  blocked.

## Rollback

For service rollback, revert the image tag change in `helm-values/<service>.yaml`
and deploy through the normal GitOps path.

Fast path:

```bash
git log --oneline -- helm-values/<service>.yaml
git revert <commit_sha>
git push
```

Then refresh the Argo CD Application:

```bash
kubectl annotate application <service>-dev \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```

For production, review the rollback diff and sync manually.

## Destroy And Rebuild

Use the `Platform` workflow for environment teardown:

- Input `environment`: `dev` or `prod`
- Input `action`: `destroy`
- Input `force_destroy_cleanup`: `true` for normal teardown

The workflow pre-cleans Argo CD Applications, ingresses, stale ExternalSecret
finalizers, TargetGroupBindings, leftover load balancers, and VPC dependencies
before running Terraform destroy.

Do not destroy `terraform/environments/bootstrap` during routine rebuilds.

Local dev rebuild, when GitHub Actions is unavailable:

```bash
terraform -chdir=terraform/environments/dev destroy -var-file=terraform.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=terraform.tfvars
```

Prefer the workflow for destroy because it contains the Kubernetes and AWS
cleanup steps that prevent dangling ALBs, target groups, and finalizers from
blocking Terraform.

## Useful References

- `.github/README.md`
- `.github/workflows/platform.yaml`
- `.github/workflows/deploy-argocd.yml`
- `.github/workflows/deploy-services.yaml`
- `.github/workflows/update-image-tags.yaml`
- `terraform/environments/bootstrap/README.md`
- `terraform/environments/dev/README.md`
- `terraform/environments/prod/README.md`
- `helm-values/README.md`
- `helm/README.md`
- `k8s/argocd/README.md`
