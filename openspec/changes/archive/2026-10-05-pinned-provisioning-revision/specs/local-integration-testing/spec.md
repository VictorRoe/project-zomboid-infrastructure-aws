## MODIFIED Requirements

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
