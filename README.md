# project-zomboid-infrastructure-aws

Terraform + Ansible para correr un servidor dedicado de Project Zomboid en una sola instancia EC2 de AWS, con actualizaciones automáticas del juego y backups basados en snapshots.

```bash
cd terraform && terraform init && terraform apply
terraform output -raw public_ip     # conectarse a <ip>:16261
```

## Documentación

- [Arquitectura](docs/architecture.md): componentes, recursos de AWS, estructura en el host y problemas conocidos
- [Flujos](docs/flows.md): aprovisionamiento, actualización automática, backup y baja, restauración
- [Spec](docs/spec.md): valores de configuración actuales
- [Operación](docs/operations.md): comandos del día a día
- [Decisiones](docs/decisions.md): por qué las cosas son como son
- [Changelog](CHANGELOG.md)
- [Specs](openspec/specs/): contratos de comportamiento (OpenSpec); historial de cambios en `openspec/changes/archive/`
