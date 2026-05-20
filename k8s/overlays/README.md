# Kustomize Overlays

This folder is retained as the legacy Kustomize overlay location.

The current `platform-petclinic` deployment path uses Argo CD Applications to
render Helm charts from `helm/` with values from `helm-values/`. There are no
active overlay manifests here right now.

Use `k8s/argocd/applications` for normal dev and prod service deployment.
