## MODIFIED Requirements

### Requirement: Única fuente de configuración
El procedimiento de respaldo DEBE (SHALL) tomar la región, el nombre del servidor y la instancia de los outputs del stack, DEBE (SHALL) permitir que `AWS_REGION`, `PZ_SERVER_NAME` e `INSTANCE_ID` los sobrescriban, y NO DEBE (SHALL NOT) depender de un bucket S3.

#### Scenario: Valores tomados de los outputs
- **WHEN** el stack expone `aws_region = "sa-east-1"`, `pz_server_name = "w1"` y no hay sobrescrituras
- **THEN** el script detiene `pzsvrtool@w1.service`, llama a AWS en `sa-east-1` y no hace llamadas a S3

#### Scenario: Sobrescritura por variable de entorno
- **WHEN** se define `AWS_REGION=eu-west-1`
- **THEN** las llamadas a AWS usan `eu-west-1` sin importar el output

## REMOVED Requirements

### Requirement: Falla rápida ante configuración faltante
**Reason**: incluía el bucket S3 de metadatos, que se retira (#17).
**Migration**: reemplazado por "Falla rápida sin configuración", sin bucket y con la instancia.

## ADDED Requirements

### Requirement: Falla rápida sin configuración
El procedimiento de respaldo DEBE (SHALL) salir con código distinto de cero antes de detener el servidor si no se puede resolver la región, el nombre del servidor, la IP, el volumen o la instancia (incluido un output de Terraform faltante).

#### Scenario: Sin instancia
- **WHEN** el output `instance_id` no existe
- **THEN** el script sale con código distinto de cero y no realiza llamadas SSH ni a AWS


### Requirement: Snapshots automáticos con retención
El stack DEBE (SHALL) crear, salvo que se desactive, una política DLM diaria con hora y retención configurables que solo apunte al volumen de este servidor y que solo pueda borrar los snapshots que ella crea.

#### Scenario: Valores por defecto
- **WHEN** se planifica con valores por defecto
- **THEN** hay un snapshot diario a las 09:00 UTC con 7 copias sobre `pz-world-volume=<nombre>`

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
