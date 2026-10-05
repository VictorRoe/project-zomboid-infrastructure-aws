# Registro de decisiones

Las entradas nuevas van al final. Cada entrada registra qué se decidió, por qué y sus consecuencias. El estado actual está en [spec.md](spec.md).

## Antes del 2026-10-04: diseño existente (deducido del código)

**D1. Una sola instancia EC2 con un único disco raíz contiene todo.** Es simple y barato para un grupo chico. Consecuencia: un backup implica hacer snapshot de todo el disco raíz, y los datos del mundo no se pueden separar del SO.

**D2. La instancia se configura sola (cloud-init clona el repo y Ansible corre localmente).** No hace falta acceso SSH ni un controlador de Ansible. Consecuencia: el playbook sale de `main` en GitHub, así que los cambios sin pushear nunca se despliegan.

**D3. El juego lo gestiona pzsvrtool (versión fija 1.7.3) como servicio systemd de usuario con linger.** pzsvrtool aporta sesiones tmux, cuentas regresivas, backups y el flujo de instalación. Consecuencias: toda llamada a `systemctl --user` necesita el entorno del bus de usuario, y el `TimeoutStopSec=20m` a nivel host le da tiempo al juego para guardar al apagarse.

**D4. Las actualizaciones del juego solo ocurren dentro de una ventana horaria, con un backup previo y un reinicio de recuperación.** No se echa a los jugadores en horario pico, y una actualización fallida no deja el servidor caído. Consecuencia: una actualización puede demorarse hasta un día.

**D5. Destruir cuando no se usa y conservar un snapshot.** Ahorra costo de EC2 entre sesiones de juego. Consecuencia: hace falta restaurar para tener continuidad, pero todavía no está conectado ([#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)). *Revisión 2026-10-04: stop/start lograría el mismo ahorro con menos complejidad; ver D20 y [#9](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/9). Reemplazada por D29 (stop/start).*

**D6. El heap de Java queda en el valor por defecto del juego; el margen extra sale del swap y de la RAM de la VM.** Mantiene la configuración cerca de upstream. Consecuencia: la instancia necesita al menos unos 7,5 GB de RAM (se verifica). *Revisión 2026-10-04: FalopaServer usa `-Xmx8g`; ver D20 y [#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7). Reemplazada por D33 (heap gestionado).*

## 2026-10-04: documentación y plan de arreglos

**D7. La documentación vive en `docs/`; en la raíz solo quedan README, CLAUDE.md y CHANGELOG.md.** Cada cambio actualiza [spec.md](spec.md), agrega una entrada acá y una entrada en el [CHANGELOG](../CHANGELOG.md).

**D8. Los issues #1–#5 se arreglan como cambios de OpenSpec en ramas apiladas**, en este orden: AMI (#4) → restauración (#1) → SSH (#5) → configuración del backup (#2) → contraseña de admin (#3). Los arreglos tocan los mismos archivos, así que apilarlos evita conflictos de merge. *Reemplazada por D19: se entregó como un único PR y las ramas intermedias se borraron.*

**D9. Todos los tests corren offline contra mocks.** Terraform usa `terraform test` con `mock_provider`, Ansible corre en localhost y el script corre con `aws`/`ssh`/`terraform` reemplazados por stubs. Motivo: sin gasto en AWS ni credenciales durante el desarrollo. Consecuencia: el comportamiento real en AWS (filtros de AMI, arranque de una imagen restaurada) todavía requiere una verificación manual en el primer despliegue real.

**D10. La AMI se resuelve por región y se ignora la deriva de imagen ([#4](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/4)).** Un `data "aws_ami"` busca la última imagen Ubuntu 24.04 amd64 gp3 de Canonical (`ami_id` la reemplaza). `availability_zone` es `null` por defecto, y una AZ explícita tiene que pertenecer a `aws_region`. Por qué: la AMI y la AZ hardcodeadas solo funcionaban en us-east-1. Consecuencias:
- `lifecycle { ignore_changes = [ami] }` evita que una imagen más nueva reemplace la instancia y borre el disco del mundo. Las reconstrucciones son deliberadas (`-replace`).
- Una instancia existente conserva su imagen original.
- `.terraform.lock.hcl` ahora se commitea.

**D11. Arnés de tests offline.** `make test` corre `terraform test` con `mock_provider "aws"`, `override_data` y el chequeo de sintaxis de Ansible. Por qué: sin gasto ni credenciales de AWS (D9). Consecuencia: el filtro real de AMI recién se ejercita en el primer apply real.

**D12. Restaurar registrando una imagen desde el snapshot del disco raíz ([#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)).** Al crear, se registra `aws_ami.restored` desde el último snapshot con tag (o `restore_snapshot_id`) y la instancia arranca desde ella. `restore_from_snapshot = false` lo desactiva. Por qué: el backup es un snapshot de todo el disco raíz, y un volumen raíz solo puede salir de una imagen. Un volumen de datos separado requeriría una migración. Consecuencias:
- La restauración solo aplica al crear (el `ignore_changes` de D10), así que un servidor en marcha nunca vuelve atrás.
- Si aparece un snapshot más nuevo mientras el servidor corre, el siguiente apply vuelve a registrar la imagen pero no toca la instancia.
- Se rechazan los snapshots que no están `completed`.
- El destroy desregistra la imagen pero conserva los snapshots.
- El modo de arranque se fijó en `uefi-preferred` sin probarlo en AWS real. Verificarlo en la primera restauración real.

**D13. El script de arranque es idempotente y vive en una plantilla.** `user_data` pasó a `terraform/templates/user_data.sh.tftpl`. Si el checkout existe, ejecuta `git fetch`/`reset` como `ubuntu`. Por qué: cloud-init vuelve a ejecutar `user_data` en un disco restaurado, y git ejecutado como root rechaza un repo cuyo dueño es `ubuntu`. Consecuencia: los cambios locales en el checkout del servidor se descartan al arrancar. `make user-data-check` valida el script renderizado.

**D14. Key pair SSH opcional, y nunca un snapshot de un servidor en marcha ([#5](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/5)).** Se puede definir `ssh_public_key` (crea el key pair `pz-server`) o `ssh_key_name`, nunca ambos. `ssh_allowed_cidrs` limita el puerto 22. El script de backup detiene el servicio con el entorno del bus de usuario, espera a que el proceso termine y, si no lo logra, aborta antes del snapshot. `FORCE_SNAPSHOT=1` es la vía de escape. Por qué: la instancia no tenía clave, el fallo de SSH enmascarado hacía snapshot de un servidor en marcha, y `sudo -iu … systemctl --user` igual no llega al bus de usuario. Consecuencias:
- **Cambio de comportamiento:** ahora los backups fallan de forma visible en lugar de continuar.
- Las host keys no se fijan, porque cloud-init las regenera en cada instancia.
- SSM Session Manager queda como posible mejora; necesita un rol de IAM.

**D15. Los tests del script usan stubs en el PATH en lugar de bats.** `tests/script/bin/{aws,ssh,terraform}` registran sus llamadas y responden según variables `STUB_*`. Por qué: sin dependencias extra, y nada toca AWS. Consecuencia: los stubs tienen que acompañar cualquier llamada nueva a una CLI que haga el script.

**D16. Los outputs de Terraform son la única fuente de configuración del backup ([#2](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/2)).** El script lee `backup_bucket_name`, `aws_region`, `pz_server_name`, `public_ip` y `root_volume_id` con `terraform -chdir`, admite reemplazos por variables de entorno y falla temprano si falta un valor. `pz_server_name` también llega al playbook vía `user_data`. Por qué: el bucket, la región y el nombre del servicio diferían entre Terraform y el script, el script solo funcionaba desde `terraform/`, y una búsqueda por tag podía elegir un volumen viejo. Consecuencias:
- Quien ya lo use tiene que definir `s3_bucket_name` con el bucket que usa de verdad.
- Un `AWS_REGION` exportado globalmente reemplaza la región del stack en el script.
- El bucket sigue sin gestionarse, porque el propio `terraform destroy` del script lo borraría.

**D17. Sin contraseña de admin por defecto; se genera una en el host y se conserva ([#3](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/3)).** Si `pz_admin_password` está vacía, que es el nuevo valor por defecto, se genera una contraseña alfanumérica aleatoria de 32 caracteres y se guarda en `~pzserver/pzsvrtool/.admin_password` (0600). Se reutiliza en ejecuciones posteriores y sobrevive a una restauración. Una contraseña provista tiene que tener al menos 12 caracteres, no estar en la lista de débiles y no contener espacios ni `=`. Por qué: las ejecuciones desatendidas dejaban a todo servidor público con la contraseña `test`. Pasar una contraseña por Terraform o `user_data` la filtraría al estado y a los metadatos de la instancia. Consecuencias:
- Los operadores leen la contraseña por SSH.
- Cambiar la contraseña después de que PZ creó la cuenta de admin puede no tener efecto (la cuenta vive en la base de datos de PZ).
- El assert de validación usa `quiet` en lugar de `no_log`, así que su mensaje de error es visible.

**D18. Los valores por defecto del playbook pasaron a `playbook/vars/main.yml`, y la validación y la lógica de contraseña, a `playbook/tasks/`.** Por qué: el playbook de tests (`tests/ansible/`) carga los mismos valores y tareas sin root ni host real. Consecuencia: `vars_files` tiene la misma precedencia que los `vars` en línea anteriores, y `--extra-vars` sigue ganando.

**D19. OpenSpec vive en el repo, y los arreglos se entregan en un único PR.** `openspec/` se movió desde el directorio de trabajo padre al repo: specs principales en `openspec/specs/`, los seis cambios archivados en `openspec/changes/archive/2026-10-04-*`. Las ramas apiladas (D8) se entregaron como un único PR, `release/fix-issues-1-5`, y las intermedias se borraron. Por qué: el mantenedor pidió mergear juntos decisiones, cambios, specs y changelog, y las specs deben versionarse junto al código que describen. Consecuencia: cada cambio futuro agrega sus artefactos de OpenSpec al PR.

**D20. Revisión del plan como servidor de Zomboid: hallazgos registrados como issues.** La revisión de consistencia no encontró contradicciones entre código, docs y specs, pero sí problemas de fondo del plan. Quedaron registrados así:
- [#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7): la `t3.large` (8 GiB, CPU burstable) no alcanza para FalopaServer (`-Xmx8g`, 257 mods).
- [#8](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/8): la configuración del servidor no está gestionada.
- [#9](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/9): stop/start con Elastic IP en lugar de destroy/restore.
- [#10](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/10): snapshots automáticos con retención (DLM).
- [#13](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/13): sin contraseña de ingreso ni whitelist.
- [#11](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/11): región `sa-east-1` para jugadores en Argentina.
- [#12](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/12): endurecimiento (backend remoto, bucket redundante, versión fija del repo, SSH).

Por qué: que no se pierdan. Consecuencia: el orden sugerido es #7 → #8 → #9/#10 → #13. Cada uno se trabaja como un cambio de OpenSpec propio.

**D21. Toda la documentación y los artefactos de OpenSpec están en castellano.** Los marcadores estructurales de OpenSpec quedan en inglés (`## Purpose`, `### Requirement:`, `#### Scenario:`, `WHEN`/`THEN`) y los requisitos usan "DEBE (SHALL)", porque el validador exige esas palabras clave. Los identificadores, comandos y rutas no se traducen. Por qué: lo pidió el mantenedor. Consecuencia: `openspec/config.yaml` indica escribir los artefactos nuevos en castellano.

**D22. Los comandos de operación usan `XDG_RUNTIME_DIR` explícito para `systemctl --user`/`journalctl --user`.** `docs/operations.md` y el mensaje final del playbook recomendaban `sudo -iu pzserver systemctl --user …`, que puede no llegar al bus de usuario (el mismo problema que D14 corrigió en el script). Ahora usan `sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/<uid> …`, igual que el playbook y el script. Por qué: consistencia entre la documentación y el código, encontrada al revisar cómo se inicia el servidor. Consecuencias:
- Los comandos de pzsvrtool (`console`, `message`, `quit`, `backupnow`) siguen con `sudo -iu`, porque no usan systemd.
- No se verificó en una instancia real; la forma explícita funciona en ambos casos.

## 2026-10-05: prueba en VM local

**D23. Pruebas de integración en una VM local que imita la EC2 ([#14](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/14)).** `local/vm.sh` arranca con QEMU/KVM la imagen cloud oficial de Ubuntu 24.04 y le pasa por cloud-init NoCloud el `user_data` renderizado por Terraform, sin cambios. Se agregaron `repo_url`/`repo_branch` (para clonar una rama sin mergear) y `SSH_PORT` en el script de backup. Por qué: los mocks no ejecutaban nunca el arranque real, y probar en AWS cuesta y tarda. Se eligió QEMU directo en lugar de libvirt porque corre como usuario, sin daemon, y con `hostfwd` alcanza para SSH y los puertos del juego. Consecuencias:
- Resultados (corrida limpia de `make local-test` del 2026-10-05, desde cero): 27 chequeos pasan y 0 fallan en 10 min 19 s (`check` 11, `reboot-test` 4, `backup-test` 5, `restore-test` 7). Se puede jugar contra `127.0.0.1:16261`.
- Confirmado en la práctica: el servidor arranca solo tras un reinicio; `systemctl --user stop` hace un apagado ordenado (cuenta regresiva de 3 min de pzsvrtool, ~3,5 min en total), así que el `STOP_TIMEOUT` de 600 s alcanza; un disco restaurado vuelve a ejecutar `user_data`, actualiza el checkout y conserva datos, partida y contraseña; la cuenta `pzadmin` se crea con la contraseña generada.
- No cubre la búsqueda real de la AMI, el arranque en hardware de AWS (Nitro/ENA/`uefi-preferred`), los snapshots EBS ni el security group.
- Requiere KVM y descarga varios GB; no corre en CI.

**D24. La instalación del juego corre con el home de `pzserver` como directorio de trabajo, y se verifica ([#15](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/15)).** La prueba en VM mostró que pzsvrtool descarga SteamCMD en el directorio actual; con `runuser` era `/home/ubuntu/repo/playbook`, sin permiso para `pzserver`. La descarga fallaba en silencio, pzsvrtool igual imprimía "Installation Completed" y el respaldo con SteamCMD directo fallaba: **el aprovisionamiento nunca podía terminar**, tampoco en AWS. Ahora ambos pasos usan `chdir: "{{ pz_home }}"` y un `assert` exige que exista `start-server.sh`. Consecuencia: si la instalación falla, el playbook lo dice explícitamente en lugar de seguir.

## 2026-10-05: issues #7–#19 (revisión del plan)

**D25. La instancia ejecuta un commit fijo y verificado ([#18](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/18)).** `repo_commit` (SHA de 40 caracteres) es obligatorio. `user_data` instala `pz-provision` (`terraform/templates/pz-provision.sh`), que obtiene ese commit (por la rama o por SHA), verifica `HEAD` antes de Ansible y aborta si no existe, sin caer a `main`. Seguir una rama queda como modo de prueba explícito (`repo_follow_branch`). No se admiten tags. `aws_instance` ahora también ignora los cambios de `user_data`. Por qué: un disco restaurado o una instancia nueva podían ejecutar código distinto del revisado, y el provider de AWS detiene y reinicia la instancia cuando cambia `user_data` (sin volver a ejecutarlo, porque cloud-init corre una vez por instancia). Consecuencias:
- No hay un valor por defecto: el operador fija el SHA de `main` ya mergeado y probado, en lugar de un SHA inventado.
- Para actualizar un host en marcha se hace a propósito, con `pz-ctl.sh provision`. Una instancia nueva o restaurada usa el `repo_commit` vigente.
- Siguen sin fijarse los paquetes apt, Ansible del PPA, la build del juego y los mods (spec.md).
- **Requisito:** el repo tiene que ser público. Se volvió privado después del PR #6, y un despliegue nuevo no podía clonarlo.

**D26. SSH cerrado por defecto y solo desde redes administrativas ([#19](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/19)).** `ssh_allowed_cidrs` es `[]` por defecto (sin regla del puerto 22). Se validan CIDRs IPv4 con la dirección de red, y `/0` se rechaza salvo con `ssh_allow_any_source = true`. Un `check` avisa en el plan y los scripts fallan temprano (output `ssh_enabled`) si faltan la clave o las redes. Por qué: el key pair no restringe el origen, y el 22 quedaba abierto a Internet. Consecuencias:
- Quien usaba el valor por defecto pierde SSH hasta declarar su IP.
- El origen se filtra **solo** en el security group. UFW mantiene `22/tcp` abierto, igual que los puertos del juego: el SG se actualiza con un `apply` en el momento, mientras que UFW solo cambia al reaprovisionar. Duplicar la lista en UFW dejaría afuera al operador cuando cambie su IP.
- La verificación de la host key sigue sin hacerse (cloud-init la regenera en cada instancia); queda para revisar más adelante.

**D27. Estado remoto en S3 con bloqueo nativo ([#16](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/16)).** `backend "s3"` con `use_lockfile` (Terraform ≥ 1.11, sin DynamoDB). El bucket se crea con un stack aparte (`bootstrap/state-backend`): versionado, SSE-S3, sin acceso público, solo TLS, versiones anteriores 90 días y `prevent_destroy`. Por qué: el estado local se podía perder o pisar entre ejecuciones concurrentes. Un ciclo de vida separado evita que la baja del servidor borre el estado. Consecuencias:
- Migración: `terraform init -backend-config=backend.hcl -migrate-state`, con copia previa de `terraform.tfstate`.
- Los tests usan `init -backend=false`, y `terraform console` necesita una copia sin `backend.tf` (`tests/render-user-data.sh`).
- La migración real y el bloqueo concurrente quedan sin probar hasta tener AWS.
- Distinto del bucket de metadatos (D28).

**D28. Se retira el bucket S3 de metadatos de backup ([#17](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/17)).** Inventario: el único escritor era `destroy-and-backup.sh` (`latest/snapshot_meta.txt` y `archive/<fecha>/`), y no había ningún lector. La restauración descubre los snapshots por tag. Los metadatos pasan a tags del snapshot (`pz-server`, `pz-backup`, `pz-consistency`). Se eliminan `s3_bucket_name` y el output `backup_bucket_name`. Por qué: era una dependencia externa duplicada que hacía fallar el backup si el bucket no existía. Consecuencias:
- El bucket existente y su historia **no se tocan**; quien la necesite la conserva o la exporta a mano.
- Un `s3_bucket_name` que quede en un `terraform.tfvars` solo genera una advertencia de variable no declarada.

**D29. Sesiones con stop/start y Elastic IP ([#9](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/9)).** `aws_eip` asociada a la instancia, y `script/pz-ctl.sh start|stop|status` lee la instancia y la región de los outputs. `stop` confirma por SSH el apagado ordenado del juego antes de `stop-instances` (sin forzar implícitamente; `FORCE_STOP=1` es la excepción). Los estados se esperan con timeout, y los errores de AWS se propagan. `destroy-and-backup.sh` queda para la baja definitiva y funciona con la EC2 ya detenida, sin SSH. Por qué: destruir y restaurar en cada sesión agregaba pasos y riesgo, y la IP cambiaba. Consecuencias:
- Con la EC2 detenida se siguen cobrando disco, Elastic IP (0,005 USD/h) y snapshots (costs.md).
- Al migrar, la IP cambia una única vez (la nueva Elastic IP); la instancia no se reemplaza.
- `public_ip` es ahora la Elastic IP.

**D30. Backups: DLM diario (crash-consistent) más backups consistentes a pedido ([#10](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/10)).** *Reemplazada en parte por D38: los automáticos los hace la instancia, no DLM.* La política DLM toma un snapshot diario a las 09:00 UTC (06:00 en Argentina, después de la ventana de actualización) y conserva 7, seleccionando el volumen por `pz-world-volume=<nombre>`. El rol de IAM solo puede borrar snapshots `pz-backup=auto`. Los snapshots automáticos se etiquetan `pz-consistency=crash` y `Name=pz-world-data-snapshot-auto`, así que la restauración automática no los usa. `pz-ctl.sh backup` hace uno consistente (detiene el juego, hace el snapshot y lo vuelve a iniciar). Por qué: un snapshot con el juego escribiendo no garantiza consistencia, y no hay forma barata de pausarlo justo cuando DLM dispara (DLM arranca dentro de la hora indicada; los pre-scripts necesitarían SSM e IAM en el host). Así no se declara una consistencia que no está garantizada. Consecuencias:
- RPO de hasta 24 h con los automáticos. RTO objetivo de 1 hora, sin medir todavía en AWS.
- Si la EC2 estaba detenida cuando corrió DLM, el snapshot es consistente en la práctica, pero igual se etiqueta `crash`.
- No hay copia a otra región ni a otra cuenta (decisión explícita; DLM lo permite si se necesita).
- Los permisos mínimos y la ejecución real de la política no se probaron en AWS. Si DLM fallara por permisos, la alternativa es la política administrada `AWSDataLifecycleManagerServiceRole`.

**D31. La configuración del juego la provee el operador, con un contrato de archivos ([#8](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/8)).** `pz-ctl.sh push-config <dir>` sube `<nombre>.ini`, `_SandboxVars.lua` y, opcionalmente, los spawns, más el commit de origen. Lo hace desde un directorio en git sin cambios pendientes. Ansible valida (contrato, claves de lista únicas, puertos, placeholders), renderiza y solo aplica si cambió el resultado: detiene el juego en orden, guarda una copia y registra revisión y origen. El orden de `Mods=`/`Map=` no se toca. Sin cambios nuevos, los cambios manuales **no se pisan** y se avisan clave por clave; la próxima subida los guarda en la copia. Con `pz_wait_for_config` (por defecto en Terraform), el juego no arranca hasta que haya configuración o un mundo. Por qué: lo eligió el mantenedor. El repo de configuración de un servidor concreto es privado y es otro proyecto. Si el juego arranca sin configuración, crea el mundo con otro `Map=`, y eso no se corrige después. Consecuencias:
- En una instalación limpia, el juego arranca recién después de `push-config`.
- Un disco existente o restaurado arranca igual, porque el mundo ya existe.
- Validado con un servidor real de unos 250 mods: el `.ini` renderizado solo difiere en `Password`/`RCONPassword`.

**D32. Contraseña de ingreso gestionada, distinta de la de admin; sin whitelist ([#13](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/13)).** Como la de admin (D17): provista o generada (24 alfanuméricos), en `.join_password` (0600) y reutilizada al reaprovisionar o restaurar. Se escribe en `Password=` antes del primer arranque, incluso sin configuración subida (un `.ini` mínimo que PZ completa). `rotate-join-password` genera una nueva y reinicia el juego. RCON queda desactivado. Por qué: conocer la IP no es autorización. La whitelist (`Open=false`) obliga a crear cuentas a mano, y por ahora no se probó con la build actual. Consecuencias:
- La contraseña se reparte por un canal privado (`pz-ctl.sh join-password`).
- Al rotarla, los jugadores conectados quedan afuera con el reinicio y vuelven a entrar con la nueva.
- El rechazo de una contraseña incorrecta con un cliente real queda sin probar.

**D33. Valores por defecto genéricos, heap gestionado y RAM verificada ([#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7)).** `m7i.large` (8 GiB, no burstable) con `pz_java_xmx_mb = 4096` y `pz_host_overhead_mb = 3072`. Terraform rechaza un tipo sin la RAM nominal necesaria o que no sea x86_64, y avisa si es burstable. Ansible exige esa RAM utilizable sin contar la swap, fija `-Xmx` en `ProjectZomboid64.json` y lo vuelve a fijar después de cada actualización del juego. Por qué: el mantenedor pidió que este stack no tome como objetivo a un servidor concreto (FalopaServer es otro proyecto). `t3.large` era burstable, y el heap dependía del JSON del juego, que una reinstalación restaura. Consecuencias:
- Un servidor con muchos mods sube juntos el heap y la instancia (ejemplo en costs.md).
- El tamaño definitivo requiere una prueba de carga real (pendiente, con `pz-ctl.sh metrics`).
- `m7i.large` cuesta 0,0176 USD/h más que `t3.large`.
- La rama pública de Steam es la build 42 vigente; no se cambia de build implícitamente.

**D34. Se mantiene `us-east-1` ([#11](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/11)).** Medido desde Argentina (TCP connect, 15 muestras, 2026-10-05): mediana de 166 ms a us-east-1 y 34 ms a sa-east-1. Pero sa-east-1 cuesta ~60 % más en EC2 y ~90 % más en disco (~18,70 contra ~12,70 USD/mes con 60 h). Por qué: no se cambia el valor por defecto por una sola medición; la región es una variable. Consecuencias:
- Procedimiento de migración entre regiones (copiar el snapshot y restaurar con otro estado) documentado en costs.md, con rollback y limpieza.
- La disponibilidad del tipo de instancia y de la AMI en la región destino se verifica en el primer plan real.

**D35. La VM local clona desde un servidor git propio y prueba la configuración real.** `local/vm.sh` sirve un espejo del repo por HTTP en `127.0.0.1:8730` (dentro de QEMU, `10.0.2.2`) y fija `repo_commit = HEAD`. `repo_url` admite `http://10.0.2.2:<puerto>/…`, inalcanzable desde una EC2. La prueba nueva `config-test` corre `push-config` real con `tests/ansible/fixtures`. Por qué: el repo es privado (la VM no podía clonar), y así no hace falta pushear para probar. Consecuencia: hay que commitear antes de `make local-up`; `LOCAL_REPO_SOURCE=github` usa GitHub.
- Resultado (corrida limpia de `make local-test`, 2026-10-05, con tiers y snapshots de D38/D39): 46 chequeos pasan y 0 fallan en 11 min 19 s (`check` 17, `config-test` 13, `reboot-test` 4, `backup-test` 5, `restore-test` 7). La primera corrida encontró el problema de D36.

**D36. pzsvrtool se verifica con sha256 y no se vuelve a descargar.** La prueba en VM mostró que `get_url` con `force: false` volvía a consultar GitHub en cada reaprovisionamiento, y un timeout hacía fallar `provision` sin ningún cambio real. Con `checksum`, un `.deb` presente y correcto no se pide; además se reintenta 5 veces. Por qué: reaprovisionar no debe depender de GitHub, y el artefacto queda fijado. Consecuencia: actualizar `pzsvrtool_deb_sha256` junto con `pzsvrtool_version`.

**D37. Los issues #7–#19 se entregan en un único PR, y la validación en AWS queda para una cuenta de prueba.** Lo pidió el mantenedor, igual que en D19. Todo se probó offline y en la VM. Lo que necesita AWS (búsqueda de AMI, EIP, DLM, backend S3 y bloqueo, stop/start real, carga, ingreso con un cliente real) queda pendiente. Se probará con la mínima cantidad de recursos, la instancia más chica que el plan admita y `terraform destroy`, más el borrado de snapshots, al terminar. Además, el README resume costos y arquitectura, y operations.md es el runbook del día a día (pedido del mantenedor).

**D38. Los snapshots automáticos los hace la propia instancia, solo los días que está prendida, y se conservan 4.** Reemplaza la parte DLM de D30. Un timer de systemd en la instancia (`pz-auto-snapshot.timer`, `Persistent=true`) corre a `backup_time_utc`, o al prender si estaba apagada a esa hora, y no repite si hay uno de menos de 12 h. Hace el snapshot de su disco y rota los automáticos de su servidor, conservando `backup_retain_count` = 4. Usa un rol de IAM de la instancia: `CreateSnapshot` solo del volumen con `pz-world-volume=<nombre>`, `CreateTags` solo al crear, `DeleteSnapshot` solo con `pz-backup=auto` y `pz-server=<nombre>`. Por qué: el mantenedor pidió snapshots *sí y solo sí* el servidor está prendido, y 4 en lugar de 7. DLM no puede condicionar por el estado de la instancia, y con la EC2 apagada sacaría copias idénticas que, al rotar, desplazarían a las útiles. Consecuencias:
- La instancia tiene credenciales de AWS (temporales, por IMDSv2), limitadas a sus propios snapshots. Un host comprometido podría borrar sus snapshots automáticos, pero no los manuales ni los de otros servidores.
- `python3-boto3` en el host. Sin AWS (la VM local) el script no hace nada. Se probó con IMDS falso y boto3 simulado.
- Si la instancia nunca se prende, no hay automáticos nuevos y los existentes no rotan. Los manuales (`pz-ctl.sh backup`, la baja) siguen siendo los consistentes.
- Se eliminan `aws_dlm_lifecycle_policy`, su rol, `backup_policy_enabled` y el output `backup_policy_id`; se agregan `auto_backup_enabled` y el output `auto_backup`. Nunca se publicaron.
- Los snapshots siguen sin pisarse: son incrementales e independientes.

**D39. Tiers de tamaño parametrizados.** `tier` (`minimo`, `estandar` por defecto, `robusto`, `grande`) fija instancia, heap, margen y disco (`locals.tiers`). `instance_type`, `pz_java_xmx_mb`, `pz_host_overhead_mb` y `root_volume_size_gb` (null por defecto) lo reemplazan uno por uno, y las precondiciones de RAM siguen aplicando a la combinación final. Por qué: el mantenedor pidió poder levantar la infraestructura según la necesidad, desde lo mínimo para levantar el servidor hasta algo robusto, con una tabla de recomendaciones, sin editar archivos. Consecuencias:
- La tabla con usos, valores y costos está en el README y en costs.md, y hay que mantenerla junto con `locals.tiers`.
- `minimo` (`t3.medium`, burstable) dispara el aviso de CPU burstable a propósito. Es también el tier para la prueba en la cuenta de AWS (D37).
- Cambiar de tier en un servidor existente: stop → apply → start → provision. El disco solo puede crecer.
