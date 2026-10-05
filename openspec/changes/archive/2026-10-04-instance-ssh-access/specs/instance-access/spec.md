# Spec Delta

## Purpose

Brinda a los operadores acceso SSH autenticado al servidor y garantiza que los snapshots de backup solo se toman después de que el servidor de juego se haya detenido de forma verificable.

## ADDED Requirements

### Requirement: Par de claves SSH configurable
El stack DEBE (SHALL) asociar un par de claves a la instancia cuando se proporcione `ssh_public_key` (se crea un par) o `ssh_key_name` (par existente), y DEBE (SHALL) rechazar las configuraciones que definan ambos.

#### Scenario: Clave pública proporcionada
- **WHEN** se define `ssh_public_key`
- **THEN** se crea un par de claves y el nombre de clave de la instancia lo referencia

#### Scenario: Nombre de clave existente
- **WHEN** se define `ssh_key_name = "ops"`
- **THEN** el nombre de clave de la instancia es `ops` y no se crea ningún par de claves

#### Scenario: Ambos proporcionados
- **WHEN** se definen tanto `ssh_public_key` como `ssh_key_name`
- **THEN** la planificación falla con un error de validación

### Requirement: Ingreso SSH restringible
El ingreso SSH DEBE (SHALL) limitarse a `ssh_allowed_cidrs`, con valor por defecto `0.0.0.0/0`.

#### Scenario: CIDR restringido
- **WHEN** `ssh_allowed_cidrs = ["203.0.113.4/32"]`
- **THEN** la regla del puerto 22 permite únicamente ese CIDR

### Requirement: Snapshot solo tras detención verificada
El procedimiento de backup DEBE (SHALL) detener el servicio del juego y confirmar que el proceso del juego terminó antes de crear un snapshot; si la confirmación falla, DEBE (SHALL) salir con código distinto de cero sin crear snapshot ni destruir, salvo que se fuerce.

#### Scenario: Detención confirmada
- **WHEN** el servicio se detiene y no queda ningún proceso del juego
- **THEN** se crea el snapshot y continúa el destroy

#### Scenario: SSH inalcanzable
- **WHEN** falla la conexión SSH
- **THEN** el script sale con código distinto de cero, no se crea ningún snapshot y no se ejecuta `terraform destroy`

#### Scenario: Forzado
- **WHEN** no se puede confirmar la detención y `FORCE_SNAPSHOT=1`
- **THEN** se imprime una advertencia y el snapshot continúa
