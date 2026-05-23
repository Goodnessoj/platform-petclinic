# Dev Environment

This is the active development platform root. It provisions the AWS and
Kubernetes foundation used by the dev Petclinic services.

## What It Manages

- VPC, public subnets, route table, internet gateway, and security groups.
- ECR repositories for all Petclinic services.
- CloudWatch log groups and a CloudWatch dashboard.
- EKS cluster, managed node group, EKS add-ons, and IRSA roles.
- RDS MySQL instance and database credential secret in AWS Secrets Manager.
- OpenAI and Grafana Secrets Manager entries through the `secrets` module.
- Optional Route 53 and ACM resources for app, Argo CD, Grafana, Prometheus,
  Zipkin, Eureka, and Discovery hostnames.
- External Secrets Operator, AWS Load Balancer Controller, optional ExternalDNS,
  Argo CD, kube-prometheus-stack, Grafana, Loki, and related platform services.

## Defaults

Key defaults from `variable.tf`:

- `environment = "dev"`
- `project_name = "petclinic"`
- `aws_region = "us-east-2"`
- `repository_prefix = "petclinic-dev"`
- `cluster_name = "petclinic-dev-eks"`
- `root_domain_name = "phoniex.site"`
- `app_subdomain = "petclinic"`
- `argocd_subdomain = "argocd"`
- `grafana_subdomain = "grafana"`
- `prometheus_subdomain = "prometheus"`
- EKS desired node count is `3` with `t3.medium` nodes.
- RDS uses `db.t3.micro`, 20 GB gp3 storage, and single-AZ by default.

## Required Local Files

Create `terraform/environments/dev/terraform.tfvars` for shared or local values.
This file is no longer ignored by Git, so commit only sanitized values.
Credentials should stay in GitHub secrets, your shell environment, or another
controlled secret source.

Common overrides:

```hcl
openai_api_key = "..."
eks_admin_role_arns = [
  "arn:aws:iam::<account-id>:role/<admin-role>"
]
```

Add the stable IAM role you use for local applies to `eks_admin_role_arns`.
Terraform will create an EKS access entry for that role so the Kubernetes and
Helm providers can manage in-cluster resources.
The GitHub Actions role is granted separately through `github_actions_role_arn`.

If GitHub Actions owns the OpenAI runtime secret, keep:

```hcl
create_openai_secret = false
```

## Usage

```bash
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev validate -no-color
terraform -chdir=terraform/environments/dev plan -var-file=terraform.tfvars
terraform -chdir=terraform/environments/dev apply -var-file=terraform.tfvars
```

Update kubeconfig after apply:

```bash
aws eks update-kubeconfig --region us-east-2 --name petclinic-dev-eks
kubectl get nodes
```

## Important Outputs

- `kubectl_update_kubeconfig_command`
- `eks_cluster_name`
- `ecr_registry_url`
- `ecr_repository_urls`
- `rds_endpoint`
- `rds_secret_name`
- `application_namespace`
- `argocd_domain_name`
- `grafana_domain_name`
- `prometheus_domain_name`
- `zipkin_domain_name`
- `app_domain_name`
- `zipkin_acm_certificate_arn`

## Post-Apply Checks

```bash
kubectl get ns
kubectl get pods -n argocd
kubectl get pods -n external-secrets
kubectl get pods -n monitoring
kubectl get clustersecretstore aws-secrets-manager
```

If `enable_dns_ingress` is true, dev endpoints are expected at:

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

## Destroy And Reapply

Keep `terraform/environments/bootstrap` in place. For routine dev teardown,
prefer the platform workflow because it removes Argo CD Applications, ingresses,
stale ExternalSecret finalizers, and TargetGroupBindings, destroys
Terraform-managed platform ingress/DNS resources first, optionally force-deletes
leftover cluster ALBs and VPC dependencies, waits for ACM certificates to
detach, then runs a fresh Terraform destroy.

If a local apply or destroy reports `Failed to persist state to backend`, do not
run apply again first. Restore the backend bucket if needed, then run:

```bash
terraform -chdir=terraform/environments/dev state push errored.tfstate
```
