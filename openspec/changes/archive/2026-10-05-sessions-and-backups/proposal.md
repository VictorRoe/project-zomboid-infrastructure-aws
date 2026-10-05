# Proposal

## Por qué

Destruir y restaurar en cada sesión agregaba riesgo y cambiaba la IP (VictorRoe/project-zomboid-infrastructure-aws#9). Los backups solo existían al destruir, sin retención ni protección del volumen (VictorRoe/project-zomboid-infrastructure-aws#10). El script escribía metadatos en un bucket S3 que nadie leía (VictorRoe/project-zomboid-infrastructure-aws#17).

## Qué cambia

- Elastic IP; `pz-ctl.sh start|stop|status` con apagado ordenado confirmado antes de detener la EC2.
- Política DLM diaria (7 copias, permisos mínimos, crash-consistent) y `pz-ctl.sh backup` consistente.
- Snapshots manuales con tags de consistencia; sin bucket de metadatos (`s3_bucket_name` y `backup_bucket_name` eliminados).
- **BREAKING (incompatible):** `public_ip` pasa a ser la Elastic IP (cambia una vez).

## Capacidades

### Capacidades nuevas
- `game-sessions`

### Capacidades modificadas
- `world-backup`

## Impacto

`terraform/main.tf`, `variable.tf`, `output.tf`; `script/` (`lib/common.sh`, `pz-ctl.sh`, `destroy-and-backup.sh`); stubs y tests.
