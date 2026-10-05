# Proposal

## Por qué

Los tests actuales son offline con mocks (D9, D11): validan la lógica de Terraform, del script y de la contraseña, pero no ejecutan nunca el arranque real (cloud-init → Ansible → pzsvrtool → SteamCMD → servicio systemd), ni el inicio automático tras un reinicio, ni la restauración de un disco con `user_data` que vuelve a correr. Esos caminos son justamente los que el PR #6 deja "sin verificar" ([#14](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/14)).

## Qué cambia

- Entorno local con QEMU/KVM que arranca la misma imagen cloud de Ubuntu 24.04 que usa AWS y le pasa, vía cloud-init NoCloud, el mismo `user_data` que renderiza Terraform.
- Pruebas automatizadas sobre esa VM: aprovisionamiento completo, arranque automático tras `reboot`, restauración (copia del disco + `instance-id` nuevo) y detención verificada del script de backup contra un servidor real (llamadas a AWS con stubs).
- Reenvío de puertos para conectarse con el juego a `localhost:16261`.
- Variables de Terraform `repo_url` y `repo_branch` para que el arranque clone una rama sin mergear (también útil en AWS; parte de [#12](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/12)).
- Variable de entorno `SSH_PORT` en el script de backup (por defecto 22) para apuntarlo a la VM.

## Capacidades

### Capacidades nuevas
- `local-integration-testing`: prueba del aprovisionamiento real y de los ciclos de reinicio, restauración y backup en una VM local que imita la EC2.
- `server-bootstrap`: de dónde obtiene la instancia el código que la configura al arrancar.

### Capacidades modificadas
- `world-backup`: se agrega la posibilidad de elegir el puerto SSH.

## Impacto

- Nuevo `local/vm.sh`, targets `local-*` en el `Makefile`, `.local-vm/` (ignorado por git) para imágenes, discos, claves y logs.
- `terraform/variable.tf`, `terraform/main.tf` (template), `terraform/tests/config.tftest.hcl`; `script/destroy-and-backup.sh`, `tests/script/run.sh`.
- Requiere en el host: KVM, `qemu-system-x86_64`, `qemu-img`, `cloud-localds`; unos 10 GB de RAM libres y ~15 GB de disco. No usa AWS. La primera ejecución descarga la imagen de Ubuntu (~600 MB) y el juego por Steam (varios GB).
- No cubre: búsqueda real de AMI, modo de arranque en hardware de AWS, snapshots EBS ni security group.
