# Config Server Raw Manifests

This folder contains the raw Kubernetes Deployment, Service, and Eureka-related
ConfigMap for `config-server`.

The active deployment is the `config-server-dev` or `config-server-prod` Argo CD
Application, which renders `helm/petclinic-service` with
`helm-values/config-server.yaml`.

`config-server` is deployed first because the other Petclinic services read
Spring configuration from it.
