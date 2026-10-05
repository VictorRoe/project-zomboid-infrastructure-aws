# Proposal

## Por qué

La instancia se lanza sin par de claves, pero `script/destroy-and-backup.sh` se conecta por SSH como `ubuntu` para detener el servidor antes de crear el snapshot. El paso SSH falla y queda enmascarado por `|| true`, de modo que el snapshot se toma desde un servidor en ejecución con guardados del mundo posiblemente inconsistentes (VictorRoe/project-zomboid-infrastructure-aws#5). Incluso con acceso, el comando de detención ejecuta `systemctl --user` mediante `sudo -iu` sin `XDG_RUNTIME_DIR`, lo que no logra alcanzar el bus de usuario.

## Qué cambia

- Acceso SSH opcional: `ssh_public_key` (crea un par de claves administrado por Terraform) o `ssh_key_name` (par existente); son mutuamente excluyentes.
- Entrada `ssh_allowed_cidrs` para la regla del puerto 22 (el valor por defecto mantiene el `0.0.0.0/0` actual).
- Script de backup: detiene el servicio con el entorno correcto del bus de usuario y luego verifica que el proceso del juego haya terminado; aborta **antes** de crear el snapshot si no se puede confirmar la detención, salvo que se fuerce explícitamente (`FORCE_SNAPSHOT=1`). Admite `SSH_KEY` para el archivo de identidad; omite el anclaje de la clave de host para el host recién aprovisionado (las claves se regeneran en cada instancia).
- **BREAKING (incompatible) (de comportamiento):** el script de backup ya no continúa silenciosamente cuando no se puede detener el servidor.
- Pruebas offline del script con `ssh`/`aws`/`terraform` simulados (stubs).

## Capacidades

### Capacidades nuevas
- `instance-access`: acceso SSH del operador al servidor y la garantía de que los backups solo toman snapshot de un servidor detenido.

### Capacidades modificadas

## Impacto

- `terraform/main.tf`, `variable.tf`, `output.tf`; `script/destroy-and-backup.sh`; nuevo arnés `tests/script/` y objetivo `make script-test`.
- Apilado sobre `restore-world-from-snapshot`.
