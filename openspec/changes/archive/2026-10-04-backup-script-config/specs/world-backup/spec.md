# Spec Delta

## Purpose

Defines how the pre-destroy backup procedure obtains its configuration and targets the correct server disk and backup bucket.

## ADDED Requirements

### Requirement: Single source of configuration
The backup procedure SHALL take bucket name, region and server name from the stack's outputs, and SHALL let `S3_BUCKET`, `AWS_REGION` and `PZ_SERVER_NAME` environment variables override each value.

#### Scenario: Values from outputs
- **WHEN** the stack outputs `backup_bucket_name = "b1"`, `aws_region = "sa-east-1"`, `pz_server_name = "w1"` and no overrides are set
- **THEN** the script stops `pzsvrtool@w1.service`, calls AWS in `sa-east-1` and writes metadata to `s3://b1/`

#### Scenario: Environment override
- **WHEN** `S3_BUCKET=override` is set
- **THEN** metadata is written to `s3://override/` regardless of the output

### Requirement: Runs from any directory
The backup procedure SHALL locate the Terraform configuration relative to its own location (or `TF_DIR`), independent of the caller's working directory.

#### Scenario: Run from repo root
- **WHEN** the script is invoked as `script/destroy-and-backup.sh` from the repository root
- **THEN** all Terraform commands target `terraform/`

### Requirement: Exact disk targeting
The backup procedure SHALL snapshot the volume reported by the stack's `root_volume_id` output.

#### Scenario: Stale tagged volume exists
- **WHEN** another volume also carries the tag `pz-world-data-root`
- **THEN** the snapshot is created from the `root_volume_id` volume only

### Requirement: Fail fast on missing configuration
The backup procedure SHALL exit non-zero before stopping the server if the bucket, region, server name, instance IP or volume ID cannot be resolved (including a missing Terraform output).

#### Scenario: No bucket configured
- **WHEN** the bucket resolves to an empty value
- **THEN** the script exits non-zero and makes no SSH or AWS calls
