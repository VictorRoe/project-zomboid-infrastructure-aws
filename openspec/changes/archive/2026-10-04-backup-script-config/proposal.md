# Proposal

## Why

The backup script and Terraform disagree on basic configuration: `var.s3_bucket_name` (`zomboid-bucket-backup`) is unused while the script hardcodes `tu-bucket-zomboid-backups`; the region and server name (`zomboid`) are hardcoded too, and the script only works when run from inside `terraform/` (VictorRoe/project-zomboid-infrastructure-aws#2). It also picks the volume by tag with `Volumes[0]`, which can match a stale volume.

## What Changes

- Terraform becomes the single source of truth: new outputs `backup_bucket_name`, `aws_region`, `pz_server_name`; new variable `pz_server_name` (default `zomboid`) passed to the playbook via `user_data`.
- Script reads those outputs with `terraform -chdir=<repo>/terraform`, so it runs from any directory; env vars (`S3_BUCKET`, `AWS_REGION`, `PZ_SERVER_NAME`, `TF_DIR`) override.
- Script uses the `root_volume_id` output instead of a tag query.
- Snapshot metadata written via a temp file instead of leaving `snapshot_meta.txt` in the cwd.
- Script tests extended (stubbed tools only).

## Capabilities

### New Capabilities
- `world-backup`: how the pre-destroy backup resolves its configuration and records snapshot metadata.

### Modified Capabilities

## Impact

- `terraform/variable.tf`, `output.tf`, user_data template; `script/destroy-and-backup.sh`; `tests/script/`.
- The S3 bucket stays **unmanaged** by this stack (otherwise `terraform destroy` at the end of the script would delete it); it must exist beforehand.
- Stacked on `instance-ssh-access`.
