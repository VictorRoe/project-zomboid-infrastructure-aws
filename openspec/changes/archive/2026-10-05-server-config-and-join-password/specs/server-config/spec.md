## ADDED Requirements

### Requirement: Contrato de archivos de configuración
La configuración subida DEBE (SHALL) contener `<nombre>.ini` y `<nombre>_SandboxVars.lua` (y opcionalmente los spawns) con `<nombre>` igual a `pz_server_name`, y DEBE (SHALL) rechazarse antes de cambiar nada si tiene otros archivos, si `Mods=`, `WorkshopItems=` o `Map=` no aparecen exactamente una vez, si `Map=` está vacío, si los puertos no coinciden con los abiertos o si contiene valores redactados fuera de las claves gestionadas.

#### Scenario: Configuración inválida
- **WHEN** el `.ini` tiene `Map=` vacío, `DefaultPort=27000` y `DiscordToken=<redacted>`
- **THEN** la ejecución falla listando cada error y la configuración en uso no cambia

#### Scenario: Orden de mods
- **WHEN** se aplica una configuración válida
- **THEN** el `.ini` en uso es idéntico al subido salvo `Password=` y `RCONPassword=`

### Requirement: Aplicación idempotente con copia
La configuración DEBE (SHALL) aplicarse solo cuando cambia su resultado renderizado, deteniendo antes el juego en orden, guardando una copia de la configuración en uso y registrando revisión y origen; sin cambios, NO DEBE (SHALL NOT) modificar archivos ni reiniciar el juego.

#### Scenario: Re-ejecución sin cambios
- **WHEN** se reaprovisiona sin una subida nueva
- **THEN** no hay cambios ni copias nuevas y el juego no se reinicia

### Requirement: Cambios manuales preservados
Si la configuración en uso difiere de la última subida, una ejecución sin subida nueva DEBE (SHALL) advertir las claves distintas sin pisarlas, y la siguiente subida DEBE (SHALL) guardarlas en la copia antes de aplicar.

#### Scenario: Edición manual
- **WHEN** se cambia `MaxPlayers` en el host y se reaprovisiona
- **THEN** se advierte `MaxPlayers` y el valor manual se conserva

### Requirement: Sin mundo antes de la configuración
Con `pz_wait_for_config`, el juego NO DEBE (SHALL NOT) arrancar (tampoco tras reiniciar) hasta que haya una configuración aplicada o un mundo existente.

#### Scenario: Instalación limpia
- **WHEN** termina el aprovisionamiento sin configuración subida
- **THEN** el proceso del juego no corre y no existe el mundo
