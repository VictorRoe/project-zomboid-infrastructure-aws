# Tasks

## 1. Restore wiring

- [x] 1.1 Add `restore_from_snapshot` (bool, default true) and `restore_snapshot_id` (string, default "") variables; verify `terraform validate`
- [x] 1.2 Compute `local.restore_snapshot_id`, add `data.aws_ebs_snapshot.restore` and `aws_ami.restored` (count-guarded; name, ENA, uefi-preferred, size, completed-state precondition) from that snapshot and `local.instance_ami_id` precedence; use it on `aws_instance.pz_server`; verify `terraform validate`
- [x] 1.3 Add `restored_from_snapshot_id` output; verify via test assertion in 2.1

## 2. Tests and boot idempotency

- [x] 2.1 Add `terraform/tests/restore.tftest.hcl` covering snapshot present, absent, disabled, explicit-ID and pending-state (`expect_failures`) scenarios with mocked provider; verify `make tf-test` passes without AWS credentials
- [x] 2.2 Make `user_data` update an existing checkout (git via `runuser -u ubuntu`) instead of cloning; extract it to `terraform/templates/user_data.sh.tftpl` and verify with `bash -n` on the rendered output plus a tftest assertion that it contains the update branch
- [x] 2.3 Document restore behavior and opt-out variables in README and CLAUDE.md; verify docs match variable names in `variable.tf`

## 3. Docs and changelog

- [x] 3.1 Update `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` where affected, append a dated decision entry to `docs/decisions.md`, and add an `[Unreleased]` entry to `CHANGELOG.md` referencing the issue; verify links resolve and values match the code
