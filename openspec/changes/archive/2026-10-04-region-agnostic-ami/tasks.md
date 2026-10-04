# Tasks

## 1. Test harness

- [x] 1.1 Add `terraform { required_version = ">= 1.9" ... required_providers aws }` block and commit `.terraform.lock.hcl` (drop it from `.gitignore`); verify `terraform init -backend=false` succeeds (registry only, no AWS)
- [x] 1.2 Add `Makefile` with `tf-test`, `ansible-check`, `test` targets and verify `make ansible-check` passes on the current playbook

## 2. Image selection

- [x] 2.1 Add `ami_id` variable (default `""`) and `data "aws_ami" "ubuntu"` lookup; set `locals.base_ami_id` and use it on `aws_instance.pz_server` with `lifecycle { ignore_changes = [ami] }`; default `availability_zone` to null with region validation; verify `terraform validate` passes
- [x] 2.2 Add `terraform/tests/ami.tftest.hcl` with mocked provider covering default lookup, override and mismatched-AZ (`expect_failures`) scenarios; verify `make tf-test` passes with no AWS credentials (`env -u AWS_ACCESS_KEY_ID -u AWS_PROFILE`)

## 3. Docs and changelog

- [x] 3.1 Update `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` where affected, append a dated decision entry to `docs/decisions.md`, and add an `[Unreleased]` entry to `CHANGELOG.md` referencing the issue; verify links resolve and values match the code
