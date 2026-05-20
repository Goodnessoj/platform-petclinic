# Admin Server Raw Manifests

This folder contains the raw Kubernetes Deployment and Service for
`admin-server`.

The active deployment is the `admin-server-dev` or `admin-server-prod` Argo CD
Application, which renders `helm/petclinic-service` with
`helm-values/admin-server.yaml`.

`admin-server` exposes the Spring Boot admin UI on port `9090` and waits for
both Config Server and Discovery Server before starting.
