# Proposal

## Por qué

`script/destroy-and-backup.sh` crea un snapshot del disco raíz del servidor (etiqueta `pz-world-data-snapshot`) antes de `terraform destroy`, y `main.tf` incluso busca el último snapshot — pero nada lo consume, así que el siguiente `terraform apply` arranca un disco de Ubuntu en blanco y el mundo se pierde en la práctica (VictorRoe/project-zomboid-infrastructure-aws#1).

## Qué cambia

- Cuando existe un snapshot de respaldo, registrar una imagen de máquina a partir de él y arrancar el servidor desde esa imagen, recuperando el disco completo (partidas del mundo, configuración de pzsvrtool, juego instalado).
- Agregar `restore_from_snapshot` (por defecto `true`) para excluirse, y `restore_snapshot_id` para restaurar un snapshot específico en lugar del último etiquetado.
- Hacer idempotente el script de arranque de EC2 para que tenga éxito sobre un disco restaurado donde el repositorio y el servidor ya existen.
- Exponer como output qué snapshot (si lo hay) se usó para restaurar la instancia.
- Cobertura con `terraform test` simulado para los caminos con y sin snapshot.

## Capacidades

### Capacidades nuevas
- `world-data-restore`: restauración del estado del servidor desde el snapshot de respaldo más reciente (o uno elegido) al aprovisionar.

### Capacidades modificadas

## Impacto

- `terraform/main.tf` (nuevo recurso `aws_ami`, precedencia de imagen, user_data), `variable.tf`, `output.tf`, nuevo `terraform/tests/restore.tftest.hcl`.
- Depende de `region-agnostic-ami` (usa su `local.base_ami_id` y su arnés de pruebas).
- La imagen registrada es administrada por Terraform y se desregistra al destruir; los snapshots en sí no son administrados y persisten.
