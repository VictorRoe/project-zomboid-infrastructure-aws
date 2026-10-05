# Proposal

## Por qué

`ssh_allowed_cidrs` permitía `0.0.0.0/0` por defecto: el puerto 22 quedaba expuesto a Internet (VictorRoe/project-zomboid-infrastructure-aws#19).

## Qué cambia

- Lista vacía por defecto (sin regla del puerto 22); validación de CIDRs IPv4 con dirección de red; `/0` solo con `ssh_allow_any_source`.
- `check` de plan y output `ssh_enabled`; los scripts fallan temprano sin SSH.
- **BREAKING (incompatible):** sin redes declaradas no hay SSH.

## Capacidades

### Capacidades modificadas
- `instance-access`

## Impacto

`terraform/variable.tf`, `main.tf`, `output.tf`; `script/lib/common.sh`; tests de Terraform y de scripts.
