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

```bash
sudo cat /home/pzserver/pzsvrtool/.admin_password    # contraseña del admin root (pzadmin)
sudo -iu pzserver pzsvrtool console
sudo -iu pzserver systemctl --user status pzsvrtool@zomboid.service
sudo -iu pzserver systemctl --user list-timers pz-auto-update.timer
sudo -iu pzserver journalctl --user -u pz-auto-update.service
sudo tail -f /var/log/cloud-init-output.log    # log del aprovisionamiento en el primer arranque
```

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
