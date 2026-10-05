## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Aviso sin acceso SSH
El plan DEBE (SHALL) advertir cuando falte el par de claves o las redes administrativas, y los procedimientos que necesitan SSH DEBEN (SHALL) fallar antes de actuar, indicando la configuración que falta.

#### Scenario: Backup sin SSH configurado
- **WHEN** el output `ssh_enabled` es `false`
- **THEN** el script sale con error sin llamadas SSH ni snapshot y menciona `ssh_allowed_cidrs`
