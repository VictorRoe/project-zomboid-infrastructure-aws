# Registro de decisiones

Las entradas nuevas van al final. Cada entrada registra qué se decidió, por qué y sus consecuencias. El estado actual está en [spec.md](spec.md).

## Antes del 2026-10-04: diseño existente (deducido del código)

**D1. Una sola instancia EC2 con un único disco raíz contiene todo.** Es simple y barato para un grupo chico. Consecuencia: un backup implica hacer snapshot de todo el disco raíz, y los datos del mundo no se pueden separar del SO.

**D2. La instancia se configura sola (cloud-init clona el repo y Ansible corre localmente).** No hace falta acceso SSH ni un controlador de Ansible. Consecuencia: el playbook sale de `main` en GitHub, así que los cambios sin pushear nunca se despliegan.

**D3. El juego lo gestiona pzsvrtool (versión fija 1.7.3) como servicio systemd de usuario con linger.** pzsvrtool aporta sesiones tmux, cuentas regresivas, backups y el flujo de instalación. Consecuencias: toda llamada a `systemctl --user` necesita el entorno del bus de usuario, y el `TimeoutStopSec=20m` a nivel host le da tiempo al juego para guardar al apagarse.

**D4. Las actualizaciones del juego solo ocurren dentro de una ventana horaria, con un backup previo y un reinicio de recuperación.** No se echa a los jugadores en horario pico, y una actualización fallida no deja el servidor caído. Consecuencia: una actualización puede demorarse hasta un día.

**D5. Destruir cuando no se usa y conservar un snapshot.** Ahorra costo de EC2 entre sesiones de juego. Consecuencia: hace falta restaurar para tener continuidad, pero todavía no está conectado ([#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)). *Revisión 2026-10-04: stop/start lograría el mismo ahorro con menos complejidad; ver D20 y [#9](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/9).*

**D6. El heap de Java queda en el valor por defecto del juego; el margen extra sale del swap y de la RAM de la VM.** Mantiene la configuración cerca de upstream. Consecuencia: la instancia necesita al menos unos 7,5 GB de RAM (se verifica). *Revisión 2026-10-04: FalopaServer usa `-Xmx8g`; ver D20 y [#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7).*

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
