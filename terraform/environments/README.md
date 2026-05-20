# Terraform Environments

This folder contains Terraform root modules. Each root has its own state key and
can be initialized, planned, applied, and destroyed independently.

## Roots

| Root | State key | Purpose | Destroy policy |
| --- | --- | --- | --- |
| [`bootstrap`](bootstrap/README.md) | `petclinic/bootstrap/terraform.tfstate` | Durable state bucket and GitHub Actions OIDC role. | Avoid destroying. |
| [`dev`](dev/README.md) | `petclinic/dev/terraform.tfstate` | Active dev EKS platform and services foundation. | Disposable with care. |
| [`prod`](prod/README.md) | `petclinic/prod/terraform.tfstate` | Production EKS platform and services foundation. | Destroy only with explicit approval. |

## Recommended Order

Bootstrap comes first:

```bash
terraform -chdir=terraform/environments/bootstrap init
terraform -chdir=terraform/environments/bootstrap apply -var-file=terraform.tfvars
```

Then apply the target environment:

```bash
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev apply -var-file=terraform.tfvars
```

## Shared Environment Pattern

The deployable environment roots compose these modules:

- `vpc`
- `ecr`
- `observability`
- `eks`
- `rds`
- `secrets`
- `dns-ingress` when DNS ingress is enabled
- `addons`

The GitHub Actions platform workflow grants its Terraform role cluster-admin
access with EKS access entries before refreshing Kubernetes and Helm resources.

## Variables

Use `terraform.tfvars` for local overrides. Important values include:

- `aws_region`
- `repository_prefix`
- `github_actions_role_name` or `github_actions_role_arn`
- EKS node sizing values
- RDS size and high availability values
- `openai_api_key` and `create_openai_secret`
- `enable_dns_ingress`
- `root_domain_name`, `app_subdomain`, `argocd_subdomain`,
  `grafana_subdomain`, `prometheus_subdomain`
- Optional Argo CD repository credentials

`terraform.tfvars` files are no longer ignored by Git. Commit only sanitized
environment values, and keep credentials in GitHub secrets or another controlled
secret source.

## State Recovery

If an apply or destroy fails while saving state, Terraform writes
`errored.tfstate` into the affected environment directory. Do not run apply
again first; that can fork state. Restore the S3 backend bucket if needed, then
push the preserved state:

```bash
terraform -chdir=terraform/environments/dev state push errored.tfstate
```

After the push, run `terraform plan` and only apply if the plan is expected.
