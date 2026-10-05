# world-backup Specification

## Purpose
Define cómo el procedimiento de respaldo previo a la destrucción obtiene su configuración y apunta al disco del servidor y al bucket de respaldo correctos.

## Requirements

### Requirement: Única fuente de configuración
El procedimiento de respaldo DEBE (SHALL) tomar la región, el nombre del servidor y la instancia de los outputs del stack, DEBE (SHALL) permitir que `AWS_REGION`, `PZ_SERVER_NAME` e `INSTANCE_ID` los sobrescriban, y NO DEBE (SHALL NOT) depender de un bucket S3.

#### Scenario: Valores tomados de los outputs
- **WHEN** el stack expone `aws_region = "sa-east-1"`, `pz_server_name = "w1"` y no hay sobrescrituras
- **THEN** el script detiene `pzsvrtool@w1.service`, llama a AWS en `sa-east-1` y no hace llamadas a S3

#### Scenario: Sobrescritura por variable de entorno
- **WHEN** se define `AWS_REGION=eu-west-1`
- **THEN** las llamadas a AWS usan `eu-west-1` sin importar el output

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

### Requirement: Puerto SSH configurable
El procedimiento de backup DEBE (SHALL) usar el puerto SSH indicado en `SSH_PORT`, o el 22 si no está definido.

#### Scenario: Puerto personalizado
- **WHEN** se ejecuta con `SSH_PORT=2222`
- **THEN** todas las conexiones SSH usan el puerto 2222

### Requirement: Falla rápida sin configuración
El procedimiento de respaldo DEBE (SHALL) salir con código distinto de cero antes de detener el servidor si no se puede resolver la región, el nombre del servidor, la IP, el volumen o la instancia (incluido un output de Terraform faltante).

#### Scenario: Sin instancia
- **WHEN** el output `instance_id` no existe
- **THEN** el script sale con código distinto de cero y no realiza llamadas SSH ni a AWS

### Requirement: Snapshots automáticos con retención
Salvo que se desactive, la propia instancia DEBE (SHALL) hacer un snapshot automático de su disco del mundo una vez por día y solo mientras está prendida (a la hora configurada o, si estaba apagada, al prender), y DEBE (SHALL) conservar los `backup_retain_count` más nuevos borrando solo snapshots automáticos completados de su servidor.

#### Scenario: Valores por defecto
- **WHEN** se planifica con valores por defecto
- **THEN** la instancia recibe un timer diario a las 09:00 UTC que conserva 4 snapshots automáticos, y un rol que solo puede crear snapshots del volumen con `pz-world-volume=<nombre>` y borrar los `pz-backup=auto` de su servidor

#### Scenario: Rotación
- **WHEN** hay 6 automáticos y se crea uno nuevo con retención 4
- **THEN** se borran los 3 más viejos y ningún snapshot manual ni de otro servidor

#### Scenario: Snapshot reciente
- **WHEN** el último automático tiene menos de 12 horas
- **THEN** no se crea otro

#### Scenario: Fuera de EC2
- **WHEN** no hay metadatos de instancia (VM local)
- **THEN** el script termina sin hacer nada

### Requirement: Consistencia declarada
Los snapshots tomados con el juego detenido y confirmado DEBEN (SHALL) etiquetarse `pz-consistency=application` y `Name=pz-world-data-snapshot`; los automáticos DEBEN (SHALL) etiquetarse `crash` con otro `Name`, y los forzados `unconfirmed`, de modo que la restauración automática solo elija los consistentes.

#### Scenario: Snapshot forzado
- **WHEN** no se confirma la detención y `FORCE_SNAPSHOT=1`
- **THEN** el snapshot se etiqueta `pz-consistency=unconfirmed`

### Requirement: Backup consistente sin destruir
`pz-ctl.sh backup` DEBE (SHALL) detener el juego, tomar el snapshot y volver a iniciarlo, también si el snapshot falla; con la EC2 detenida, DEBE (SHALL) tomarlo sin SSH.

#### Scenario: Falla el snapshot
- **WHEN** `create-snapshot` falla
- **THEN** el comando sale con error y el juego se vuelve a iniciar

### Requirement: Nunca destruir sin snapshot completado
El procedimiento de baja NO DEBE (SHALL NOT) ejecutar `terraform destroy` si el snapshot no se creó o no se completó.

#### Scenario: Snapshot incompleto
- **WHEN** la espera del snapshot falla
- **THEN** el script sale con error sin destruir
