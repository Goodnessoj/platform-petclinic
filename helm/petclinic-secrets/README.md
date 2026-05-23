# Petclinic Secrets Chart

`petclinic-secrets` renders shared `ExternalSecret` resources for application
runtime secrets.

## Resources Rendered

- Database `ExternalSecret`, enabled by `database.enabled`.
- OpenAI `ExternalSecret`, enabled by `openai.enabled`.

## Template Files

- `templates/database-externalsecret.yaml`: maps database properties from AWS
  Secrets Manager into the Kubernetes `mysql-secret`.
- `templates/openai-externalsecret.yaml`: maps the OpenAI API key into the
  Kubernetes `openai-secret` when enabled.
- `templates/_helpers.tpl`: shared labels and chart naming helpers.

Do not add Markdown files under `templates/`; Helm attempts to render every file
in that directory.

The chart expects the External Secrets Operator CRDs and the
`ClusterSecretStore` named `aws-secrets-manager` to already exist. Terraform
creates those through the add-ons module.

## Default Targets

| ExternalSecret | Kubernetes Secret | Remote secret |
| --- | --- | --- |
| `petclinic-db-secret` | `mysql-secret` | `petclinic/dev/terraform/database` |
| `petclinic-openai-secret` | `openai-secret` | `petclinic/dev/terraform/openai-api-key` |

Environment-specific values in `helm-values/secrets-dev.yaml` and
`helm-values/secrets-prod.yaml` override the remote secret names.

## Database Mapping

The database secret maps these properties from AWS Secrets Manager:

- `MYSQL_PASSWORD`
- `MYSQL_USER`
- `MYSQL_HOST`
- `MYSQL_DATABASE`

## OpenAI Mapping

The OpenAI secret maps:

- `OPENAI_API_KEY` from Secrets Manager to
  `SPRING_AI_OPENAI_API_KEY` in Kubernetes.

Current GitHub Actions workflows create the Kubernetes `openai-secret` directly
from the `OPENAI_API_KEY` GitHub secret and install this chart with
`--set openai.enabled=false`. That avoids storing the OpenAI key in Terraform
state-managed secret versions.

Local installs should usually follow the same pattern unless you deliberately
store the OpenAI key in AWS Secrets Manager. A local Terraform apply cannot read
GitHub Secrets, so it can create the database secret path but not the
GitHub-owned OpenAI runtime secret.

## Install Example

```bash
helm upgrade --install petclinic-secrets helm/petclinic-secrets \
  --namespace petclinic-dev \
  --create-namespace \
  --wait \
  -f helm-values/secrets-dev.yaml \
  --set openai.enabled=false
```

## Verify

```bash
kubectl get externalsecret -n petclinic-dev
kubectl get secret mysql-secret -n petclinic-dev
kubectl get secret openai-secret -n petclinic-dev
```
