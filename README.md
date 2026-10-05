# project-zomboid-infrastructure-aws

Terraform + Ansible para correr un servidor dedicado de Project Zomboid en una sola instancia EC2 de AWS. Incluye sesiones con stop/start e IP fija, backups automáticos y consistentes, configuración del juego versionada, contraseña de ingreso y actualizaciones automáticas del juego.

```bash
# Requisitos únicos: bucket del estado (bootstrap/state-backend) y terraform/terraform.tfvars (ver docs/operations.md)
cd terraform && terraform init -backend-config=backend.hcl && terraform apply
../script/pz-ctl.sh push-config ~/mi-config     # ini, SandboxVars y spawns del juego (en git)
../script/pz-ctl.sh join-password               # contraseña para los jugadores
../script/pz-ctl.sh stop | start | status       # sesiones de juego
```

## Arquitectura

Una EC2 Ubuntu 24.04 (`m7i.large`, 2 vCPU, 8 GiB, no burstable) con un único disco gp3 de 30 GB que contiene SO, juego y mundo, más una Elastic IP y un security group (UDP 16261–16262 y 8766; SSH solo desde las redes que se declaren). Al crearse, la instancia clona **este repo en un commit fijo** y se configura sola con Ansible: pzsvrtool como servicio systemd, heap de Java, contraseñas y la configuración que sube el operador. DLM toma un snapshot diario del disco. El estado de Terraform vive en S3, con bloqueo. Detalle en [docs/architecture.md](docs/architecture.md).

## Costos estimados

Con los valores por defecto (`us-east-1`, `m7i.large`, 30 GB gp3, Elastic IP, 7 snapshots diarios), en USD por mes, sin impuestos. Precios consultados el 2026-10-05.

| Uso | Costo aproximado |
|---|---|
| 60 h de juego al mes (`pz-ctl.sh stop` entre sesiones) | **~12,70** |
| Encendido 24/7 | **~80** |
| Detenido todo el mes (disco + Elastic IP + snapshots) | ~6,65 |
| Dado de baja con `destroy-and-backup.sh` (solo snapshots) | ~0,60 |

La EC2 se cobra solo mientras está encendida (0,10 USD/h). El disco (2,40), la Elastic IP (3,65) y los snapshots se cobran siempre. En `sa-east-1` la latencia desde Argentina es mucho menor (~34 ms contra ~166 ms), pero cuesta ~60 % más. Desglose, tamaños para servidores con muchos mods, la comparación de regiones y las fuentes: [docs/costs.md](docs/costs.md).

## Documentación

- [Operación](docs/operations.md): **runbook del día a día**: levantar, sesiones, backups, configuración, contraseñas, actualizar, restaurar, dar de baja, destruir y probar sin AWS
- [Costos, tamaño y región](docs/costs.md)
- [Arquitectura](docs/architecture.md): componentes, recursos de AWS y estructura en el host
- [Flujos](docs/flows.md): aprovisionamiento, configuración, sesiones, backups, baja y restauración paso a paso
- [Spec](docs/spec.md): valores de configuración actuales
- [Decisiones](docs/decisions.md): por qué las cosas son como son
- [Changelog](CHANGELOG.md)
- [Specs](openspec/specs/): contratos de comportamiento (OpenSpec); historial en `openspec/changes/archive/`
