# Design

## Contexto

El respaldo es un snapshot del volumen *raíz*. `aws_instance.root_block_device` no admite un `snapshot_id`, por lo que el disco raíz solo puede provenir de una imagen. cloud-init vuelve a ejecutar `user_data` ante un nuevo ID de instancia, por lo que el script de arranque se ejecuta de nuevo sobre un disco restaurado; hoy hace `git clone` en un directorio existente bajo `set -e` y abortaría.

## Objetivos / No objetivos

**Objetivos:** restauración de disco completo sin pasos manuales; valor por defecto seguro cuando no existe snapshot; pruebas deterministas mediante mocks.

**No objetivos:** separar los datos del mundo en un volumen de datos aparte (más limpio a largo plazo, pero una migración mayor); retención/limpieza de snapshots; copia de snapshots entre regiones.

## Decisiones

- **Registrar una imagen a partir del snapshot (`aws_ami` con `ebs_block_device` raíz = snapshot, `/dev/sda1`, hvm, ENA habilitado, gp3, delete_on_termination) y arrancar desde ella.** Alternativas: (a) un volumen de datos separado restaurado vía `aws_ebs_volume.snapshot_id` + montaje — requiere cambiar dónde guarda los datos pzsvrtool y migrar los snapshots existentes; (b) restauración posterior al arranque con la AWS CLI — necesita un rol IAM y más piezas móviles. El registro de imagen encaja con el snapshot de raíz completa existente tal como está.
- **Precedencia de imagen:** `local.instance_ami_id = local.restore_snapshot_id != "" ? aws_ami.restored[0].id : local.base_ami_id`. `local.restore_snapshot_id` = `var.restore_snapshot_id` si está definido, si no el ID del último snapshot etiquetado, si no `""`; se fuerza a `""` cuando `restore_from_snapshot = false`. La restauración prevalece sobre `ami_id` deliberadamente — omitir silenciosamente una restauración porque se definió una sobrescritura perdería datos; `restore_from_snapshot = false` es la exclusión explícita.
- **La búsqueda de snapshots conserva la guarda `count` existente** en `data.aws_ebs_snapshot` (falla ante cero coincidencias).
- **La restauración se aplica solo cuando se crea la instancia.** Con `ignore_changes = [ami]` (de `region-agnostic-ami`), un snapshot nuevo nunca reemplaza un servidor en ejecución; la restauración ocurre en el primer apply posterior a un destroy, o ante un `-replace` explícito. (Hallazgo de la revisión: sin esto, un apply sobre un servidor activo lo revertiría a un snapshot más antiguo.)
- **El snapshot elegido se busca directamente:** `data.aws_ebs_snapshot.restore[0]` (con guarda count, `snapshot_ids = [local.restore_snapshot_id]`) tanto para el caso del último como para el explícito, de modo que su tamaño y estado siempre se conocen. Tamaño = `max(30, volume_size)`, usado por el `ebs_block_device` de la AMI y el `root_block_device` de la instancia.
- **Argumentos de `aws_ami.restored`:** `name = "pz-restore-${snapshot_id}"` (obligatorio, único por región), `root_device_name = "/dev/sda1"`, `virtualization_type = "hvm"`, `ena_support = true` (obligatorio en t3), `boot_mode = "uefi-preferred"` (coincide con Canonical 24.04; funciona con BIOS o UEFI), gp3. Precondición: snapshot `state == "completed"`. Al destruir se desregistra la imagen pero se deja el snapshot (`aws_ami` no administra los snapshots a partir de los cuales se registra).
- **Script de arranque:** `if [ -d /home/ubuntu/repo/.git ]; then runuser -u ubuntu -- git -C … fetch && runuser -u ubuntu -- git -C … reset --hard origin/main; else git clone …; fi`. Git se ejecuta como `ubuntu`: como root se niega a operar sobre un repositorio cuyo propietario es `ubuntu` ("dubious ownership", git ≥ 2.35.2) y `set -e` abortaría. El playbook ya es idempotente (omite la instalación si existe `start-server.sh`, swap/usuario/linger protegidos).
- **Pruebas:** `command = apply` contra `mock_provider "aws"`. El `aws_ebs_snapshot_ids.ids` simulado tiene por defecto `[]`, por lo que cada ejecución con snapshot sobrescribe `data.aws_ebs_snapshot_ids.zomboid_snapshots`, `data.aws_ebs_snapshot.latest_zomboid_snapshot[0]` y `data.aws_ebs_snapshot.restore[0]` (estado `completed`) por dirección completa, además de `override_resource` para `aws_ami.restored` (`id` fijo).

## Riesgos / Compromisos

- [Desajuste del modo de arranque de la imagen restaurada] → las imágenes de Ubuntu arrancan con BIOS heredado en Nitro; registrar con el modo de arranque por defecto, igual que arrancó la imagen de origen; se documenta una verificación manual en la primera restauración real.
- [Snapshot consistente ante fallos (crash-consistent) si el servicio no se detuvo] → se aborda en el cambio `instance-ssh-access` (detención ordenada verificada).
- [Los snapshots antiguos acumulan costos] → fuera de alcance; se anota en el README.

## Plan de migración

Aplicar sobre un servidor activo tras el merge no cambia nada (la AMI se ignora). El siguiente apply posterior a `destroy-and-backup.sh` restaura desde el último snapshot. Para forzar un mundo nuevo, definir `restore_from_snapshot = false`. Los cambios de playbook/user_data llegan a los hosts reales solo después de que este repositorio se fusione upstream (las instancias clonan `main` de GitHub). Reversión: revertir; los snapshots no se tocan.
