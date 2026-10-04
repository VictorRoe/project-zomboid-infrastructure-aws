# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- World data is restored on `terraform apply` after `destroy-and-backup.sh`: the instance boots from an image registered from the latest `pz-world-data-snapshot`; `restore_snapshot_id` selects a specific snapshot and `restore_from_snapshot = false` opts out ([#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)).
- The EC2 boot script no longer fails on a restored disk where the repo already exists.
- Deploys in any AWS region: the Ubuntu AMI is resolved per region, `availability_zone` defaults to an AWS-chosen zone and is validated against `aws_region` ([#4](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/4)).

### Changed
- AMI changes no longer replace an existing instance (`ignore_changes = [ami]`); use `terraform apply -replace=aws_instance.pz_server` to rebuild.
- Terraform `>= 1.9` required; provider lock file is committed.

### Added
- `restored_from_snapshot_id` output and `make user-data-check`.
- `make test`: offline Terraform tests (mocked AWS provider) and Ansible syntax check.
- `docs/` with architecture, flows, spec, operations and decision log.
- `CHANGELOG.md`, `CLAUDE.md`, and an expanded README.
