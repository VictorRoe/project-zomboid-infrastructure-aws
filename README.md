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

Una EC2 Ubuntu 24.04, del tamaño que define el tier, con un único disco gp3 que contiene SO, juego y mundo, más una Elastic IP y un security group (UDP 16261–16262 y 8766; SSH solo desde las redes que se declaren). Al crearse, la instancia clona **este repo en un commit fijo** y se configura sola con Ansible: pzsvrtool como servicio systemd, heap de Java, contraseñas y la configuración que sube el operador. La propia instancia toma un snapshot diario del disco, solo los días que está prendida, y conserva los últimos 4. El estado de Terraform vive en S3, con bloqueo. Detalle en [docs/architecture.md](docs/architecture.md).

## Tiers y costos estimados

Se elige un tier en `terraform.tfvars` (`tier = "estandar"` por defecto). Cada uno fija la instancia, el heap de Java y el disco; cualquier variable explícita lo reemplaza. USD por mes en `us-east-1`, sin impuestos, con precios del 2026-10-05:

| Tier | Recomendado para | Instancia | vCPU | RAM | Heap del juego (`-Xmx`) | Disco | 60 h de juego/mes | 24/7 |
|---|---|---|---|---|---|---|---|---|
| `minimo` | Probar, 1–2 jugadores sin mods | `t3.medium` (burstable) | 2 | 4 GiB | 2 GB | 30 GB | ~9 | ~37 |
| `estandar` | Grupo chico, pocos mods | `m7i.large` | 2 | 8 GiB | 4 GB | 30 GB | **~12,70** | ~80 |
| `robusto` | Muchos mods (~250), 4–8 jugadores | `r7i.large` | 2 | 16 GiB | 8 GB | 50 GB | ~17 | ~105 |
| `grande` | Muchos mods, más jugadores y CPU | `m7i.xlarge` | 4 | 16 GiB | 10 GB | 60 GB | ~22 | ~157 |

La RAM es la memoria de la instancia. El heap es lo que puede usar Java para el juego: el resto queda para el SO, la memoria propia de Java y pzsvrtool (el plan verifica que RAM ≥ heap + margen).

La EC2 se cobra solo mientras está encendida (`pz-ctl.sh stop` entre sesiones). El disco, la Elastic IP (3,65) y los snapshots se cobran siempre: unos 6,65 USD/mes detenido en `estandar`. Después de `destroy-and-backup.sh` quedan solo los snapshots (~0,60). En `sa-east-1` la latencia desde Argentina es mucho menor (~34 ms contra ~166 ms), pero cuesta ~60 % más. Desglose, criterios para elegir tier, comparación de regiones y fuentes: [docs/costs.md](docs/costs.md).

## Documentación

- [Operación](docs/operations.md): **runbook del día a día**: levantar, sesiones, backups, configuración, contraseñas, actualizar, restaurar, dar de baja, destruir y probar sin AWS
- [Costos, tamaño y región](docs/costs.md)
- [Arquitectura](docs/architecture.md): componentes, recursos de AWS y estructura en el host
- [Flujos](docs/flows.md): aprovisionamiento, configuración, sesiones, backups, baja y restauración paso a paso
- [Spec](docs/spec.md): valores de configuración actuales
- [Decisiones](docs/decisions.md): por qué las cosas son como son
- [Changelog](CHANGELOG.md)
- [Specs](openspec/specs/): contratos de comportamiento (OpenSpec); historial en `openspec/changes/archive/`
