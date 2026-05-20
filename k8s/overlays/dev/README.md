# Dev Kustomize Overlay

This folder is currently empty and kept only as a placeholder for the previous
raw-manifest deployment model.

Dev workloads are now deployed by the Argo CD Applications in
`k8s/argocd/applications/dev`, using Helm values from `helm-values/dev.yaml`
and each service-specific values file.
