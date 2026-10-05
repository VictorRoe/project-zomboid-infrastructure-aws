# Changelog

Todos los cambios relevantes del proyecto se documentan acá.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [Sin publicar]

### Seguridad
- Ya no existe la contraseña de admin por defecto `test`: si no se provee una, se genera en el host una contraseña aleatoria de 32 caracteres y se guarda en `/home/pzserver/pzsvrtool/.admin_password` (0600). Una contraseña provista tiene que tener al menos 12 caracteres, no ser un valor débil conocido y no contener espacios ni `=` ([#3](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/3)).

### Corregido
- La instalación del juego fallaba en silencio: pzsvrtool descargaba SteamCMD en un directorio sin permisos para `pzserver`, imprimía "Installation Completed" igual y el aprovisionamiento no terminaba. Ahora corre con el home de `pzserver` como directorio de trabajo y se verifica que el juego quedó instalado ([#15](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/15)).
- `docs/operations.md` y el mensaje final del playbook recomendaban `sudo -iu pzserver systemctl --user`, que puede no llegar al bus de usuario; ahora usan `XDG_RUNTIME_DIR` explícito. Se agregaron los comandos para iniciar, detener y reiniciar el servidor a mano.
- La configuración del backup es consistente: `destroy-and-backup.sh` lee bucket, región, nombre del servidor, IP y volumen raíz de los outputs de Terraform (reemplazables con `S3_BUCKET`, `AWS_REGION`, `PZ_SERVER_NAME`, `TF_DIR`), funciona desde cualquier directorio, hace snapshot del `root_volume_id` exacto y falla temprano si falta un valor ([#2](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/2)).
- `destroy-and-backup.sh` ahora detiene el servidor con el entorno correcto del bus de usuario de systemd, espera a que termine el proceso del juego y aborta antes del snapshot si no puede confirmarlo (`FORCE_SNAPSHOT=1` lo fuerza) ([#5](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/5)).
- Los datos del mundo se restauran en el `terraform apply` posterior a `destroy-and-backup.sh`: la instancia arranca desde una imagen registrada a partir del último `pz-world-data-snapshot`; `restore_snapshot_id` elige un snapshot específico y `restore_from_snapshot = false` lo desactiva ([#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)).
- El script de arranque de la EC2 ya no falla en un disco restaurado donde el repo ya existe.
- Despliegue en cualquier región de AWS: la AMI de Ubuntu se resuelve por región y `availability_zone` por defecto la elige AWS y se valida contra `aws_region` ([#4](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/4)).

### Cambiado
- Toda la documentación y los artefactos de OpenSpec pasaron al castellano.
- Los valores por defecto del playbook pasaron a `playbook/vars/main.yml`; la validación y el manejo de contraseña, a `playbook/tasks/`.
- **Migración:** definir `s3_bucket_name` con el bucket existente; el script ya no usa el hardcodeado `tu-bucket-zomboid-backups`.
- **Comportamiento:** el script de backup ya no sigue en silencio cuando no puede detener el servidor.
- Los cambios de AMI ya no reemplazan una instancia existente (`ignore_changes = [ami]`); para reconstruir, usar `terraform apply -replace=aws_instance.pz_server`.
- Se requiere Terraform `>= 1.9`; el lock file de providers se commitea.

### Agregado
- Pruebas locales con una VM QEMU/KVM que imita la EC2 (`make local-up`, `local-check`, `local-reboot-test`, `local-backup-test`, `local-restore-test`, `local-test`), sin AWS ([#14](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/14)).
- Variables de Terraform `repo_url` y `repo_branch` para elegir qué rama clona la instancia; `SSH_PORT` en el script de backup.
- `openspec/`: specs de comportamiento (7 capacidades) y las propuestas, diseños y tareas archivados de #1–#5 y #14.
- `make ansible-test`: tests offline de validación y generación de la contraseña.
- Variable de Terraform `pz_server_name` (se pasa al playbook) y outputs `backup_bucket_name`, `aws_region`, `pz_server_name`.
- Acceso SSH opcional: `ssh_public_key` o `ssh_key_name`, y `ssh_allowed_cidrs` para el puerto 22 ([#5](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/5)).
- `make script-test`: tests del script de backup contra stubs de `aws`/`ssh`/`terraform`.
- Output `restored_from_snapshot_id` y `make user-data-check`.
- `make test`: tests offline de Terraform (provider de AWS simulado) y chequeo de sintaxis de Ansible.
- `docs/` con arquitectura, flujos, spec, operación y registro de decisiones; problemas abiertos #7–#13 registrados.
- `CHANGELOG.md`, `CLAUDE.md` y un README ampliado.
