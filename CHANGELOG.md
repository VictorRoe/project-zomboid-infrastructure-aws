# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Deploys in any AWS region: the Ubuntu AMI is resolved per region, `availability_zone` defaults to an AWS-chosen zone and is validated against `aws_region` ([#4](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/4)).

### Changed
- AMI changes no longer replace an existing instance (`ignore_changes = [ami]`); use `terraform apply -replace=aws_instance.pz_server` to rebuild.
- Terraform `>= 1.9` required; provider lock file is committed.

### Added
- `make test`: offline Terraform tests (mocked AWS provider) and Ansible syntax check.
- `docs/` with architecture, flows, spec, operations and decision log.
- `CHANGELOG.md`, `CLAUDE.md`, and an expanded README.
