# Bootstrap Environment

This Terraform root owns durable infrastructure required before any disposable
platform environment can be managed safely.

## What It Creates

- S3 bucket for Terraform remote state.
- Versioning, AES256 server-side encryption, public access blocking, and bucket
  ownership controls for the state bucket.
- A state-bucket guardrail policy that denies non-break-glass principals from
  deleting the bucket, deleting state objects or versions, deleting the bucket
  policy, or adding lifecycle cleanup rules.
- GitHub Actions OIDC provider for `token.actions.githubusercontent.com`.
- `petclinic-github-actions-role`.
- IAM policies that let GitHub Actions:
  - Push and pull prefixed ECR images.
  - Read and write allowed Terraform state keys.
  - Manage the dev and prod platform Terraform stacks when enabled.
  - Manage Secrets Manager entries used by the platform.
  - Read and create AWS service-linked roles needed by managed EKS node groups.

## Safety Policy

Do not destroy this root during normal environment rebuilds. It uses
`prevent_destroy` on the state bucket and key GitHub OIDC resources because
losing them can break Terraform state access and CI/CD authentication.

The state bucket also has an explicit bucket policy guardrail. By default, only
the AWS account root principal is exempt as a break-glass path. Add tightly
controlled emergency principals with
`state_bucket_guardrail_exempt_principal_arns` only when needed.

Destroy only disposable environment roots such as `terraform/environments/dev`
when rebuilding the platform.

If the backend bucket is missing, recreate it before running more platform
applies or destroys. When Terraform has written an `errored.tfstate` recovery
file in an environment root, push that file back to the restored backend before
running another apply.

## Inputs

Important variables:

- `terraform_state_bucket_name`: remote state bucket name.
- `github_repositories`: repositories and branches/environments allowed to
  assume the GitHub Actions role.
- `github_actions_role_name`: name of the OIDC role.
- `repository_prefix`: ECR repository prefix GitHub Actions may push to.
- `platform_state_key_prefix`, `prod_state_key_prefix`,
  `bootstrap_state_key_prefix`: state prefixes permitted by the IAM policy.
- `terraform_state_kms_key_arn`: optional KMS key for encrypted state access.
- `state_bucket_guardrail_exempt_principal_arns`: optional break-glass
  principals allowed to bypass state bucket deletion denies.

## Outputs

Useful outputs:

- `terraform_state_bucket_name`
- `github_oidc_provider_arn`
- `github_actions_role_arn`
- `github_actions_role_name`
- `github_actions_allowed_subjects`

## Usage

```bash
terraform -chdir=terraform/environments/bootstrap init
terraform -chdir=terraform/environments/bootstrap fmt -check -recursive
terraform -chdir=terraform/environments/bootstrap validate -no-color
terraform -chdir=terraform/environments/bootstrap plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/bootstrap apply -var-file=terraform.tfvars
```

After bootstrap is applied, copy `github_actions_role_arn` into the GitHub
environment or repository secret/variable used by the workflows.

Re-apply this root whenever the GitHub Actions role policy changes. Platform
workflow failures that mention missing IAM permissions are usually fixed here,
not in the disposable dev or prod roots. For example, EKS managed node group
creation needs `iam:GetRole` to check
`AWSServiceRoleForAmazonEKSNodegroup` and `iam:CreateServiceLinkedRole` when the
service-linked role does not exist yet.

## Typical Rebuild Flow

```bash
terraform -chdir=terraform/environments/dev destroy -var-file=terraform.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=terraform.tfvars
```

Leave the bootstrap root in place while doing that rebuild.
