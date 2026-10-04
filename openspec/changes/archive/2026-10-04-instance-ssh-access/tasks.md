# Tasks

## 1. Terraform SSH access

- [x] 1.1 Add `ssh_public_key`, `ssh_key_name`, `ssh_allowed_cidrs` variables, `aws_key_pair.pz` (count-guarded), `key_name` on the instance with a cross-variable validation rejecting both inputs; verify `terraform validate`
- [x] 1.2 Add `terraform/tests/ssh.tftest.hcl` covering public key, existing name, both (expect_failures), and restricted CIDR; verify `make tf-test` passes

## 2. Safe stop in backup script

- [x] 2.1 Create `tests/script/` stub harness (`bin/ssh`, `bin/aws`, `bin/terraform`, `run.sh`) and `make script-test`; verify a smoke test of the current script runs entirely against stubs
- [x] 2.2 Rewrite the stop step with correct user-bus env, process-exit polling, `SSH_KEY`, single-quoted remote command, host-key options, `FORCE_SNAPSHOT`; verify script tests for confirmed stop, SSH failure (no snapshot, no destroy) and forced path pass
- [x] 2.3 Document SSH variables and backup failure semantics in README/CLAUDE.md; verify `bash -n script/destroy-and-backup.sh`

## 3. Docs and changelog

- [x] 3.1 Update `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` where affected, append a dated decision entry to `docs/decisions.md`, and add an `[Unreleased]` entry to `CHANGELOG.md` referencing the issue; verify links resolve and values match the code
