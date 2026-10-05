# Spec

Estado objetivo actual del stack. Actualizar este archivo con cada cambio y registrar el motivo en [decisions.md](decisions.md).

## AWS (Terraform)

| Ítem | Valor |
|---|---|
| Región / AZ | `aws_region` = `us-east-1`; `availability_zone` = `null` (AWS elige una dentro de la región; una AZ explícita tiene que pertenecer a `aws_region`) |
| Instancia | `instance_type` = `t3.large`, tag `Name=PZ-Server-Instance` (insuficiente para FalopaServer, ver [#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7)) |
| Imagen | Última Ubuntu Server 24.04 LTS amd64 (gp3) de Canonical en `aws_region`, o `ami_id` si está definida. Los cambios de AMI se ignoran en una instancia existente (`ignore_changes = [ami]`) |
| Disco | Un único volumen raíz gp3 de 30 GB (o el tamaño del snapshot si es mayor), `delete_on_termination=true`, tag `Name=pz-world-data-root` |
| Security group | `pz-server-sg`: UDP 16261–16262 y 8766 desde `0.0.0.0/0`; TCP 22 desde `ssh_allowed_cidrs` (por defecto `0.0.0.0/0`); todo el egreso permitido |
| Clave SSH | Opcional: `ssh_public_key` crea el key pair `pz-server`, o `ssh_key_name` usa uno existente (son excluyentes); ninguna por defecto |
| Backups | Snapshots EBS con tag `pz-world-data-snapshot`; bucket S3 `s3_bucket_name` = `zomboid-bucket-backup`. Tiene que existir de antemano y este stack no lo gestiona |
| Restauración | Al crear la instancia, si `restore_from_snapshot` (por defecto `true`) y existe un snapshot: registra la imagen `pz-restore-<snap>` desde el último snapshot con tag (o `restore_snapshot_id`) y arranca desde ella; tamaño raíz `max(30, tamaño del snapshot)`; el snapshot tiene que estar `completed` |
| Nombre del servidor | `pz_server_name` = `zomboid` (regex `^[A-Za-z0-9._-]+$`), se pasa al playbook vía `user_data` (`-e pz_server_name=`) |
| Origen del arranque | `repo_url` (repo de GitHub del proyecto) y `repo_branch` (`main`), validados; el `user_data` clona/actualiza esa rama |
| Outputs | `public_ip`, `root_volume_id`, `restored_from_snapshot_id`, `backup_bucket_name`, `aws_region`, `pz_server_name` |
| Estado | Local, sin backend |
| Herramientas | Terraform `>= 1.9`, provider de AWS `~> 6.0`, lock file commiteado |

## Tests (offline)

`make test` corre todo sin credenciales de AWS ni llamadas a la API:

- `make tf-test`: `terraform fmt/validate/test` contra un provider de AWS simulado (mock). Suites: `terraform/tests/{ami,restore,ssh,config}.tftest.hcl`.
- `make user-data-check`: renderiza el script de arranque y corre `bash -n` + shellcheck.
- `make script-test`: `tests/script/run.sh` (script de backup con `aws`/`ssh`/`terraform` reemplazados por stubs) + shellcheck.
- `make ansible-check`: chequeo de sintaxis del playbook.
- `make ansible-test`: `tests/ansible/run.sh` (validación y generación de la contraseña en localhost).

## Pruebas locales con VM (sin AWS)

`local/vm.sh` (targets `make local-*`) levanta con QEMU/KVM la imagen cloud oficial de Ubuntu 24.04 (verificada con `SHA256SUMS`) y le pasa por cloud-init NoCloud el `user_data` renderizado por Terraform, sin cambios, más la clave SSH. VM de 4 vCPU y 10 GB; puertos reenviados a `127.0.0.1`: SSH 2222, UDP 16261, 16262 y 8766. Estado en `.local-vm/` (ignorado por git). Pruebas: `check` (11 chequeos), `reboot-test`, `backup-test` (script real con SSH real; `aws`/`terraform` simulados) y `restore-test` (copia del disco + `instance-id` nuevo). Detalle en [operations.md](operations.md#pruebas-locales-con-una-vm-sin-aws).

## Script de backup

| Ítem | Valor |
|---|---|
| Configuración | Sale de los outputs de Terraform (`terraform -chdir=<repo>/terraform`); `S3_BUCKET`, `AWS_REGION`, `PZ_SERVER_NAME` y `TF_DIR` la reemplazan. Falla antes de cualquier acción si falta un valor |
| Disco | Output `root_volume_id` |
| Metadatos | `s3://<bucket>/latest/snapshot_meta.txt` (el `latest/` anterior se copia a `archive/<fecha>/`) |
| Detención | `systemctl --user stop pzsvrtool@<pz_server_name>.service` como `pzserver` con `XDG_RUNTIME_DIR`; el `ExecStop` de pzsvrtool avisa "Unplanned shutdown", hace una cuenta regresiva de 3 min y guarda (si no termina en 2 min más, `kill -9`). Después consulta hasta que no quede proceso `ProjectZomboid` |
| Tiempo de espera | `STOP_TIMEOUT` = 600 s; consulta cada `POLL_INTERVAL` = 5 s |
| Si falla | Aborta antes del snapshot (exit 1). `FORCE_SNAPSHOT=1` sigue con una advertencia |
| SSH | `ubuntu@<public_ip>`, puerto `SSH_PORT` (22), archivo de identidad `SSH_KEY`, `BatchMode`, sin fijar la host key |

## Host (Ansible)

Los valores por defecto están en `playbook/vars/main.yml`; la validación, en `playbook/tasks/validate.yml`, y el manejo de la contraseña de admin, en `playbook/tasks/admin_password.yml`.

| Ítem | Valor |
|---|---|
| Requisitos del SO | Familia Debian, x86_64, ≥ 2 vCPU, ≥ 7500 MB de RAM |
| Cuenta de servicio | `pzserver`, home `/home/pzserver`, linger activo |
| pzsvrtool | `1.7.3` (`.deb` con versión fija) |
| Nombre del servidor | `pz_server_name` (por defecto `zomboid`; Terraform pasa su valor) |
| Rama de Steam | pública (`pz_branch: ""`; revisar contra la build del servidor, ver [#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7)) |
| Admin | `pzadmin`. Contraseña: provista con `-e pz_admin_password` (≥ 12 caracteres, fuera de la lista de débiles, sin espacios ni `=`) o una aleatoria alfanumérica de 32 caracteres generada en la primera ejecución. En ambos casos se guarda en `/home/pzserver/pzsvrtool/.admin_password` (0600, `pzserver`) y se reutiliza |
| Contraseña de ingreso | Ninguna, ni whitelist (ver [#13](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/13)) |
| Configuración del juego | No gestionada (ini, SandboxVars, mods; ver [#8](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/8)) |
| Swap | `/swapfile`, 2 GB |
| Backups (pzsvrtool) | activados, límite 10; cuenta regresiva de apagado 5 min |
| Actualización automática | activada; ventana 03:00–06:00 `America/Argentina/Buenos_Aires`; chequeo cada 15 min; aviso de 5 min; tiempo máximo de apagado 20 min |
| Firewall | UFW: TCP 22, UDP 16261, 16262, 8766 |
