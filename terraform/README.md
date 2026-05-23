# Terraform

This folder contains the Terraform code that provisions the AWS infrastructure
for the Petclinic platform.

## Structure

| Path | Purpose |
| --- | --- |
| [`environments/`](environments/README.md) | Root modules for durable bootstrap infrastructure and deployable environments. |
| [`modules/`](modules/README.md) | Reusable modules for VPC, EKS, ECR, RDS, DNS, secrets, observability, GitHub OIDC, and platform add-ons. |

## Environment Roots

- `environments/bootstrap`: durable foundation for Terraform state and GitHub
  Actions OIDC. Do not destroy this root during routine rebuilds.
- `environments/dev`: active dev platform root.
- `environments/prod`: production platform root with prod-oriented defaults,
  outputs, and a separate remote state key.

## Remote State

The checked-in backends point to S3 keys:

| Environment | State key |
| --- | --- |
| Bootstrap | `petclinic/bootstrap/terraform.tfstate` |
| Dev | `petclinic/dev/terraform.tfstate` |
| Prod | `petclinic/prod/terraform.tfstate` |

The state bucket is created by the bootstrap root and is currently named
`petclinic-tfstate-974263620909`.

Do not destroy the bootstrap root during routine rebuilds. If a platform apply
or destroy reports `Failed to persist state to backend`, Terraform writes
`errored.tfstate` in the affected root. Restore the S3 backend bucket first,
then push the recovery file with:

```bash
terraform -chdir=terraform/environments/dev state push errored.tfstate
```

## Standard Workflow

Run Terraform from the repository root with `-chdir`:

```bash
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev validate -no-color
terraform -chdir=terraform/environments/dev plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=terraform.tfvars
```

`terraform.tfvars` contains environment-specific variable values used by local
runs and the platform workflow when the file exists.

Local applies are useful for infrastructure repair and validation, but they do
not have access to GitHub Secrets. If `create_openai_secret = false`, run the
GitHub `Platform` workflow with `bootstrap_gitops=true` after apply so the
workflow can create `openai-secret`, install the shared secrets chart, and apply
the Petclinic Argo CD Applications without waiting for workload health.

## Provider Notes

The dev and prod roots configure:

- `aws` for AWS infrastructure.
- `kubernetes` for in-cluster platform resources.
- `helm` for platform add-on charts.
- `random` for generated passwords.
- `tls` for EKS OIDC thumbprint discovery.

The Kubernetes and Helm providers authenticate to the EKS cluster created by the
same root with AWS CLI exec auth (`aws eks get-token`). This avoids stale EKS
tokens during long apply and destroy runs.

## Apply Order

1. Apply `environments/bootstrap`.
2. Apply `environments/dev` or `environments/prod`.
3. Use Terraform outputs to update kubeconfig or let GitHub Actions do it.
4. Bootstrap or refresh Argo CD applications through the platform workflow or
   `deploy-argocd.yml`.

When GitHub Actions applies the platform, the bootstrap-created role must have
the current platform policy. Managed EKS node group creation requires
`iam:GetRole` as well as `iam:CreateServiceLinkedRole` because EKS validates the
`AWSServiceRoleForAmazonEKSNodegroup` service-linked role before creating the
node group. Re-apply `environments/bootstrap` after changing that policy.

For destroy runs, prefer the platform workflow. It previews destroy without a
saved plan, removes GitOps Applications, ingresses, stale ExternalSecret
finalizers, and TargetGroupBindings, destroys Terraform-managed platform
ingress/DNS resources first, optionally force-deletes leftover cluster ALBs and
VPC dependencies, waits for ACM certificates to detach from ALB listeners, then
runs a fresh Terraform destroy for the rest of the environment.

The `platform.yaml` workflow automates this flow for the selected environment.
