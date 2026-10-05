# Flujos

Secuencias que atraviesan varios archivos. Los componentes se describen en [architecture.md](architecture.md); los comandos, en [operations.md](operations.md).

## 1. Aprovisionamiento (`terraform apply`)

1. Terraform lee el tipo de instancia (RAM, arquitectura, burstable) y la AMI de Ubuntu 24.04 de la región (o `ami_id`). Rechaza un tipo sin RAM para heap + margen o que no sea x86_64, y avisa si es burstable o si falta SSH. Resuelve el tier (instancia, heap, margen y disco; las variables explícitas ganan). Después crea el security group, el rol de IAM de la instancia, la instancia y la Elastic IP.
2. cloud-init ejecuta `user_data` como root: instala Ansible desde su PPA, escribe `/etc/pz-provision.env`, instala `/usr/local/sbin/pz-provision` y lo ejecuta.
3. `pz-provision`:
   1. Valida que `REPO_COMMIT` sea un SHA de 40 caracteres, salvo en modo rama.
   2. Clona `repo_url` (o reutiliza el checkout) y hace fetch de `repo_branch`. Si el commit no está, lo pide por SHA, y si no existe, **aborta**.
   3. Hace `checkout --detach` y verifica `HEAD`.
   4. Corre el playbook como `ubuntu` y, si termina bien, registra la revisión en `/var/lib/pz-provision/revision`.
4. El playbook:
   1. Verifica Debian x86_64, ≥ 2 vCPU y RAM utilizable ≥ heap + margen, y valida las variables (fortaleza de las contraseñas provistas).
   2. Instala paquetes, crea `pzserver`, el swap y linger, e instala pzsvrtool (`.deb` verificado con sha256). Resuelve la contraseña de admin, escribe `pzsvrtool.config` e instala el juego (con el home de `pzserver` como directorio de trabajo, y lo verifica).
   3. **Ajustes del juego** (`tasks/game_settings.yml`):
      1. Instala los helpers y resuelve la contraseña de ingreso.
      2. Calcula qué cambiaría: el heap, la configuración subida (si existe y cambió su revisión renderizada) y `Password=` en el `.ini` (si no hay configuración subida).
      3. Si algo cambia y el juego corre, lo detiene en orden y aplica todo.
      4. Sin configuración nueva, avisa las claves del `.ini` editadas a mano, sin pisarlas.
   4. Instala los drop-ins del servicio. Con `pz_wait_for_config`, el servicio solo arranca si hay configuración aplicada o un mundo existente.
   5. Si corresponde, inicia el servicio y espera al proceso. Si no, informa que espera `push-config`.
   6. Instala el timer de actualización automática y el de snapshots diarios, y configura UFW (SSH, después los puertos del juego, y por último lo activa).
5. `terraform output -raw public_ip` es la Elastic IP que usan los jugadores (UDP 16261).

## 2. Configuración del juego (`pz-ctl.sh push-config <dir>`)

1. En la máquina del operador:
   1. Toma `<nombre>.ini` y `<nombre>_SandboxVars.lua`, que son obligatorios, y los spawns, que son opcionales. Ignora los demás archivos.
   2. Exige un repo git sin cambios en esos archivos (`ALLOW_DIRTY`/`ALLOW_UNVERSIONED` son excepciones) y arma `SOURCE` (`git:<origin>@<sha>`, quién y cuándo).
2. Por SSH:
   1. Sube un tar a `config-staged.new`.
   2. Lo valida con `pz-config-render.py` (el mismo renderizador del playbook).
   3. Solo si es válido, reemplaza `config-staged`. Si no, sale con error sin cambiar nada.
3. `pz-ctl.sh provision` vuelve a correr el playbook en el commit fijado (flujo 1, paso 4.3):
   1. Renderiza la configuración: `Password=` con la contraseña de ingreso y `RCONPassword=` vacío; el resto queda tal cual, en el mismo orden.
   2. Compara la revisión con `config-applied.json`.
   3. Si cambió: detiene el juego en orden, copia la configuración en uso a `config-backups/<fecha>/`, instala los archivos, registra revisión, origen y hashes, y vuelve a iniciar el juego. La primera vez, el juego crea el mundo con este `Map=`.
4. Una re-ejecución sin cambios no toca archivos ni reinicia el juego.

## 3. Sesiones (`pz-ctl.sh stop` / `start`)

1. Las dos órdenes leen `instance_id`, `aws_region` y `public_ip` de los outputs, y consultan el estado de la EC2.
2. `stop`:
   - Si ya está `stopped`, no hace nada. Si está `stopping`, espera.
   - Si está `running`, verifica que haya SSH, ejecuta `systemctl --user stop` del juego (el `ExecStop` de pzsvrtool avisa, hace una cuenta regresiva de 3 min y guarda) y consulta hasta que no quede proceso `ProjectZomboid`.
   - Si no lo confirma, **aborta sin detener la EC2** (salvo `FORCE_STOP=1`).
   - Después ejecuta `stop-instances` y espera `stopped` (`INSTANCE_TIMEOUT`).
3. `start`:
   - Si ya está `running`, no hace nada. Si está `stopping`, espera `stopped` y después inicia.
   - Si está `stopped`, ejecuta `start-instances` y espera `running`. Cualquier otro estado es un error.
   - El juego arranca solo (servicio habilitado + linger) con la misma Elastic IP. `user_data` no se vuelve a ejecutar.

## 4. Backups

- **Automático (en la instancia):**
  - `pz-auto-snapshot.timer` (systemd, `Persistent=true`) corre a `backup_time_utc`, o al prender si a esa hora estaba apagada. Con la EC2 apagada no corre, así que no hay snapshots de días apagada.
  - El script obtiene la instancia y la región por IMDSv2, busca su volumen con `pz-world-volume=<nombre>` y no hace nada si el último automático tiene menos de 12 h.
  - Hace el snapshot con `sync` previo y los tags `pz-world-data-snapshot-auto`, `pz-backup=auto`, `pz-consistency=crash` y `pz-server`.
  - Rota: borra los automáticos completados de este servidor que excedan `backup_retain_count` (4). Los manuales no se tocan, y el rol de IAM tampoco lo permitiría.
- **A pedido (`pz-ctl.sh backup`):**
  - Con la EC2 corriendo: detiene el juego y lo confirma, hace el snapshot (`pz-world-data-snapshot`, `pz-consistency=application`), espera `completed` y vuelve a iniciar el juego. El reinicio corre aunque falle el snapshot.
  - Con la EC2 detenida: snapshot directo.
- **Del juego (pzsvrtool):** backups locales en el mismo disco al apagar y antes de actualizar. No protegen ante la pérdida del volumen.

## 5. Actualización automática del juego (`pz-auto-update.timer`)

El timer se dispara 10 minutos después del arranque y luego cada `pz_update_check_minutes`. El script:

1. Toma un `flock`. Si la hora está fuera de la ventana, sale.
2. Compara el `buildid` instalado con el remoto de la rama de Steam.
3. Si difieren, y no hay una cuenta regresiva ni un arranque en curso:
   1. Avisa, ejecuta `pzsvrtool quit --time N` y espera al proceso y al servicio.
   2. Ejecuta `pzsvrtool backupnow` y reinstala.
   3. Verifica la build, **vuelve a fijar el heap** (la reinstalación restaura `ProjectZomboid64.json`) y reinicia.
4. Un trap de ERR reinicia el servidor si algo falla después del apagado.

## 6. Actualizar el código (`repo_commit` nuevo)

1. El operador cambia `repo_commit` y ejecuta `terraform apply`. La instancia no cambia (`ignore_changes = [user_data]`); solo cambia el output `repo_commit`.
2. `pz-ctl.sh provision` ejecuta por SSH `sudo pz-provision --commit <sha>`: verifica el commit, corre el playbook y, si termina bien, lo registra en `/etc/pz-provision.env`.
3. Una instancia nueva o restaurada usa directamente el `repo_commit` del `user_data` actual.

## 7. Baja (`script/destroy-and-backup.sh`)

1. Lee `aws_region`, `pz_server_name`, `public_ip`, `root_volume_id` e `instance_id` de los outputs (`AWS_REGION`, `PZ_SERVER_NAME` e `INSTANCE_ID` los reemplazan). Si falta alguno, sale antes de tocar nada. Sin SSH configurado (y sin `FORCE_SNAPSHOT`), también sale.
2. Si la EC2 está detenida, el disco ya es consistente. Si no, detiene el juego y lo confirma; si no puede, **aborta** (`FORCE_SNAPSHOT=1` sigue con `pz-consistency=unconfirmed`).
3. Hace el snapshot del disco raíz con los tags de restauración y espera `completed`. Si falla, no destruye nada.
4. `terraform destroy`: elimina la instancia, el disco, la Elastic IP, el security group y el rol de IAM. Quedan los snapshots.

## 8. Restauración (`terraform apply` después de una baja)

1. Origen: `restore_snapshot_id` o, si no se define, el snapshot propio más reciente con `Name=pz-world-data-snapshot` (los automáticos se eligen a mano). Con `restore_from_snapshot = false`, no se restaura nada.
2. Una precondición exige que el snapshot esté `completed`. Terraform registra la imagen `pz-restore-<snap>` y la instancia arranca desde ella, con una Elastic IP nueva.
3. cloud-init vuelve a ejecutar `user_data` (instancia nueva). `pz-provision` reutiliza el checkout y lo lleva al `repo_commit` vigente. El playbook es idempotente: no reinstala el juego, conserva las contraseñas y la configuración aplicada (misma revisión renderizada), y el juego arranca porque el mundo existe.

## 9. Prueba local con VM (`make local-test`)

1. `up`:
   1. Descarga y verifica la imagen de Ubuntu.
   2. Sirve un espejo del repo por HTTP en el host y renderiza el `user_data` con `repo_commit = HEAD` y `repo_url = http://10.0.2.2:8730/repo.git`.
   3. Arma un seed NoCloud (clave SSH + `user_data`) y arranca QEMU/KVM. Corre el flujo 1.
   4. `check` verifica la revisión, las contraseñas, el heap, UFW, y que el juego espera la configuración.
2. `config-test`:
   1. Corre `pz-ctl.sh push-config` real con `tests/ansible/fixtures` (SSH real; `aws`/`terraform` simulados).
   2. Verifica que el juego arranca con esa configuración y que completó el `.ini` mínimo.
   3. Verifica que una re-ejecución sin cambios no lo reinicia.
3. `reboot-test`: reinicia y verifica que el juego vuelve solo.
4. `backup-test`: corre `destroy-and-backup.sh` con SSH real y verifica el apagado ordenado antes del snapshot simulado.
5. `restore-test`: copia el disco y arranca con otro `instance-id`. Verifica la revisión, los datos, la partida, las contraseñas y la configuración aplicada.
