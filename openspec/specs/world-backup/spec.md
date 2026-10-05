# world-backup Specification

## Purpose
Define cómo el procedimiento de respaldo previo a la destrucción obtiene su configuración y apunta al disco del servidor y al bucket de respaldo correctos.

## Requirements

### Requirement: Única fuente de configuración
El procedimiento de respaldo DEBE (SHALL) tomar el nombre del bucket, la región y el nombre del servidor de los outputs del stack, y DEBE (SHALL) permitir que las variables de entorno `S3_BUCKET`, `AWS_REGION` y `PZ_SERVER_NAME` sobrescriban cada valor.

#### Scenario: Valores tomados de los outputs
- **WHEN** el stack expone `backup_bucket_name = "b1"`, `aws_region = "sa-east-1"`, `pz_server_name = "w1"` y no hay sobrescrituras
- **THEN** el script detiene `pzsvrtool@w1.service`, llama a AWS en `sa-east-1` y escribe los metadatos en `s3://b1/`

#### Scenario: Sobrescritura por variable de entorno
- **WHEN** se define `S3_BUCKET=override`
- **THEN** los metadatos se escriben en `s3://override/` sin importar el output

### Requirement: Se ejecuta desde cualquier directorio
El procedimiento de respaldo DEBE (SHALL) ubicar la configuración de Terraform de forma relativa a su propia ubicación (o mediante `TF_DIR`), independientemente del directorio de trabajo de quien lo invoca.

#### Scenario: Ejecución desde la raíz del repositorio
- **WHEN** el script se invoca como `script/destroy-and-backup.sh` desde la raíz del repositorio
- **THEN** todos los comandos de Terraform apuntan a `terraform/`

### Requirement: Selección exacta del disco
El procedimiento de respaldo DEBE (SHALL) crear el snapshot del volumen indicado por el output `root_volume_id` del stack.

#### Scenario: Existe un volumen etiquetado obsoleto
- **WHEN** otro volumen también lleva la etiqueta `pz-world-data-root`
- **THEN** el snapshot se crea únicamente a partir del volumen `root_volume_id`

### Requirement: Falla rápida ante configuración faltante
El procedimiento de respaldo DEBE (SHALL) salir con código distinto de cero antes de detener el servidor si no se puede resolver el bucket, la región, el nombre del servidor, la IP de la instancia o el ID del volumen (incluido un output de Terraform faltante).

#### Scenario: Sin bucket configurado
- **WHEN** el bucket se resuelve a un valor vacío
- **THEN** el script sale con código distinto de cero y no realiza llamadas SSH ni a AWS
