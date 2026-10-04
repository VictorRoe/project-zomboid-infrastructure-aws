# Design

## Context

The backup is a snapshot of the *root* volume. `aws_instance.root_block_device` cannot take a `snapshot_id`, so the root disk can only come from an image. cloud-init re-runs `user_data` on a new instance ID, so the boot script runs again on a restored disk; today it does `git clone` into an existing directory under `set -e` and would abort.

## Goals / Non-Goals

**Goals:** full-disk restore with zero manual steps; safe default when no snapshot exists; deterministic tests via mocks.

**Non-Goals:** splitting world data onto a separate data volume (cleaner long-term, but a larger migration); snapshot retention/cleanup; cross-region snapshot copy.

## Decisions

- **Register an image from the snapshot (`aws_ami` with root `ebs_block_device` = snapshot, `/dev/sda1`, hvm, ENA on, gp3, delete_on_termination) and boot from it.** Alternatives: (a) separate data volume restored via `aws_ebs_volume.snapshot_id` + mount — requires changing where pzsvrtool stores data and a migration of existing snapshots; (b) post-boot restore with the AWS CLI — needs IAM role and more moving parts. Image registration fits the existing full-root snapshot as-is.
- **Image precedence:** `local.instance_ami_id = local.restore_snapshot_id != "" ? aws_ami.restored[0].id : local.base_ami_id`. `local.restore_snapshot_id` = `var.restore_snapshot_id` if set, else the latest tagged snapshot ID, else `""`; forced `""` when `restore_from_snapshot = false`. Restore beats `ami_id` deliberately — silently skipping a restore because an override was set would lose data; `restore_from_snapshot = false` is the explicit opt-out.
- **Snapshot lookup keeps the existing `count` guard** on `data.aws_ebs_snapshot` (it errors on zero matches).
- **Restore applies only when the instance is created.** With `ignore_changes = [ami]` (from `region-agnostic-ami`), a new snapshot never replaces a running server; restore happens on the first apply after a destroy, or on an explicit `-replace`. (Review finding: without this, an apply on a live server would roll it back to an older snapshot.)
- **Chosen snapshot is looked up directly:** `data.aws_ebs_snapshot.restore[0]` (count-guarded, `snapshot_ids = [local.restore_snapshot_id]`) for both the latest and the explicit case, so its size and state are always known. Size = `max(30, volume_size)`, used by the AMI's `ebs_block_device` and the instance's `root_block_device`.
- **`aws_ami.restored` arguments:** `name = "pz-restore-${snapshot_id}"` (required, unique per region), `root_device_name = "/dev/sda1"`, `virtualization_type = "hvm"`, `ena_support = true` (required on t3), `boot_mode = "uefi-preferred"` (matches Canonical 24.04; works under BIOS or UEFI), gp3. Precondition: snapshot `state == "completed"`. Destroy deregisters the image but leaves the snapshot (`aws_ami` does not manage the snapshots it's registered from).
- **Boot script:** `if [ -d /home/ubuntu/repo/.git ]; then runuser -u ubuntu -- git -C … fetch && runuser -u ubuntu -- git -C … reset --hard origin/main; else git clone …; fi`. Git runs as `ubuntu`: as root it refuses a repo owned by `ubuntu` ("dubious ownership", git ≥ 2.35.2) and `set -e` would abort. The playbook is already idempotent (skips install if `start-server.sh` exists, swap/user/linger guarded).
- **Tests:** `command = apply` against `mock_provider "aws"`. Mocked `aws_ebs_snapshot_ids.ids` defaults to `[]`, so every with-snapshot run overrides `data.aws_ebs_snapshot_ids.zomboid_snapshots`, `data.aws_ebs_snapshot.latest_zomboid_snapshot[0]` and `data.aws_ebs_snapshot.restore[0]` (state `completed`) by full address, plus `override_resource` for `aws_ami.restored` (fixed `id`).

## Risks / Trade-offs

- [Restored image boot mode mismatch] → Ubuntu images boot under legacy BIOS on Nitro; register with default boot mode, matching how the source image booted; documented for manual check on first real restore.
- [Crash-consistent snapshot if the service wasn't stopped] → addressed by the `instance-ssh-access` change (verified graceful stop).
- [Old snapshots accumulate costs] → out of scope; noted in README.

## Migration Plan

Applying to a live server after merge changes nothing (AMI ignored). The next apply after `destroy-and-backup.sh` restores from the latest snapshot. To force a fresh world, set `restore_from_snapshot = false`. Playbook/user_data changes reach real hosts only after this repo is merged upstream (instances clone GitHub `main`). Rollback: revert; snapshots are untouched.
