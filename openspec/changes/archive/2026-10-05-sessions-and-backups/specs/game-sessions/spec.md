## ADDED Requirements

### Requirement: Dirección pública estable
El stack DEBE (SHALL) asociar una Elastic IP a la instancia y exponerla como `public_ip`, junto con `instance_id`.

#### Scenario: Outputs
- **WHEN** se aplica el stack
- **THEN** `public_ip` es la Elastic IP asociada a la instancia

### Requirement: Detención segura de una sesión
`pz-ctl.sh stop` DEBE (SHALL) confirmar el apagado ordenado del juego antes de detener la EC2; si no puede confirmarlo, NO DEBE (SHALL NOT) detener la EC2 salvo con `FORCE_STOP=1`.

#### Scenario: Juego que no termina
- **WHEN** el proceso del juego sigue corriendo al vencer `STOP_TIMEOUT`
- **THEN** el comando sale con error y no se llama a `stop-instances`

#### Scenario: Ya detenida
- **WHEN** la instancia ya está `stopped`
- **THEN** el comando termina con éxito sin otras llamadas

### Requirement: Estados esperados con timeout
`start` y `stop` DEBEN (SHALL) esperar el estado pedido hasta `INSTANCE_TIMEOUT`, propagar los errores de AWS y fallar ante estados terminales.

#### Scenario: Timeout
- **WHEN** la instancia no llega a `running` dentro del tiempo
- **THEN** el comando sale con error indicando el estado actual
