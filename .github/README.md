# GitHub Automation

This folder contains GitHub Actions workflows that operate the platform and the
GitOps deployment loop.

## Workflows

| Workflow | File | Purpose |
| --- | --- | --- |
| Platform | [`workflows/platform.yaml`](workflows/platform.yaml) | Plans, applies, or destroys the selected Terraform platform. On apply it can also bootstrap runtime secrets, but it does not apply Petclinic Argo CD Applications. On destroy it pre-cleans GitOps ingresses/finalizers before Terraform removes AWS resources. |
| Deploy ArgoCD Applications | [`workflows/deploy-argocd.yml`](workflows/deploy-argocd.yml) | Verifies the Terraform-managed Argo CD install, applies Argo CD applications, and waits for selected apps. Its only trigger is the image tag update dispatch; it does not run from pushes to `main`. |
| Update Image Tags | [`workflows/update-image-tags.yaml`](workflows/update-image-tags.yaml) | Receives app image build dispatches, updates service image tags in `helm-values`, commits the change, and triggers Argo CD deployment. |
| Deploy Changed Petclinic Services | [`workflows/deploy-services.yaml`](workflows/deploy-services.yaml) | Imperatively deploys selected services with Helm in dependency order. This is useful when bypassing or recovering GitOps. |

## Required Configuration

Common repository or environment variables:

- `AWS_REGION`: defaults to `us-east-2` when unset.
- `AWS_ROLE_ARN` or `AWS_ROLE_TO_ASSUME`: IAM role assumed through GitHub OIDC.
- `EKS_CLUSTER_NAME`: defaults to `petclinic-<environment>-eks` in service deployment.
- `K8S_NAMESPACE`: defaults to `petclinic-<environment>`.
- `DOMAIN_NAME` or `APP_DOMAIN_NAME`: optional public application hostname.
- `ACM_CERTIFICATE_ARN`: required when deploying `api-gateway` with an ALB
  ingress through the service deployment workflow.

Common secrets:

- `OPENAI_API_KEY`: creates the Kubernetes `openai-secret` consumed by
  `genai-service` when platform apply or the Argo CD deployment workflow
  bootstraps runtime secrets.
- `ARGOCD_REPO_TOKEN`: optional token for Argo CD private repository access.
- `GITOPS_PAT`: optional token used by the image tag updater when the default
  `GITHUB_TOKEN` is not enough for pushing to `main` or dispatching workflows.

The `AWS_ROLE_ARN` role must come from the bootstrap Terraform root. Its
platform policy must include EKS, EC2, IAM, Route 53, ACM, RDS, Secrets Manager,
and service-linked-role read/create permissions. In particular, EKS managed node
group creation fails if the role cannot call `iam:GetRole` while checking
`AWSServiceRoleForAmazonEKSNodegroup`.

## Flow

The normal automated flow starts in the application repository:

1. Application CI builds and pushes service images to ECR.
2. It sends a `repository_dispatch` event of type `app-image-built`.
3. `update-image-tags.yaml` updates `helm-values/<service>.yaml` image tags.
4. The tag update workflow dispatches `deploy-argocd.yml`; that
   `repository_dispatch` event is the only deploy workflow trigger.
5. Argo CD refreshes the affected Applications and syncs dev automatically.

The platform workflow is separate. Use it for infrastructure changes, initial
cluster bootstrapping, and controlled environment teardown. Destroy runs delete
Argo CD Applications, application/platform ingresses, stale ExternalSecret and
TargetGroupBinding finalizers, then wait for the ACM certificate to detach
before Terraform deletes the certificate and cluster.

For a complete rebuild, run `platform.yaml` with `action=destroy`, then rerun it
with `action=apply` and `bootstrap_runtime_secrets=true`. Local Terraform can
recreate the platform, but only GitHub Actions can consume the `OPENAI_API_KEY`
GitHub secret and create the runtime `openai-secret`. Applying Petclinic Argo
CD Applications and waiting for their health stays in `deploy-argocd.yml`.
