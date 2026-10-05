# Operación

Runbook del día a día para levantar, probar, mantener, dar de baja y destruir el servidor. Los valores están en [spec.md](spec.md), los costos en [costs.md](costs.md) y las secuencias internas en [flows.md](flows.md).

Todo se maneja desde la máquina del operador con Terraform y `script/pz-ctl.sh`, que lee sus datos de los outputs de Terraform. Se puede ejecutar desde cualquier directorio.

| Quiero… | Comando |
|---|---|
| Ver el estado | `script/pz-ctl.sh status` |
| Empezar una sesión de juego | `script/pz-ctl.sh start` |
| Terminar la sesión (deja de cobrar la EC2) | `script/pz-ctl.sh stop` |
| Backup consistente ahora | `script/pz-ctl.sh backup` |
| Cambiar la configuración del juego | commitear el directorio de configuración → `script/pz-ctl.sh push-config <dir>` |
| Pasar la contraseña a los jugadores | `script/pz-ctl.sh join-password` |
| Cambiar la contraseña de ingreso | `script/pz-ctl.sh rotate-join-password` |
| Actualizar el código del servidor | `repo_commit` nuevo → `terraform apply` → `script/pz-ctl.sh provision` |
| Medir RAM/CPU | `script/pz-ctl.sh metrics 60 60` |
| Dar de baja conservando el mundo | `script/destroy-and-backup.sh` |
| Probar sin AWS | `make test` y `make local-test` |

## 0. Requisitos

- Terraform ≥ 1.11, AWS CLI v2 con credenciales del operador, `ssh`, `git` y `python3`.
- El repo tiene que ser **público**: la instancia lo clona al arrancar, sin credenciales.
- Un directorio de configuración del juego versionado en git (ver [Configuración del juego](#configuración-del-juego)).

## 1. Levantar por primera vez

### 1.1 Estado remoto de Terraform (una vez por cuenta y región)

```bash
cd bootstrap/state-backend
terraform init && terraform apply              # bucket pz-tfstate-<cuenta>-<región>: versionado, cifrado, privado
terraform output -raw backend_hcl > ../../terraform/backend.hcl
```

Este stack tiene su propio estado local (`bootstrap/state-backend/terraform.tfstate`, ignorado por git; guardarlo en un lugar seguro) y `prevent_destroy`, así que la baja del servidor nunca lo borra. Permisos mínimos del operador sobre el estado: `s3:ListBucket` en el bucket, y `s3:GetObject`/`PutObject`/`DeleteObject` en `project-zomboid/terraform.tfstate` y en `project-zomboid/terraform.tfstate.tflock`.

### 1.2 Variables

`terraform/terraform.tfvars` (ignorado por git):

```hcl
repo_commit       = "<SHA de 40 caracteres de main, ya mergeado y probado>"  # git rev-parse origin/main
ssh_public_key    = "ssh-ed25519 AAAA... vos@host"     # o: ssh_key_name = "par-existente"
ssh_allowed_cidrs = ["203.0.113.4/32"]                 # tu IP pública: curl -s https://checkip.amazonaws.com
pz_server_name    = "miserver"                         # = nombre de los archivos de configuración
# Opcionales: aws_region, instance_type, pz_java_xmx_mb (ver costs.md), backup_time_utc, backup_retain_count
```

### 1.3 Crear, configurar y jugar

```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform apply                                         # EC2 + Elastic IP + SG + política DLM
../script/pz-ctl.sh status                              # esperar ~10 min al primer aprovisionamiento
../script/pz-ctl.sh push-config ~/mi-config             # el juego espera esto antes de crear el mundo
../script/pz-ctl.sh join-password                       # pasarla a los jugadores por un canal privado
terraform output -raw public_ip                         # los jugadores se conectan a <ip>:16261
```

Para seguir el aprovisionamiento: `ssh ubuntu@<ip> sudo tail -f /var/log/cloud-init-output.log`.

## 2. Sesiones de juego (stop/start)

```bash
script/pz-ctl.sh start      # inicia la EC2; el juego arranca solo en unos minutos; misma IP
script/pz-ctl.sh stop       # apagado ordenado del juego (cuenta regresiva de 3 min) y después stop de la EC2
script/pz-ctl.sh status
```

- `stop` no detiene la EC2 si no puede confirmar por SSH que el juego terminó. `FORCE_STOP=1` lo hace igual, como excepción explícita.
- Con la EC2 detenida se siguen cobrando el disco, la Elastic IP y los snapshots (unos 6,65 USD/mes con los valores por defecto).
- Repetir `start` o `stop` es seguro: si la EC2 ya está en el estado pedido, no hace nada, y si está en transición, espera (`INSTANCE_TIMEOUT`, 600 s).

## 3. Mantener

### Backups

- **Automáticos:** DLM toma un snapshot diario (`backup_time_utc`, 09:00 UTC por defecto) y conserva `backup_retain_count` (7). Se etiquetan `Name=pz-world-data-snapshot-auto` y `pz-consistency=crash`: si el juego estaba corriendo, son *crash-consistent* (como un corte de luz). La restauración automática no los elige, así que hay que pasarlos a mano.
- **Consistente a pedido:** `script/pz-ctl.sh backup` detiene el juego, hace el snapshot (`pz-world-data-snapshot`, `pz-consistency=application`) y lo vuelve a iniciar (con la EC2 detenida, no hace falta detener nada). Conviene antes de cambios grandes.
- Listar: `aws ec2 describe-snapshots --owner-ids self --filters Name=tag:pz-server,Values=<nombre> --query 'Snapshots[].[SnapshotId,StartTime,Tags[?Key==\`Name\`].Value|[0]]' --output table`.
- Objetivos: pérdida máxima de hasta 24 h (RPO) con los automáticos, o la del último backup consistente. Tiempo de recuperación (RTO) objetivo: 1 hora (apply + arranque + aprovisionamiento; sin medir todavía en AWS).

### Configuración del juego

El directorio lo provee el operador y tiene que estar en git, sin cambios sin commitear: el commit queda registrado en el host. Contrato (los nombres = `pz_server_name`):

| Archivo | |
|---|---|
| `<nombre>.ini` | Obligatorio. `Mods=`, `WorkshopItems=` y `Map=` exactamente una vez cada uno y `Map=` no vacío. `DefaultPort`/`UDPPort` iguales a los puertos abiertos (16261/16262) |
| `<nombre>_SandboxVars.lua` | Obligatorio |
| `<nombre>_spawnregions.lua`, `<nombre>_spawnpoints.lua` | Opcionales |

- `Password=` y `RCONPassword=` los gestiona Ansible (contraseña de ingreso, y RCON desactivado). Cualquier otro valor `<redacted>`/`CHANGE_ME` se rechaza: hay que vaciarlo o completarlo.
- `push-config` valida en el host antes de reemplazar nada. Si la configuración cambió, detiene el juego en orden, guarda una copia de la anterior en `~pzserver/pzsvrtool/config-backups/` (conserva 10) y aplica. El orden de `Mods=`/`Map=` nunca se toca.
- **Cambios manuales en el host** (o comandos de admin dentro del juego que reescriben el `.ini`): no se pisan al reaprovisionar ni al restaurar; cada ejecución avisa qué claves difieren. La próxima `push-config` los guarda en la copia y aplica la versión subida. Para conservarlos, incorporarlos al directorio y volver a subirlo.
- Mods y mapas se descargan solos del Workshop al iniciar el juego, en el orden de `WorkshopItems=`.

### Contraseñas

```bash
script/pz-ctl.sh join-password            # contraseña de ingreso (Password= del .ini)
script/pz-ctl.sh rotate-join-password     # genera otra: reinicia el juego; los jugadores reconectan con la nueva
ssh ubuntu@<ip> sudo cat /home/pzserver/pzsvrtool/.admin_password   # admin root (pzadmin)
```

Las dos se guardan en el disco del mundo (0600, `pzserver`), así que sobreviven a reaprovisionar, a stop/start y a una restauración. Nunca pasan por Git, Terraform ni los logs. La de ingreso siempre es distinta de la de admin.

### Actualizar el código del servidor (revisión fija)

```bash
git fetch && git rev-parse origin/main            # el commit nuevo, ya mergeado y probado
# repo_commit = "<sha>" en terraform.tfvars
terraform -chdir=terraform apply                  # no reinicia la EC2 (solo actualiza el output)
script/pz-ctl.sh provision                        # corre el playbook en ese commit en el host
```

Si el commit no existe o no coincide, `pz-provision` aborta sin usar otra revisión. Para probar una rama sin mergear: `repo_follow_branch = true`, `repo_commit = ""` y `repo_branch = "<rama>"` (modo mutable, solo para pruebas).

### Actualizaciones del juego y heap

- El juego se actualiza solo dentro de la ventana 03:00–06:00 (Argentina): avisa, se apaga en orden, hace un backup, reinstala y vuelve a fijar el heap.
- Cambiar el heap o el tipo de instancia: `pz-ctl.sh stop` → `terraform apply -var instance_type=… -var pz_java_xmx_mb=…` → `pz-ctl.sh start` → `pz-ctl.sh provision`. El plan falla si la instancia no tiene RAM para heap + margen.

### SSH

- Sin `ssh_allowed_cidrs` no hay SSH, y `stop`/`backup`/`push-config`/`destroy-and-backup.sh` no funcionan (el plan lo avisa).
- **Si cambia tu IP:** actualizar `ssh_allowed_cidrs` y `terraform apply` (solo cambia el security group, en el momento). Para no quedarse afuera, agregar la IP nueva antes de quitar la vieja. UFW en el host permite el puerto 22: el origen lo filtra el security group.
- `0.0.0.0/0` se rechaza salvo con `ssh_allow_any_source = true`, una excepción documentada que no se recomienda.

### En el servidor (por SSH)

```bash
PZ="sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/$(id -u pzserver)"
$PZ systemctl --user status  pzsvrtool@<nombre>.service     # también start / stop / restart
$PZ systemctl --user list-timers pz-auto-update.timer
$PZ journalctl --user -u pz-auto-update.service
sudo -iu pzserver pzsvrtool console                          # consola del servidor (tmux)
sudo -iu pzserver pzsvrtool message "Reinicio en 5 minutos"
cat /var/lib/pz-provision/revision                           # commit en uso
sudo cat /home/pzserver/pzsvrtool/config-applied.json        # configuración en uso y su origen
```

`systemctl --user` necesita `XDG_RUNTIME_DIR`; `sudo -iu pzserver` no lo arma.

## 4. Restaurar

```bash
terraform apply                                          # tras una baja: restaura el último pz-world-data-snapshot
terraform apply -var restore_snapshot_id=snap-0abc...    # un snapshot específico (p. ej. uno automático)
terraform apply -var restore_from_snapshot=false         # mundo nuevo, ignorando los snapshots
terraform output restored_from_snapshot_id
```

Si se perdió la instancia (falla de la AZ o del disco): elegir el último snapshot automático con el comando de listado de arriba y aplicar con `restore_snapshot_id`. Para reconstruir una instancia en marcha con una imagen nueva: backup → `terraform apply -replace=aws_instance.pz_server`.

## 5. Dar de baja (conservando el mundo)

```bash
script/destroy-and-backup.sh       # detener el juego → snapshot consistente → terraform destroy
```

Elimina la EC2, el disco, la Elastic IP (deja de cobrarse), el security group, la política DLM y su rol. Quedan los snapshots (manuales y automáticos), que siguen costando. Con la EC2 ya detenida, no hace falta SSH. `FORCE_SNAPSHOT=1` hace el snapshot aunque no se confirme la detención (queda `pz-consistency=unconfirmed`).

## 6. Destruir todo

Irreversible: borra el mundo.

```bash
terraform -chdir=terraform destroy                                   # sin snapshot previo
aws ec2 describe-snapshots --owner-ids self --filters Name=tag:pz-server,Values=<nombre> --query 'Snapshots[].SnapshotId' --output text \
  | xargs -n1 aws ec2 delete-snapshot --snapshot-id                  # snapshots del servidor (revisar la lista antes)
aws ec2 describe-images --owners self --filters Name=name,Values='pz-restore-*'   # no debería quedar ninguna
# Estado remoto (solo si no queda ningún stack que lo use): vaciar el bucket con todas sus versiones,
# quitar prevent_destroy en bootstrap/state-backend/main.tf y correr terraform destroy ahí.
```

Snapshots anteriores a este cambio no tienen el tag `pz-server`: buscarlos con `Name=tag:Name,Values=pz-world-data-snapshot*`. El bucket S3 de metadatos que usaban versiones anteriores ya no se usa ni se borra solo ([D28](decisions.md)).

## 7. Probar sin AWS

```bash
make test             # offline: Terraform (mock), bootstrap, user_data, pz-provision, scripts con stubs, Ansible en localhost
make local-test       # VM QEMU/KVM con la misma imagen y user_data que la EC2 (~20 min)
```

`make test` necesita Terraform ≥ 1.11, ansible-core, `git` y `python3` (`shellcheck` es opcional). `terraform init` descarga los providers, pero nunca llama a AWS.

### VM local

Levanta con QEMU/KVM la imagen cloud oficial de Ubuntu 24.04 y le pasa por cloud-init el mismo `user_data` que renderiza Terraform. Requiere KVM, `qemu-system-x86_64`, `qemu-img`, `cloud-localds`, unos 10 GB de RAM libres y ~15 GB de disco.

La VM clona el repo desde un servidor git HTTP en el host (`127.0.0.1:8730`, que dentro de la VM es `10.0.2.2`), con el **commit actual fijado**: hay que commitear, pero no pushear. `LOCAL_REPO_SOURCE=github` clona desde GitHub (rama pusheada, repo público).

```bash
make local-up             # crea la VM y aprovisiona; check: revisión, contraseñas, heap, el juego espera la config
make local-config-test    # push-config real con la config de tests/ansible/fixtures; el juego arranca con ella
make local-reboot-test    # reinicia y verifica que el juego vuelve solo
make local-backup-test    # destroy-and-backup.sh con SSH real (aws/terraform simulados)
make local-restore-test   # copia el disco y arranca con otro instance-id (como una restauración)
make local-test           # todo lo anterior, en orden
make local-ssh            # shell (o: local/vm.sh ssh '<comando>')
make local-down           # apaga (el disco queda); make local-clean borra discos y claves
```

Con la VM corriendo se puede jugar contra `127.0.0.1:16261` con la contraseña de `local/vm.sh ssh 'sudo cat /home/pzserver/pzsvrtool/.join_password'`. Variables: `LOCAL_VM_MEM` (10240), `LOCAL_VM_CPUS` (4), `LOCAL_VM_DISK` (40G), `LOCAL_SSH_PORT` (2222), `LOCAL_GIT_PORT` (8730), `PROVISION_TIMEOUT` (3600 s).

**No cubre:** la búsqueda real de la AMI, el arranque en hardware de AWS, los snapshots EBS, DLM, la Elastic IP, el security group, el backend S3 ni el ingreso de un cliente real.
