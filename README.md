# project-zomboid-infrastructure-aws

Terraform + Ansible to run a Project Zomboid dedicated server on a single AWS EC2 instance, with automatic game updates and snapshot-based backups.

```bash
cd terraform && terraform init && terraform apply
terraform output -raw public_ip     # connect to <ip>:16261
```

## Documentation

- [Architecture](docs/architecture.md): components, AWS resources, on-host layout
- [Flows](docs/flows.md): provisioning, auto-update, backup and destroy, restore
- [Spec](docs/spec.md): current configuration values
- [Operations](docs/operations.md): day-to-day commands
- [Decisions](docs/decisions.md): why things are the way they are
- [Changelog](CHANGELOG.md)
- [Specs](openspec/specs/): behavior contracts (OpenSpec); change history in `openspec/changes/archive/`
