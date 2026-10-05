# Proposal

## Por qué

El estado de Terraform era local: perderlo complica la operación y las ejecuciones concurrentes pueden pisarse (VictorRoe/project-zomboid-infrastructure-aws#16).

## Qué cambia

- `terraform/backend.tf`: backend S3 con `use_lockfile`, `encrypt`; bucket/región por `backend.hcl` (ignorado por git).
- `bootstrap/state-backend`: bucket versionado, SSE-S3, privado, solo TLS, retención de versiones, `prevent_destroy`, estado propio.
- Terraform `>= 1.11`.

## Capacidades

### Capacidades nuevas
- `state-backend`

## Impacto

`terraform/backend.tf`, `versions.tf`; `bootstrap/state-backend/`; Makefile (`bootstrap-test`); `tests/render-user-data.sh`.
