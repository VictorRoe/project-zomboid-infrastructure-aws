# Flujos

Secuencias que atraviesan varios archivos. Los componentes se describen en [architecture.md](architecture.md).

## 1. Aprovisionamiento (`terraform apply`)

1. Terraform resuelve la AMI de Ubuntu 24.04 para `aws_region` (o usa `ami_id`) y crea `pz-server-sg` y `PZ-Server-Instance` (raíz gp3 de 30 GB). En applies posteriores los cambios de imagen se ignoran, así que la instancia nunca se reemplaza implícitamente.
2. cloud-init ejecuta `user_data` como root: instala Ansible desde su PPA, clona el repo de GitHub en `/home/ubuntu/repo` y corre el playbook como `ubuntu` contra `localhost` con `-e pz_server_name=<var>`.
3. El playbook:
   1. En las pre-tasks verifica Debian x86_64, al menos 2 vCPU y unos 7,5 GB de RAM, y después valida las variables (`tasks/validate.yml`). Una contraseña de admin provista tiene que cumplir las reglas de fortaleza.
   2. Instala paquetes, crea `pzserver` y crea y activa el archivo de swap.
   3. Activa linger, le da `TimeoutStopSec=20m` al gestor de usuario e instala pzsvrtool (`.deb` con versión fija).
   4. Resuelve la contraseña de admin (`tasks/admin_password.yml`): si se proveyó una, la guarda; si no, reutiliza la guardada o genera una aleatoria y la guarda en `.admin_password` (0600). Después escribe `pzsvrtool.config` e instala el juego con `pzsvrtool install`. Si todavía falta `start-server.sh`, recurre directamente a SteamCMD.
   5. Habilita e inicia `pzsvrtool@<nombre>.service` y espera al proceso `ProjectZomboid`.
   6. Instala el script, el servicio y el timer de actualización automática.
   7. Configura UFW: primero SSH, después los puertos UDP del juego, y por último activa el firewall.
   8. Verifica que el servicio esté habilitado y que linger esté activo.
4. `terraform output public_ip` da la dirección que usan los jugadores (UDP 16261).

## 2. Actualización automática del juego (`pz-auto-update.timer`)

El timer se dispara 10 minutos después del arranque y luego cada `pz_update_check_minutes`. El script:

1. Toma un `flock`. Si la hora está fuera de la ventana de actualización, sale sin hacer nada (se admiten ventanas que cruzan la medianoche).
2. Compara el `buildid` de Steam instalado (app manifest) con la build remota de la rama (`app_info_print`).
3. Si difieren, y no hay una cuenta regresiva ni un arranque en curso:
   1. Avisa a los jugadores y ejecuta `pzsvrtool quit --time N`.
   2. Espera a que se detengan el proceso y el servicio.
   3. Ejecuta `pzsvrtool backupnow` y reinstala.
   4. Verifica la build nueva y vuelve a iniciar el servidor.
4. Un trap de ERR reinicia el servidor si la actualización falla después del apagado.

## 3. Backup y baja (`script/destroy-and-backup.sh`)

Se puede ejecutar desde cualquier directorio.

1. Lee `backup_bucket_name`, `aws_region`, `pz_server_name`, `public_ip` y `root_volume_id` con `terraform -chdir=<repo>/terraform output`. `S3_BUCKET`, `AWS_REGION` y `PZ_SERVER_NAME` reemplazan a los tres primeros. Si algún valor queda vacío, sale antes de tocar nada.
2. Detiene el servidor por SSH (`SSH_KEY` opcional):
   1. Ejecuta `systemctl --user stop pzsvrtool@<pz_server_name>.service` como `pzserver`, con el entorno del bus de usuario armado del lado del servidor.
   2. Consulta `pgrep ProjectZomboid` hasta que el proceso desaparezca (`STOP_TIMEOUT`, 600 s por defecto).
   3. Si falla SSH, falla la detención o se vence el tiempo, el script **aborta con exit 1**, antes de cualquier snapshot o destroy. `FORCE_SNAPSHOT=1` sigue de todos modos, con una advertencia.
3. Crea un snapshot EBS con el tag `pz-world-data-snapshot` y espera a que se complete.
4. Archiva `s3://<bucket>/latest/` en `archive/<fecha>/` y sube el ID del snapshot (desde un archivo temporal) a `latest/snapshot_meta.txt`.
5. Ejecuta `terraform destroy -auto-approve`, que elimina la instancia y su disco. El snapshot queda.

## 4. Restauración (`terraform apply` después de una baja)

1. Terraform elige el origen: `restore_snapshot_id` si está definido; si no, el snapshot propio más reciente con el tag `pz-world-data-snapshot`. Con `restore_from_snapshot = false` no hay restauración.
2. Lee ese snapshot. Una precondición hace fallar la ejecución si el snapshot no está `completed`.
3. Registra la imagen `pz-restore-<snap>` (`/dev/sda1`, hvm, ENA, `uefi-preferred`, gp3, tamaño `max(30, snapshot)`).
4. La instancia arranca desde esa imagen, así que las partidas guardadas, la configuración de pzsvrtool y la instalación del juego vuelven tal como estaban.
5. cloud-init vuelve a ejecutar `user_data` (ID de instancia nuevo). Como el repo ya existe, ejecuta `git fetch` y `reset --hard origin/main` como `ubuntu` en lugar de clonar. Después el playbook se vuelve a correr de forma idempotente: el juego no se reinstala porque `start-server.sh` existe.
6. El output `restored_from_snapshot_id` muestra el snapshot usado (vacío significa instalación nueva).

La restauración solo ocurre cuando la instancia se **crea**. En un servidor que está corriendo, un snapshot más nuevo no provoca un reemplazo, porque los cambios de `ami` se ignoran. `terraform destroy` desregistra la imagen de restauración; los snapshots quedan.
