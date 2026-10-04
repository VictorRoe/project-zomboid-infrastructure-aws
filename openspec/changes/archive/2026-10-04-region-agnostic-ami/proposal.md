# Proposal

## Why

`aws_instance.pz_server` pins `ami-0b6d9d3d33ba97d99`, an Ubuntu image that only exists in us-east-1, so `var.aws_region` looks configurable but any other region fails at apply time (GitHub issue VictorRoe/project-zomboid-infrastructure-aws#4). The repo also has no automated checks, and changes must be verifiable without touching AWS.

## What Changes

- Resolve the Ubuntu Server LTS x86_64 AMI for the configured region at plan time via a data source (Canonical owner).
- Add an optional `ami_id` override variable; when set it wins over the lookup.
- Default `availability_zone` to `null` (AWS picks one in the region) and validate any explicit AZ belongs to `aws_region`.
- Ignore AMI drift on the existing instance so a newer image never replaces a running server (and its world disk) implicitly.
- Introduce an offline test harness: `terraform test` with `mock_provider "aws"` (no credentials, no API calls), Ansible syntax check, and a `make test` entry point that later changes extend.
- Document the test command in `CLAUDE.md`/README.

## Capabilities

### New Capabilities
- `compute-image-selection`: how the server's machine image is chosen per region, including the override.

### Modified Capabilities

## Impact

- `terraform/main.tf`, `terraform/variable.tf`; new `terraform/tests/`, `Makefile`.
- Requires Terraform >= 1.7 locally (for `mock_provider`); the AWS provider is downloaded by `terraform init` but never called.
- Existing instances are not replaced (AMI changes ignored); new instances get the current image. `.terraform.lock.hcl` becomes tracked.
