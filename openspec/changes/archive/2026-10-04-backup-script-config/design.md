# Design

## Context

After `instance-ssh-access`, the script already has a stub-based test harness and a verified-stop step. Remaining hardcoded values: bucket, region, service name; cwd-dependent `terraform` calls; tag-based volume lookup.

## Goals / Non-Goals

**Goals:** one place to configure; script location-independent; deterministic tests.

**Non-Goals:** creating/managing the S3 bucket (would be destroyed by the script's own `terraform destroy`; a separate bootstrap stack is a possible follow-up); changing the snapshot tag scheme (restore depends on it).

## Decisions

- **Outputs over parsing tfvars:** `terraform output -raw` is the stable interface; it reflects effective values including defaults.
- **Precedence:** env var > Terraform output. Lets operators recover when state is partially gone.
- **`TF_DIR` default:** `$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)`; all calls use `terraform -chdir="$TF_DIR"`.
- **Server name flows Terraform → user_data → playbook** via `ansible-playbook -e pz_server_name=...`, so the script, playbook and service name can't drift. Name validated in Terraform with the playbook's regex `^[A-Za-z0-9._-]+$`.
- **Metadata file** via `mktemp` + `trap` cleanup.

## Risks / Trade-offs

- [Existing setups relying on `tu-bucket-zomboid-backups`] → set `s3_bucket_name` in tfvars or `S3_BUCKET`; documented in migration.
- [State missing → outputs fail] → env overrides + fail-fast message naming the missing value.

## Migration Plan

Set `s3_bucket_name` to the bucket actually in use before the next backup run. Rollback: revert.
