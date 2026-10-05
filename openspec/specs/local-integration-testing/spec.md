# local-integration-testing Specification

## Purpose
Permite verificar en una VM local, sin AWS, el aprovisionamiento real del servidor y sus ciclos de reinicio, restauración y backup, usando la misma imagen y el mismo script de arranque que la EC2.

## Requirements

### Requirement: Paridad de arranque con la EC2
El entorno local DEBE (SHALL) arrancar la imagen cloud oficial de Ubuntu 24.04 amd64 verificada por checksum y pasarle por cloud-init el `user_data` que renderiza Terraform sin modificaciones, con `repo_commit` igual al commit actual del repositorio, servido desde un servidor git en el host.

#### Scenario: Aprovisionamiento completo
- **WHEN** se ejecuta `make local-up` en un host con KVM
- **THEN** cloud-init termina sin errores, el servicio `pzsvrtool@<nombre>.service` está habilitado y, sin configuración subida, el juego espera; tras `config-test` existe un proceso `ProjectZomboid` del usuario `pzserver`

#### Scenario: Checksum inválido
- **WHEN** la imagen descargada no coincide con el `SHA256SUMS` publicado
- **THEN** el entorno se niega a arrancar y no crea la VM

#### Scenario: Revisión fija en la VM
- **WHEN** se ejecuta `make local-up` con el árbol commiteado
- **THEN** la VM registra `commit=<HEAD>` y `mode=pinned` y su checkout está en ese commit

#### Scenario: Cambios sin commitear
- **WHEN** hay cambios sin commitear en archivos rastreados
- **THEN** `local-up` falla antes de crear la VM

### Requirement: Arranque automático verificado
Las pruebas locales DEBEN (SHALL) verificar que el servidor vuelve a estar corriendo después de reiniciar la VM, sin intervención.

#### Scenario: Reinicio
- **WHEN** se ejecuta `make local-reboot-test`
- **THEN** tras el reinicio el proceso `ProjectZomboid` vuelve a existir dentro del tiempo límite

### Requirement: Restauración verificada
Las pruebas locales DEBEN (SHALL) simular la restauración arrancando una VM nueva desde una copia del disco con un `instance-id` distinto, y verificar que el servidor y sus datos vuelven.

#### Scenario: Disco restaurado
- **WHEN** se ejecuta `make local-restore-test`
- **THEN** cloud-init vuelve a ejecutar `user_data`, actualiza el checkout existente en lugar de clonar, el servidor vuelve a correr y la contraseña de admin no cambia

### Requirement: Detención verificada contra un servidor real
Las pruebas locales DEBEN (SHALL) ejecutar el script de backup contra la VM con SSH real y AWS/Terraform simulados, y verificar que el juego quedó detenido antes del snapshot simulado.

#### Scenario: Backup contra la VM
- **WHEN** se ejecuta `make local-backup-test`
- **THEN** el script termina con éxito, la llamada simulada `create-snapshot` ocurre y en la VM no queda proceso `ProjectZomboid`

### Requirement: Sin AWS
El entorno local NO DEBE (SHALL NOT) requerir credenciales de AWS ni realizar llamadas a sus APIs.

#### Scenario: Sin credenciales
- **WHEN** las pruebas locales corren sin variables ni archivos de credenciales de AWS
- **THEN** todas las pruebas se ejecutan igual

### Requirement: Configuración verificada contra un servidor real
Las pruebas locales DEBEN (SHALL) subir una configuración con `pz-ctl.sh push-config` por SSH real y verificar que el juego arranca con ella, que la contraseña de ingreso está en el `.ini` y que una re-ejecución sin cambios no reinicia el juego.

#### Scenario: config-test
- **WHEN** se ejecuta `make local-config-test`
- **THEN** el juego corre con el `Map=` y el SandboxVars subidos y el PID no cambia tras reaprovisionar
