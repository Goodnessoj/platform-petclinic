# Raw Kubernetes Base

This folder stores raw Kubernetes reference manifests for the Petclinic
services and supporting runtime resources.

The active deployment path for this repo is Helm through Argo CD. These raw
manifests are kept for review, troubleshooting, and as a readable baseline for
the resources rendered by `helm/petclinic-service` and
`helm/petclinic-secrets`.

## Folders

| Folder | Purpose |
| --- | --- |
| `namespaces/` | Reference namespace manifest. |
| `config-server/` | Raw Config Server Deployment, Service, and Eureka config. |
| `discovery-server/` | Raw Eureka Discovery Server Deployment and Service. |
| `customers-service/` | Raw Customers service Deployment and Service. |
| `vets-service/` | Raw Vets service Deployment and Service. |
| `visits-service/` | Raw Visits service Deployment and Service. |
| `genai-service/` | Raw GenAI service Deployment and Service. |
| `api-gateway/` | Raw public edge service Deployment and Service. |
| `admin-server/` | Raw admin UI/service Deployment and Service. |
| `external-secrets/` | Raw ExternalSecret and ClusterSecretStore references. |
| `ingress/` | Raw ALB ingress reference. |

Use Argo CD Applications under `k8s/argocd/applications` for normal deploys.
