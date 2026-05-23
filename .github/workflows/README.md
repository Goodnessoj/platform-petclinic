# Workflow Files

The YAML files in this folder are the executable GitHub Actions definitions for
the platform.

## File Guide

- `platform.yaml`: Terraform workflow for the platform environments. Manual
  dispatch selects `dev` or `prod` and supports `plan`, `apply`, and
  `destroy`; pull requests and pushes run plan-only checks against `dev`.
  Before Terraform refreshes Kubernetes resources, it ensures the selected EKS
  cluster grants the workflow role cluster-admin access through EKS access
  entries. Apply runs can bootstrap runtime secrets and apply/refresh Petclinic
  Argo CD Applications, but do not wait for workload health. Destroy runs also
  set up kubectl, remove GitOps-owned Applications, ExternalSecrets, ingresses,
  and TargetGroupBindings, destroy
  Terraform-managed platform ingress/DNS resources first, optionally force-delete
  leftover cluster ALBs and VPC dependencies, then wait for all ACM certificates
  to detach before running a fresh Terraform destroy.
- `deploy-argocd.yml`: verifies the Terraform-managed Argo CD install, applies
  the Petclinic AppProject and Applications, then optionally waits for health.
  It is triggered by image tag update dispatches or manual dispatch, not by
  pushes to `main`.
- `update-image-tags.yaml`: listens for `repository_dispatch` events from the
  application build pipeline and writes new image tags into `helm-values`.
- `deploy-services.yaml`: deploys one or more services directly with Helm. It
  also ensures shared runtime secrets exist before deploying workloads.

## Dependency Order

Both Argo CD and direct Helm deployment respect the service dependency order:

```text
config-server
discovery-server
customers-service
vets-service
visits-service
genai-service
api-gateway
admin-server
```

`config-server` must come first because other services read configuration from
it. `discovery-server` follows because application services register with
Eureka. Edge and admin components deploy after the backing services.

## State Safety

If Terraform completes real work but cannot write remote state, it writes
`errored.tfstate` in the affected environment directory. Do not rerun apply or
destroy until the backend is restored and the recovered state has been pushed
with `terraform state push errored.tfstate`.

## Platform Apply Requirements

The `platform.yaml` workflow assumes the bootstrap-created GitHub Actions role.
Keep `terraform/environments/bootstrap` applied before running platform apply or
destroy. The role must be able to read and create AWS service-linked roles; EKS
managed node group creation checks `AWSServiceRoleForAmazonEKSNodegroup` with
`iam:GetRole`.

`platform.yaml` can bootstrap GitOps only when `OPENAI_API_KEY` is configured as
a GitHub secret. Local Terraform does not receive that secret. Petclinic Argo CD
Application health is gated by `deploy-argocd.yml`, not by the platform
workflow.
