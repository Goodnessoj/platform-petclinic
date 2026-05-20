# Discovery Server Raw Manifests

This folder contains the raw Kubernetes Deployment and Service for
`discovery-server`.

The active deployment is the `discovery-server-dev` or
`discovery-server-prod` Argo CD Application, which renders
`helm/petclinic-service` with `helm-values/discovery-server.yaml`.

`discovery-server` provides Eureka service discovery and waits for
`config-server` before starting.
