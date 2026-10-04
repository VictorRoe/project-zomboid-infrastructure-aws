# Tasks

## 1. Terraform outputs and server name

- [x] 1.1 Add `pz_server_name` variable (validated by regex) and outputs `backup_bucket_name`, `aws_region`, `pz_server_name`; pass `-e pz_server_name=` in the user_data template; verify `make tf-test` with an assertion on outputs and rendered user_data

## 2. Script configuration

- [x] 2.1 Resolve `TF_DIR`, read outputs with env overrides, fail fast on empty values; verify script tests for outputs, override and missing-bucket scenarios
- [x] 2.2 Use `root_volume_id` output, mktemp metadata file, parameterized service name; verify script test asserts `create-snapshot --volume-id <output>` and `pzsvrtool@<name>.service`
- [x] 2.3 Verify the script runs from repo root and from `/tmp` in tests (cwd independence)

## 3. Docs and changelog

- [x] 3.1 Update `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` where affected, append a dated decision entry to `docs/decisions.md`, and add an `[Unreleased]` entry to `CHANGELOG.md` referencing the issue; verify links resolve and values match the code
