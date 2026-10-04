# Design

## Context

Single-root Terraform config, local state, no tests, Terraform not pinned. Ubuntu AMIs are published by Canonical (owner `099720109477`) with names `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`.

## Goals / Non-Goals

**Goals:** region-correct AMI by default; deterministic override; an offline test harness reused by the following changes (restore, SSH access, backup script, admin password).

**Non-Goals:** multi-arch (Graviton) support; remote state; CI wiring (can be added later, harness is CI-ready).

## Decisions

- **`data "aws_ami" "ubuntu"` with `most_recent = true`, Canonical owner, name filter for 24.04 noble amd64 gp3.** Alternative: SSM parameter `/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id` — equally valid, but `aws_ami` is easier to mock with `override_data` and needs no SSM permission. Playbook asserts Debian x86_64, which 24.04 satisfies.
- **`locals { base_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id }`.** Local named `base_ami_id` so the restore change can layer "restored image > base image" on top without renaming.
- **`lifecycle { ignore_changes = [ami] }` on the instance.** The root disk is the world (`delete_on_termination=true`), so an image change must never replace a running server implicitly (a newer Canonical image or, after the restore change, a newer snapshot). Deliberate rebuilds use `terraform apply -replace=aws_instance.pz_server` after a backup. (Review finding: the earlier "plan shows replacement" mitigation was insufficient.)
- **`availability_zone` defaults to `null`** (AWS picks an AZ in the region); if set, a validation requires it to start with `var.aws_region` (cross-variable validation, Terraform >= 1.9).
- **Test harness:** `terraform/tests/*.tftest.hcl` using `mock_provider "aws"` + `override_data` for `aws_ami` and the snapshot data sources, `command = plan` assertions. `Makefile` targets: `tf-test` (`terraform init -backend=false` + `fmt -check` + `validate` + `test`), `ansible-check` (`--syntax-check`), `test` (all). `required_version = ">= 1.9"` (installed: 1.16.5) and `.terraform.lock.hcl` committed (removed from `.gitignore`) for reproducible provider versions; `terraform init` still needs registry access but never AWS APIs.

## Risks / Trade-offs

- [Running instances keep an old base image forever] → acceptable; the auto-updater handles the game, `unattended-upgrades` the OS; rebuild deliberately with `-replace`.
- [Mocked tests don't prove the real filter matches an image] → filter mirrors Canonical's documented naming; manual `aws ec2 describe-images` check noted in tasks as optional, not required.

## Migration Plan

Existing us-east-1 deployments wanting zero changes set `ami_id = "ami-0b6d9d3d33ba97d99"` in their tfvars. Rollback: revert the commit.
