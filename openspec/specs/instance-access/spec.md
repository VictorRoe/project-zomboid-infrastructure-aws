# instance-access Specification

## Purpose
Brinda a los operadores acceso SSH autenticado al servidor y garantiza que los snapshots de respaldo solo se tomen después de que el servidor de juego se haya detenido de forma verificada.

## Requirements

### Requirement: Par de claves SSH configurable
El stack DEBE (SHALL) asociar un par de claves a la instancia cuando se provea `ssh_public_key` (se crea un par) o `ssh_key_name` (par existente), y DEBE (SHALL) rechazar las configuraciones que definan ambos.

#### Scenario: Clave pública suministrada
- **WHEN** se define `ssh_public_key`
- **THEN** se crea un par de claves y el nombre de clave de la instancia lo referencia

#### Scenario: Nombre de clave existente
- **WHEN** se define `ssh_key_name = "ops"`
- **THEN** el nombre de clave de la instancia es `ops` y no se crea ningún par de claves

#### Scenario: Se suministran ambos
- **WHEN** se definen tanto `ssh_public_key` como `ssh_key_name`
- **THEN** la planificación falla con un error de validación

### Requirement: Ingreso SSH restringible
El ingreso SSH DEBE (SHALL) limitarse a `ssh_allowed_cidrs`, con valor por defecto una lista vacía que no crea ninguna regla para el puerto 22; el stack DEBE (SHALL) rechazar CIDRs que no sean IPv4 válidos con la dirección de red, y redes universales (`/0`) salvo con `ssh_allow_any_source = true`.

#### Scenario: Por defecto
- **WHEN** no se define `ssh_allowed_cidrs`
- **THEN** el security group no tiene regla para el puerto 22 y los puertos del juego siguen abiertos

#### Scenario: CIDR restringido
- **WHEN** `ssh_allowed_cidrs = ["203.0.113.4/32"]`
- **THEN** la regla del puerto 22 permite solo ese CIDR

#### Scenario: Internet entera
- **WHEN** `ssh_allowed_cidrs = ["0.0.0.0/0"]` sin `ssh_allow_any_source`
- **THEN** la planificación falla con un error de validación

#### Scenario: CIDR inválido
- **WHEN** `ssh_allowed_cidrs = ["203.0.113.4/24"]`
- **THEN** la planificación falla con un error de validación

### Requirement: Snapshot solo después de una detención verificada
El procedimiento de respaldo DEBE (SHALL) detener el servicio de juego y confirmar que el proceso del juego terminó antes de crear un snapshot; si la confirmación falla, DEBE (SHALL) salir con código distinto de cero sin crear el snapshot ni destruir, salvo que se fuerce.

#### Scenario: Detención confirmada
- **WHEN** el servicio se detiene y no queda ningún proceso del juego
- **THEN** se crea el snapshot y la destrucción continúa

#### Scenario: SSH inaccesible
- **WHEN** la conexión SSH falla
- **THEN** el script sale con código distinto de cero, no se crea ningún snapshot y no se ejecuta `terraform destroy`

#### Scenario: Forzado
- **WHEN** no se puede confirmar la detención y `FORCE_SNAPSHOT=1`
- **THEN** se imprime una advertencia y el snapshot continúa

### Requirement: Aviso sin acceso SSH
El plan DEBE (SHALL) advertir cuando falte el par de claves o las redes administrativas, y los procedimientos que necesitan SSH DEBEN (SHALL) fallar antes de actuar, indicando la configuración que falta.

#### Scenario: Backup sin SSH configurado
- **WHEN** el output `ssh_enabled` es `false`
- **THEN** el script sale con error sin llamadas SSH ni snapshot y menciona `ssh_allowed_cidrs`
