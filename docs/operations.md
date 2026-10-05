# Operación

Comandos del día a día. Los valores están en [spec.md](spec.md).

## Despliegue y baja

El acceso SSH, que necesita el script de backup, se define en `terraform.tfvars` (ignorado por git):

```hcl
s3_bucket_name    = "mi-bucket-existente"              # tiene que existir; este stack no lo crea
ssh_public_key    = "ssh-ed25519 AAAA... vos@host"     # o: ssh_key_name = "par-existente"
ssh_allowed_cidrs = ["203.0.113.4/32"]
```

```bash
cd terraform
terraform init
terraform apply                       # crea el servidor y lo configura vía user_data
terraform output -raw public_ip       # los jugadores se conectan a <ip>:16261
../script/destroy-and-backup.sh       # detener, snapshot, metadatos en S3, terraform destroy (desde cualquier directorio)
SSH_KEY=~/.ssh/pz ../script/destroy-and-backup.sh     # con un archivo de identidad específico
S3_BUCKET=otro-bucket ../script/destroy-and-backup.sh # reemplazar un output (también AWS_REGION, PZ_SERVER_NAME, TF_DIR)
FORCE_SNAPSHOT=1 ../script/destroy-and-backup.sh      # último recurso: snapshot aunque no se confirme la detención
```

## En el servidor

El servidor arranca solo: al crearse la instancia, en cada reinicio de la máquina (servicio habilitado con linger) y después de cada actualización del juego. Los comandos de abajo son para manejarlo a mano.

`systemctl --user` y `journalctl --user` necesitan el entorno del bus de usuario de `pzserver`; `sudo -iu pzserver` no lo arma. Por eso se usa `XDG_RUNTIME_DIR` explícito:

```bash
PZ="sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/$(id -u pzserver)"

$PZ systemctl --user status  pzsvrtool@zomboid.service    # estado
$PZ systemctl --user start   pzsvrtool@zomboid.service    # iniciar
$PZ systemctl --user stop    pzsvrtool@zomboid.service    # detener
$PZ systemctl --user restart pzsvrtool@zomboid.service    # reiniciar
$PZ systemctl --user list-timers pz-auto-update.timer     # próximo chequeo de actualización
$PZ journalctl --user -u pz-auto-update.service           # logs de actualización

sudo cat /home/pzserver/pzsvrtool/.admin_password    # contraseña del admin root (pzadmin)
sudo -iu pzserver pzsvrtool console                  # consola del servidor (tmux)
sudo -iu pzserver pzsvrtool message "Reinicio en 5 minutos"   # aviso a los jugadores
sudo -iu pzserver pzsvrtool quit --time 5            # apagado ordenado con cuenta regresiva
sudo -iu pzserver pzsvrtool backupnow                # backup inmediato
sudo tail -f /var/log/cloud-init-output.log          # log del aprovisionamiento en el primer arranque
```

Si el servidor no se llama `zomboid`, reemplazar el nombre del servicio por `pzsvrtool@<pz_server_name>.service`.

## Restauración

```bash
terraform apply                                          # restaura desde el último pz-world-data-snapshot, si hay
terraform apply -var restore_snapshot_id=snap-0abc...    # restaurar un snapshot específico
terraform apply -var restore_from_snapshot=false         # mundo nuevo, ignorar snapshots
terraform output restored_from_snapshot_id
```

Los snapshots viejos se conservan y siguen costando. Borrar los que ya no hagan falta con `aws ec2 delete-snapshot`.

## Reconstruir con una imagen más nueva

En una instancia que está corriendo, los cambios de imagen se ignoran. Para reconstruir a propósito, hacer antes un backup, porque se borra el disco raíz (el mundo):

```bash
terraform apply -replace=aws_instance.pz_server
```

## Chequeos locales (sin AWS)

```bash
make test             # todo lo de abajo
make tf-test          # terraform init/fmt/validate/test (provider de AWS simulado)
make ansible-check    # chequeo de sintaxis del playbook
make user-data-check  # renderiza el script de arranque de la EC2, bash -n + shellcheck
make script-test      # script de backup contra stubs de aws/ssh/terraform
make ansible-test     # validación/generación de la contraseña de admin en localhost
terraform -chdir=terraform test -filter=tests/restore.tftest.hcl   # una sola suite
```

Requiere Terraform >= 1.9 y ansible-core. `terraform init` descarga el provider del registry pero nunca llama a AWS.

## Pruebas locales con una VM (sin AWS)

Levanta con QEMU/KVM la misma imagen cloud de Ubuntu 24.04 que usa AWS y le pasa por cloud-init el mismo `user_data` que renderiza Terraform. Así se prueba el aprovisionamiento real (Ansible, pzsvrtool, Steam, servicio systemd) sin gastar en AWS. Requiere KVM, `qemu-system-x86_64`, `qemu-img`, `cloud-localds`, unos 10 GB de RAM libres y ~15 GB de disco.

La VM clona la **rama actual desde GitHub**, así que tiene que estar pusheada (el script lo verifica). Para otra rama: `LOCAL_REPO_BRANCH=<rama>`.

```bash
make local-up             # descarga y verifica la imagen, crea la VM y espera el aprovisionamiento; luego corre check
make local-check          # servicio, proceso, puerto 16261/udp, linger, timer, contraseña, UFW
make local-reboot-test    # reinicia la VM y verifica que el juego vuelve solo
make local-backup-test    # script de backup con SSH real contra la VM y aws/terraform simulados
make local-restore-test   # copia el disco y arranca con otro instance-id (como una AMI restaurada)
make local-test           # todo lo anterior en orden
make local-ssh            # shell en la VM (o: local/vm.sh ssh '<comando>')
make local-down           # apaga la VM (el disco queda)
make local-clean          # borra discos, seed y claves (la imagen base queda en .local-vm/)
```

Con la VM corriendo se puede jugar contra ella: en el juego, conectarse a `127.0.0.1:16261`. La contraseña del admin: `local/vm.sh ssh 'sudo cat /home/pzserver/pzsvrtool/.admin_password'`.

Variables opcionales: `LOCAL_VM_MEM` (MB, 10240), `LOCAL_VM_CPUS` (4), `LOCAL_VM_DISK` (40G), `LOCAL_SSH_PORT` (2222), `PROVISION_TIMEOUT` (3600 s), `LOCAL_REPO_BRANCH`.

**No cubre:** la búsqueda real de la AMI, el arranque en hardware de AWS (Nitro, ENA, `uefi-preferred`), los snapshots EBS ni el security group.
