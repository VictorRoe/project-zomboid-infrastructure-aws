# Proposal

## Por qué

El script de backup y Terraform discrepan en la configuración básica: `var.s3_bucket_name` (`zomboid-bucket-backup`) no se usa mientras el script tiene fijo `tu-bucket-zomboid-backups`; la región y el nombre del servidor (`zomboid`) también están fijos, y el script solo funciona cuando se ejecuta desde dentro de `terraform/` (VictorRoe/project-zomboid-infrastructure-aws#2). Además elige el volumen por etiqueta con `Volumes[0]`, lo que puede coincidir con un volumen obsoleto.

## Qué cambia

- Terraform pasa a ser la única fuente de verdad: nuevos outputs `backup_bucket_name`, `aws_region`, `pz_server_name`; nueva variable `pz_server_name` (por defecto `zomboid`) pasada al playbook mediante `user_data`.
- El script lee esos outputs con `terraform -chdir=<repo>/terraform`, por lo que se ejecuta desde cualquier directorio; las variables de entorno (`S3_BUCKET`, `AWS_REGION`, `PZ_SERVER_NAME`, `TF_DIR`) los sobrescriben.
- El script usa el output `root_volume_id` en lugar de una consulta por etiqueta.
- Los metadatos del snapshot se escriben mediante un archivo temporal en lugar de dejar `snapshot_meta.txt` en el cwd.
- Pruebas del script ampliadas (solo con herramientas simuladas).

## Capacidades

### Capacidades nuevas
- `world-backup`: cómo el backup previo al destroy resuelve su configuración y registra los metadatos del snapshot.

### Capacidades modificadas

## Impacto

- `terraform/variable.tf`, `output.tf`, plantilla de user_data; `script/destroy-and-backup.sh`; `tests/script/`.
- El bucket S3 permanece **sin administrar** por este stack (de lo contrario el `terraform destroy` al final del script lo eliminaría); debe existir de antemano.
- Apilado sobre `instance-ssh-access`.
