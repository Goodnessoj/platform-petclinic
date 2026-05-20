# Terraform Modules

This folder contains reusable Terraform modules consumed by the environment
roots.

## Module Guide

| Module | Purpose |
| --- | --- |
| [`vpc`](vpc/README.md) | Creates the VPC, public subnets, internet routing, and security groups. |
| [`ecr`](ecr/README.md) | Creates one ECR repository per Petclinic service. |
| [`observability`](observability/README.md) | Creates CloudWatch log groups and dashboard resources. |
| [`eks`](eks/README.md) | Creates the EKS cluster, managed node group, EKS OIDC provider, EKS add-ons, and IRSA roles. |
| [`rds`](rds/README.md) | Creates the MySQL RDS instance and stores DB credentials in Secrets Manager. |
| [`secrets`](secrets/README.md) | Creates OpenAI and Grafana Secrets Manager entries. |
| [`dns-ingress`](dns-ingress/README.md) | Creates ACM certificates and Route 53 DNS validation records. |
| [`addons`](addons/README.md) | Installs Kubernetes platform add-ons with Helm and Kubernetes resources. |
| [`github-oidc`](github-oidc/README.md) | Creates the GitHub Actions OIDC provider, IAM role, and policies. |

## Composition

The dev root wires modules in this order:

1. `vpc`
2. `ecr`
3. `observability`
4. `eks`
5. `rds`
6. `secrets`
7. `dns-ingress` when enabled
8. `addons`

The `addons` module depends on a working EKS cluster and the IAM roles created
by the `eks` module.

## Development Notes

- Keep module interfaces explicit with `variable.tf` and `output.tf`.
- Prefer passing ARNs, IDs, and names from parent roots rather than using data
  lookups inside modules unless the module truly owns that lookup.
- Review destructive settings before production use. For example, the ECR
  module currently sets `force_delete = true`.
