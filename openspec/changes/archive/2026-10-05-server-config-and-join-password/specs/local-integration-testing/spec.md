## ADDED Requirements

### Requirement: Configuración verificada contra un servidor real
Las pruebas locales DEBEN (SHALL) subir una configuración con `pz-ctl.sh push-config` por SSH real y verificar que el juego arranca con ella, que la contraseña de ingreso está en el `.ini` y que una re-ejecución sin cambios no reinicia el juego.

#### Scenario: config-test
- **WHEN** se ejecuta `make local-config-test`
- **THEN** el juego corre con el `Map=` y el SandboxVars subidos y el PID no cambia tras reaprovisionar
