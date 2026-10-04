# Proposal

## Why

`script/destroy-and-backup.sh` snapshots the server's root disk (tag `pz-world-data-snapshot`) before `terraform destroy`, and `main.tf` even looks the latest snapshot up — but nothing consumes it, so the next `terraform apply` boots a blank Ubuntu disk and the world is effectively lost (VictorRoe/project-zomboid-infrastructure-aws#1).

## What Changes

- When a backup snapshot exists, register a machine image from it and boot the server from that image, bringing back the whole disk (world saves, pzsvrtool config, installed game).
- Add `restore_from_snapshot` (default `true`) to opt out, and `restore_snapshot_id` to restore a specific snapshot instead of the latest tagged one.
- Make the EC2 boot script idempotent so it succeeds on a restored disk where the repo and server already exist.
- Expose which snapshot (if any) the instance was restored from as an output.
- Mocked `terraform test` coverage for the with/without snapshot paths.

## Capabilities

### New Capabilities
- `world-data-restore`: restoring server state from the most recent (or a chosen) backup snapshot on provisioning.

### Modified Capabilities

## Impact

- `terraform/main.tf` (new `aws_ami` resource, image precedence, user_data), `variable.tf`, `output.tf`, new `terraform/tests/restore.tftest.hcl`.
- Depends on `region-agnostic-ami` (uses its `local.base_ami_id` and test harness).
- The registered image is Terraform-managed and deregistered on destroy; snapshots themselves stay unmanaged and persist.
