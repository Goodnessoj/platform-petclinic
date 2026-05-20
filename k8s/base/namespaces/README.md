# Namespace Raw Manifest

This folder contains the original raw namespace manifest for Petclinic.

The active platform creates environment-specific namespaces through Terraform,
Argo CD sync options, and deployment workflows:

- `petclinic-dev`
- `petclinic-prod`

Keep this manifest as a reference only unless you are doing manual Kubernetes
experiments outside the normal platform workflow.
