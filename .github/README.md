# GitHub Automation

This folder contains GitHub Actions workflows that operate the platform and the
GitOps deployment loop.

## Workflows

| Workflow | File | Purpose |
| --- | --- | --- |
| Platform | [`workflows/platform.yaml`](workflows/platform.yaml) | Plans, applies, or destroys the selected Terraform platform. On apply it can also bootstrap runtime secrets and Argo CD applications. On destroy it pre-cleans GitOps ingresses/finalizers before Terraform removes AWS resources. |
| Deploy ArgoCD | [`workflows/deploy-argocd.yml`](workflows/deploy-argocd.yml) | Installs or upgrades Argo CD with Helm, configures RBAC, applies Argo CD applications, and waits for selected apps. |
| Update Image Tags | [`workflows/update-image-tags.yml`](workflows/update-image-tags.yml) | Receives app image build dispatches, updates service image tags in `helm-values`, commits the change, and triggers Argo CD deployment. |
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
  `genai-service` when platform apply bootstraps GitOps.
- `ARGOCD_REPO_TOKEN`: optional token for Argo CD private repository access.
- `GITOPS_PAT`: optional token used by the image tag updater when the default
  `GITHUB_TOKEN` is not enough for pushing to `main` or dispatching workflows.

## Flow

The normal automated flow starts in the application repository:

1. Application CI builds and pushes service images to ECR.
2. It sends a `repository_dispatch` event of type `app-image-built`.
3. `update-image-tags.yml` updates `helm-values/<service>.yaml` image tags.
4. The commit to `main` is observed by Argo CD or followed by a dispatch to
   `deploy-argocd.yml`.
5. Argo CD refreshes the affected Applications and syncs dev automatically.

The platform workflow is separate. Use it for infrastructure changes, initial
cluster bootstrapping, and controlled environment teardown. Destroy runs delete
Argo CD Applications, application/platform ingresses, stale ExternalSecret and
TargetGroupBinding finalizers, then wait for the ACM certificate to detach
before Terraform deletes the certificate and cluster.
