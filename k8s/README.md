# Kubernetes Manifests

This folder contains the Kubernetes side of `platform-petclinic`.

The active deployment path is:

1. Terraform installs platform add-ons, including Argo CD, External Secrets
   Operator, AWS Load Balancer Controller, and monitoring.
2. Argo CD Applications under `k8s/argocd/applications` render Helm charts from
   `helm/` with values from `helm-values/`.
3. The raw manifests under `k8s/base` remain as reference manifests for the
   service shape and for emergency/manual review.

## Structure

| Path | Purpose |
| --- | --- |
| [`argocd/`](argocd/README.md) | Active GitOps project, Applications, and fallback install layer. |
| [`base/`](base/README.md) | Raw Deployment, Service, namespace, ingress, and ExternalSecret references. |
| [`overlays/`](overlays/README.md) | Legacy Kustomize overlay location kept for reference. |

## Common Checks

```bash
kubectl get applications -n argocd -o wide
kubectl get pods,svc,ingress -n petclinic-dev
kubectl get externalsecret -n petclinic-dev
```
