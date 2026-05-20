# Argo CD Applications

This folder defines the Petclinic Argo CD project and environment-specific
Applications.

## Files

- `project.yaml`: AppProject named `petclinic`.
- `dev/`: dev Applications with automated sync.
- `prod/`: prod Applications with manual sync.
- `kustomization.yaml`: includes the project plus both environment folders.

## AppProject Scope

The `petclinic` project allows:

- Source repository: `https://github.com/Goodnessoj/platform-petclinic.git`
- Destinations:
  - `petclinic-dev`
  - `petclinic-prod`
- Namespace creation as a cluster-scoped resource.
- All namespace-scoped resources.

## Sync Waves

Applications use sync waves to respect service dependencies:

| Wave | Services |
| ---: | --- |
| `0` | `config-server` |
| `1` | `discovery-server` |
| `2` | `customers-service`, `vets-service`, `visits-service`, `genai-service` |
| `3` | `api-gateway`, `admin-server` |

## Helm Source

Each service Application points to:

```text
helm/petclinic-service
```

and merges:

```text
helm-values/<environment>.yaml
helm-values/<service>.yaml
```

Prod Applications additionally set Helm parameters for prod image registry and
repository values.

## Apply

Dev:

```bash
kubectl apply -f k8s/argocd/applications/project.yaml
kubectl apply -k k8s/argocd/applications/dev
```

Prod:

```bash
kubectl apply -f k8s/argocd/applications/project.yaml
kubectl apply -k k8s/argocd/applications/prod
```

All:

```bash
kubectl apply -k k8s/argocd/applications
```