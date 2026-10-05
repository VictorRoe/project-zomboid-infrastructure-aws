# world-data-restore Specification

## Purpose
Garantiza que un servidor de Project Zomboid reaprovisionado vuelva con el mundo y la configuración capturados por el último respaldo, en lugar de iniciar vacío.

## Requirements

### Requirement: Restauración desde el último snapshot de respaldo
Cuando se crea una instancia de servidor, la restauración está habilitada y existe al menos un snapshot propio etiquetado `pz-world-data-snapshot`, el servidor DEBE (SHALL) arrancar desde un disco creado a partir del snapshot más reciente de ese tipo, con un tamaño al menos igual al del snapshot.

#### Scenario: Existe un snapshot
- **WHEN** se aplica el stack y un snapshot etiquetado `snap-123` es el más reciente
- **THEN** la instancia arranca desde una imagen respaldada por `snap-123`
- **AND** el output `restored_from_snapshot_id` es igual a `snap-123`

### Requirement: Instalación nueva sin snapshot
Cuando no existe ningún snapshot etiquetado o la restauración está deshabilitada, el servidor DEBE (SHALL) arrancar desde la imagen base de Ubuntu y realizar una instalación nueva.

#### Scenario: Sin snapshot
- **WHEN** se aplica el stack y no existe ningún snapshot etiquetado
- **THEN** la instancia usa la imagen base y `restored_from_snapshot_id` está vacío

#### Scenario: Restauración deshabilitada
- **WHEN** existe un snapshot etiquetado y `restore_from_snapshot = false`
- **THEN** la instancia usa la imagen base y no se registra ninguna imagen restaurada

### Requirement: Restaurar un snapshot específico
El stack DEBE (SHALL) aceptar `restore_snapshot_id`; cuando no esté vacío y la restauración esté habilitada, se DEBE (SHALL) usar ese snapshot en lugar del último etiquetado.

#### Scenario: Snapshot explícito
- **WHEN** `restore_snapshot_id = "snap-old"` mientras `snap-new` es el último snapshot etiquetado
- **THEN** la instancia arranca desde una imagen respaldada por `snap-old`

### Requirement: Primer arranque idempotente sobre un disco restaurado
El aprovisionamiento DEBE (SHALL) completarse con éxito sobre un disco restaurado que ya contiene el checkout del repositorio y un servidor instalado, sin reinstalar el juego ni eliminar los datos del mundo.

#### Scenario: El repositorio ya está presente
- **WHEN** se ejecuta el script de arranque y `/home/ubuntu/repo` ya existe
- **THEN** actualiza el checkout en lugar de fallar al clonar y vuelve a ejecutar el playbook

### Requirement: Un servidor en ejecución nunca se revierte
La aparición de un snapshot más nuevo o distinto NO DEBE (SHALL NOT) reemplazar una instancia de servidor existente.

#### Scenario: Aparece un snapshot mientras el servidor está en ejecución
- **WHEN** la instancia existe y se crea un nuevo snapshot etiquetado
- **THEN** un plan posterior no muestra ningún reemplazo de la instancia

### Requirement: Solo se restauran snapshots completados
La restauración DEBE (SHALL) rechazar un snapshot que no esté en estado completado, fallando en el plan/apply con un error claro.

#### Scenario: Snapshot pendiente
- **WHEN** el estado del snapshot elegido es `pending`
- **THEN** la ejecución falla con un error que nombra el snapshot
