# Proposal

## Why

The instance is launched without a key pair, yet `script/destroy-and-backup.sh` SSHes as `ubuntu` to stop the server before snapshotting. The SSH step fails and is masked by `|| true`, so the snapshot is taken from a running server with possibly inconsistent world saves (VictorRoe/project-zomboid-infrastructure-aws#5). Even with access, the stop command runs `systemctl --user` via `sudo -iu` without `XDG_RUNTIME_DIR`, which fails to reach the user bus.

## What Changes

- Optional SSH access: `ssh_public_key` (creates a Terraform-managed key pair) or `ssh_key_name` (existing pair); mutually exclusive.
- `ssh_allowed_cidrs` input for the port-22 rule (default keeps today's `0.0.0.0/0`).
- Backup script: stop the service with the correct user-bus environment, then verify the game process has exited; abort **before** snapshotting if stop cannot be confirmed, unless explicitly forced (`FORCE_SNAPSHOT=1`). Supports `SSH_KEY` for the identity file; skips host-key pinning for the freshly provisioned host (keys regenerate on every instance).
- **BREAKING (behavioral):** the backup script no longer proceeds silently when the server cannot be stopped.
- Offline script tests with stubbed `ssh`/`aws`/`terraform`.

## Capabilities

### New Capabilities
- `instance-access`: operator SSH access to the server and the guarantee that backups only snapshot a stopped server.

### Modified Capabilities

## Impact

- `terraform/main.tf`, `variable.tf`, `output.tf`; `script/destroy-and-backup.sh`; new `tests/script/` harness and `make script-test` target.
- Stacked on `restore-world-from-snapshot`.
