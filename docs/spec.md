# Spec

Estado objetivo actual del stack. Actualizar este archivo con cada cambio y registrar el motivo en [decisions.md](decisions.md). Costos en [costs.md](costs.md).

## AWS (Terraform)

| Ítem | Valor |
|---|---|
| Región / AZ | `aws_region` = `us-east-1` (se conserva; comparación con `sa-east-1` en [costs.md](costs.md#región-11)); `availability_zone` = `null` (AWS elige; una AZ explícita tiene que pertenecer a la región) |
| Tier | `tier` = `estandar`. Perfiles (instancia / heap / margen / disco): `minimo` `t3.medium` 2560/1024/30 GB; `estandar` `m7i.large` 5632/1536/30 GB; `robusto` `r7i.large` 13312/2048/50 GB; `grande` `m7i.xlarge` 12800/2560/60 GB. `instance_type`, `pz_java_xmx_mb`, `pz_host_overhead_mb` y `root_volume_size_gb` (null por defecto) los reemplazan. Output `tier` con los valores efectivos |
| Instancia | La del tier (x86_64), tag `Name=PZ-Server-Instance`, perfil de IAM `pz-server-<nombre>` si hay snapshots automáticos. Precondiciones: arquitectura x86_64 y RAM nominal ≥ `pz_java_xmx_mb` + `pz_host_overhead_mb`. Aviso de plan (`check.burstable_cpu`) si es burstable |
| Heap | El del tier, salvo `pz_java_xmx_mb`/`pz_host_overhead_mb` (se pasan al playbook) |
| Imagen | Última Ubuntu Server 24.04 LTS amd64 (gp3) de Canonical en la región, o `ami_id`. `ignore_changes = [ami, user_data]` |
| Disco | Un volumen raíz gp3 del tamaño del tier (o el del snapshot, si es mayor; solo puede crecer), `delete_on_termination=true`, tags `Name=pz-world-data-root` y `pz-world-volume=<pz_server_name>` |
| Dirección | Elastic IP `pz-server-eip` asociada a la instancia (estable entre stop/start); output `public_ip` |
| Security group | `pz-server-sg`: UDP 16261–16262 y 8766 desde `0.0.0.0/0`; TCP 22 solo si `ssh_allowed_cidrs` no está vacía, y desde esas redes; todo el egreso permitido |
| SSH | `ssh_allowed_cidrs` = `[]` (sin SSH). Solo CIDRs IPv4 con la dirección de red; `/0` se rechaza salvo con `ssh_allow_any_source = true`. Key pair opcional: `ssh_public_key` (crea `pz-server`) o `ssh_key_name` (excluyentes). Aviso de plan (`check.ssh_access_for_operations`) si falta la clave o las redes |
| Snapshots automáticos | `auto_backup_enabled` = true: los hace la propia instancia (timer de systemd, `pz-auto-snapshot`), así que solo los días que está prendida: a las `backup_time_utc` = `09:00` UTC o, si estaba apagada a esa hora, al volver a prenderla (`Persistent=true`); no más de uno cada 12 h. Tags: `Name=pz-world-data-snapshot-auto`, `pz-backup=auto`, `pz-consistency=crash`, `pz-server`. Rotación: se conservan los `backup_retain_count` = 4 más nuevos (solo borra automáticos completados de este servidor). Rol `pz-server-<nombre>`: `CreateSnapshot` solo del volumen con `pz-world-volume=<nombre>`, `CreateTags` solo al crear, `DeleteSnapshot` solo con `pz-backup=auto` y `pz-server=<nombre>`, `Describe*` |
| Restauración | Al crear la instancia, si `restore_from_snapshot` (true) y existe: imagen `pz-restore-<snap>` desde el último snapshot con `Name=pz-world-data-snapshot` (consistente) o `restore_snapshot_id`; tamaño `max(30, snapshot)`; el snapshot tiene que estar `completed` |
| Nombre del servidor | `pz_server_name` = `zomboid` (`^[A-Za-z0-9._-]+$`) |
| Configuración del juego | `pz_wait_for_config` = true: el juego no arranca hasta tener configuración subida o un mundo existente |
| Origen del arranque | `repo_url` (este repo, https; o `http://10.0.2.2:<puerto>/…` solo para la VM local), `repo_branch` = `main`, `repo_commit` (SHA de 40 caracteres, **obligatorio**), `repo_follow_branch` = false (modo de prueba mutable; excluyente con `repo_commit`) |
| `user_data` | Escribe `/etc/pz-provision.env` (sin secretos), instala `/usr/local/sbin/pz-provision` (`terraform/templates/pz-provision.sh`) y lo ejecuta; < 16 KB |
| Outputs | `public_ip`, `instance_id`, `root_volume_id`, `restored_from_snapshot_id`, `aws_region`, `pz_server_name`, `repo_commit`, `ssh_enabled`, `tier`, `auto_backup` |
| Estado | Backend S3 (`terraform/backend.tf`): key `project-zomboid/terraform.tfstate`, `encrypt`, `use_lockfile` (bloqueo nativo); bucket y región en `backend.hcl` (ignorado por git) |
| Bucket del estado | `bootstrap/state-backend`: `pz-tfstate-<cuenta>-<región>`, versionado, SSE-S3, sin acceso público, `BucketOwnerEnforced`, solo TLS, versiones anteriores 90 días, `prevent_destroy`, estado local propio |
| Herramientas | Terraform `>= 1.11`, provider de AWS `~> 6.0`, lock files commiteados |

## Arranque (`pz-provision`)

| Ítem | Valor |
|---|---|
| Revisión | Modo fijo: obtiene `repo_branch`; si el commit no está en ella, lo pide por SHA; si no existe, aborta. Checkout `--detach` con `--force` y verifica `HEAD = repo_commit` antes de Ansible. Modo rama: la punta de `repo_branch`, advertido como mutable |
| Ejecución | git y Ansible como `ubuntu`; playbook con `-e pz_server_name`, `pz_java_xmx_mb`, `pz_host_overhead_mb`, `pz_wait_for_config` |
| Registro | `/var/lib/pz-provision/revision` (`commit`, `mode`, `applied_at`) |
| Actualización deliberada | `pz-provision --commit <sha>` (vía `pz-ctl.sh provision`); el `.env` se actualiza solo si el playbook termina bien. `-- <args>` pasa argumentos a ansible-playbook |
| Límites de reproducibilidad | Fijos: código del repo, pzsvrtool `1.7.3` con sha256. Variables: paquetes apt y Ansible del PPA, imagen de Ubuntu (al crear), build del juego (rama pública de Steam) y mods del Workshop |

## Scripts del operador

| Ítem | Valor |
|---|---|
| Configuración | Outputs de Terraform (`terraform -chdir=<repo>/terraform`); `AWS_REGION`, `PZ_SERVER_NAME`, `INSTANCE_ID` y `TF_DIR` los reemplazan. Fallan antes de actuar si falta un valor. `script/lib/common.sh` es compartido |
| `pz-ctl.sh` | `status`, `start`, `stop`, `backup`, `provision`, `push-config <dir>`, `join-password`, `rotate-join-password`, `metrics [n] [seg]` |
| start/stop | Consultan el estado hasta `INSTANCE_TIMEOUT` = 600 s; idempotentes; `terminated`/`shutting-down` → error. `stop` confirma el apagado del juego por SSH antes de `stop-instances` (`FORCE_STOP=1` lo omite, con advertencia) |
| Detención del juego | `systemctl --user stop pzsvrtool@<nombre>.service` como `pzserver` con `XDG_RUNTIME_DIR`; consulta `pgrep ProjectZomboid` hasta `STOP_TIMEOUT` = 600 s cada `POLL_INTERVAL` = 5 s |
| Snapshots manuales | Tags `Name=pz-world-data-snapshot`, `pz-server`, `pz-backup=manual`, `pz-consistency=application` (`unconfirmed` si se forzó). Esperan a `completed`; si falla, no se destruye nada |
| `backup` | EC2 corriendo: detener el juego → snapshot → volver a iniciarlo (también si el snapshot falla). EC2 detenida: snapshot directo |
| `destroy-and-backup.sh` | Detener el juego (o EC2 ya detenida) → snapshot → `terraform destroy`. `FORCE_SNAPSHOT=1` sigue sin confirmación. Sin S3 |
| `push-config` | Sube solo los archivos del contrato más `SOURCE` (`git:<origin>@<sha>`; rechaza cambios sin commitear salvo `ALLOW_DIRTY=1`, y directorios fuera de git salvo `ALLOW_UNVERSIONED=1`). Valida en el host con el renderizador del playbook antes de reemplazar `~pzserver/pzsvrtool/config-staged`, y después corre `provision` |
| SSH | `ubuntu@<public_ip>`, `SSH_PORT` (22), `SSH_KEY`, `BatchMode`, sin fijar host key. Preflight: si `ssh_enabled = false`, error con la configuración necesaria |

## Host (Ansible)

Valores por defecto en `playbook/vars/main.yml`; validación en `tasks/validate.yml`; heap, contraseña de ingreso y configuración en `tasks/game_settings.yml`.

| Ítem | Valor |
|---|---|
| Requisitos del SO | Debian/Ubuntu x86_64, ≥ 2 vCPU, RAM utilizable (`ansible_memtotal_mb`) ≥ `pz_java_xmx_mb` + `pz_host_overhead_mb` |
| Cuenta de servicio | `pzserver`, home `/home/pzserver`, linger activo |
| pzsvrtool | `1.7.3`, `.deb` verificado con sha256 (no se vuelve a descargar si ya está) |
| Heap | `-Xmx<pz_java_xmx_mb>m` en `ProjectZomboid64.json` (`pz-set-heap.py`; baja un `-Xms` mayor); se vuelve a fijar después de cada actualización del juego |
| Rama de Steam | pública (`pz_branch: ""`) |
| Admin | `pzadmin`; contraseña provista (≥ 12, sin débiles, espacios ni `=`) o generada (32), en `.admin_password` (0600) |
| Contraseña de ingreso | `Password=` del `.ini`. Provista (`pz_join_password`: ≥ 12, sin débiles ni espacios, distinta de la de admin) o generada (24 alfanuméricos) en `/home/pzserver/pzsvrtool/.join_password` (0600); `pz_join_password_rotate` genera otra. Se escribe antes del primer arranque; sin whitelist (`Open` lo decide la configuración) |
| RCON | Desactivado (`RCONPassword=` vacío en la configuración subida); el puerto 27015 no está abierto |
| Configuración del juego | Contrato: `<nombre>.ini` y `<nombre>_SandboxVars.lua` obligatorios; `_spawnregions.lua`, `_spawnpoints.lua` y `SOURCE` opcionales; nada más. `.ini`: `Mods=`, `WorkshopItems=` y `Map=` exactamente una vez, `Map=` no vacío, `DefaultPort`/`UDPPort` = `pz_udp_ports`, sin `<redacted>`/`CHANGE_ME` fuera de las claves gestionadas |
| Aplicación | Solo si cambia la revisión renderizada (sha256 de los archivos finales): detener el juego en orden → copia en `config-backups/<fecha>/` (conserva `pz_config_backup_keep` = 10) → instalar en `~/Zomboid/Server/` (`.ini` 0600) → registro en `config-applied.json` (revisión, origen, sha de cada archivo). Sin cambios: no toca nada y avisa las claves del `.ini` que difieren |
| Espera de configuración | Con `pz_wait_for_config`, drop-in `wait-config.conf`: `ConditionPathExists=\|config-applied.json` o `\|Saves/Multiplayer/<nombre>` |
| Cambios con el juego corriendo | Si cambian el heap, la configuración o la contraseña: apagado ordenado (`pz_stop_timeout_seconds` = 600) → aplicar → iniciar |
| Swap | `/swapfile`, 2 GB (emergencia; no cuenta como RAM) |
| Backups (pzsvrtool) | activados, límite 10; cuenta regresiva de apagado 5 min |
| Actualización automática | ventana 03:00–06:00 `America/Argentina/Buenos_Aires`; chequeo cada 15 min; aviso de 5 min; apagado máximo 20 min; vuelve a fijar el heap |
| Snapshots automáticos (host) | `tasks/auto_snapshot.yml`: `python3-boto3`, `/usr/local/sbin/pz-auto-snapshot`, `/etc/pz-auto-snapshot.env`, `pz-auto-snapshot.service`/`.timer` (sistema, root). Credenciales del rol de la instancia por IMDSv2. Fuera de EC2 no hace nada |
| Firewall | UFW: TCP 22 (el origen lo filtra el security group), UDP 16261, 16262, 8766 |

## Tests (offline)

`make test`, sin credenciales de AWS ni llamadas a la API:

- `tf-test`: `terraform test` con `mock_provider "aws"`; suites `ami`, `restore`, `ssh`, `config`, `sizing` (tiers), `sessions`, `backups`.
- `bootstrap-test`: el stack del bucket del estado.
- `user-data-check`: renderiza `user_data` sin backend (`tests/render-user-data.sh`); `bash -n`, shellcheck y < 16 KB.
- `provision-test`: `pz-provision` con repos git locales y ansible simulado.
- `snapshot-test`: `pz-auto-snapshot.py` con IMDS falso y boto3 simulado.
- `script-test`: `pz-ctl.sh` y `destroy-and-backup.sh` contra stubs de `aws`/`ssh`/`terraform`.
- `ansible-check` y `ansible-test`: contraseñas, heap y configuración en localhost, sin root.

## Pruebas locales con VM (sin AWS)

`local/vm.sh` (`make local-*`): QEMU/KVM con la imagen cloud oficial de Ubuntu 24.04 (verificada con `SHA256SUMS`) y el `user_data` renderizado, con `repo_commit = HEAD` servido por HTTP desde el host (`LOCAL_GIT_PORT` = 8730). VM de 4 vCPU y 10 GB; reenvío a `127.0.0.1`: SSH 2222, UDP 16261, 16262 y 8766. Pruebas: `check`, `config-test` (`push-config` real), `reboot-test`, `backup-test` y `restore-test`.
