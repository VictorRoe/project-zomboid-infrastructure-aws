# CLAUDE.md

Este archivo orienta a Claude Code (claude.ai/code) cuando trabaja con el código de este repositorio.

## Qué es

Infraestructura como código para alojar un servidor dedicado de Project Zomboid **genérico** en una sola instancia EC2 de AWS. No apunta a un servidor concreto: perfiles como un servidor con muchos mods se definen con variables (D33). No hay código de aplicación ni paso de build: el repo es Terraform + un playbook de Ansible + scripts de Bash y dos helpers de Python, con tests offline (mocks/stubs) y una VM local. Toda la documentación está en castellano; los identificadores y comandos, en inglés.

## Comandos

Terraform (desde `terraform/`; estado remoto en S3, ver `docs/operations.md`):

```bash
terraform init -backend-config=backend.hcl     # backend.hcl sale de bootstrap/state-backend
terraform plan / apply                          # repo_commit es obligatorio (tfvars)
terraform output -raw public_ip                 # Elastic IP
```

Operación (desde cualquier directorio; lee los outputs): `script/pz-ctl.sh status|start|stop|backup|provision|push-config <dir>|join-password|rotate-join-password|metrics`; baja con `script/destroy-and-backup.sh`.

Tests offline (sin credenciales ni llamadas a AWS). Necesitan Terraform >= 1.11 (instalado en `~/.local/bin/terraform` en esta máquina), ansible-core, git y python3:

```bash
make test               # todo lo de abajo
make tf-test            # terraform fmt/validate/test (mock_provider); suites en terraform/tests/
make bootstrap-test     # bootstrap/state-backend
make user-data-check    # renderiza user_data sin backend (tests/render-user-data.sh): bash -n, shellcheck, < 16 KB
make provision-test     # pz-provision con repos git locales (tests/provision)
make snapshot-test      # pz-auto-snapshot.py con IMDS falso y boto3 simulado (tests/snapshot)
make script-test        # pz-ctl.sh y destroy-and-backup.sh contra stubs (tests/script/bin)
make ansible-test       # contraseñas, heap y configuración en localhost sin root (tests/ansible)
terraform -chdir=terraform test -filter=tests/ssh.tftest.hcl   # una sola suite
```

VM local (QEMU/KVM, sin AWS; clona desde un servidor git en el host con `repo_commit = HEAD`, así que hay que **commitear** antes, no pushear):

```bash
make local-clean && make local-test   # up + config-test + reboot + backup + restore (~20 min)
local/vm.sh ssh '<cmd>'
```

En este entorno, `ansible`/`ansible-playbook` necesitan `</dev/null` (stdin no bloqueante).

## Arquitectura: cómo se conectan las piezas

1. **Terraform** (`terraform/main.tf`): security group (UDP 16261-16262, 8766; TCP 22 solo desde `ssh_allowed_cidrs`), EC2 Ubuntu con el tamaño de `tier` (`locals.tiers`; las variables explícitas ganan) y un disco raíz gp3 (tags `pz-world-data-root`, `pz-world-volume=<nombre>`), Elastic IP y un rol de IAM de la instancia con permisos mínimos para sus snapshots. Lee `aws_ec2_instance_type` para verificar la RAM (heap + margen) y la arquitectura. Backend S3 (`backend.tf`); el bucket lo crea `bootstrap/state-backend`.
2. **`user_data`** (`templates/user_data.sh.tftpl`): instala Ansible, escribe `/etc/pz-provision.env` e instala y ejecuta `pz-provision` (`templates/pz-provision.sh`), que obtiene **el commit fijo** `repo_commit` de este repo desde GitHub, verifica `HEAD` y corre el playbook. El repo tiene que ser público.
3. **Playbook** (`playbook/project-zomboid-server-install.yml`, conexión local):
   - Crea `pzserver`, el swap y linger, e instala pzsvrtool (`.deb` con versión y sha256 fijos), que envuelve SteamCMD y tmux.
   - El servidor corre como **servicio systemd de usuario** `pzsvrtool@<pz_server_name>.service`. Toda llamada a `systemctl --user` pasa por `runuser` con `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` explícitos.
   - `tasks/game_settings.yml`: heap (`files/pz-set-heap.py`), contraseña de ingreso (`tasks/join_password.yml`) y configuración subida por el operador (`files/pz-config-render.py`, `tasks/server_config_*.yml`). Si algo cambia con el juego corriendo, primero lo detiene (`tasks/stop_game.yml`).
   - Con `pz_wait_for_config`, el juego no arranca sin configuración o mundo (drop-in `wait-config.conf`).
   - Valores por defecto en `playbook/vars/main.yml`; validación en `tasks/validate.yml`. También instala `pz-auto-update.sh` (vuelve a fijar el heap después de actualizar) y configura UFW.
4. **Operación:** `script/lib/common.sh` (outputs, SSH, detención del juego, snapshots con tags) es compartido por `pz-ctl.sh` (sesiones stop/start, backups consistentes, `push-config`, `provision`, contraseñas) y `destroy-and-backup.sh` (baja con snapshot). La restauración ocurre al crear: `aws_ami.restored` desde el último `Name=pz-world-data-snapshot` (o `restore_snapshot_id`).

## Invariantes

- La configuración fluye variables de Terraform → outputs → scripts, y → `/etc/pz-provision.env` → playbook. No hardcodear región/nombre/instancia en otro lado.
- `aws_instance.pz_server` ignora `ami` y `user_data` a propósito: el disco raíz es el mundo, y cambiar `user_data` detiene y reinicia la instancia sin volver a ejecutarlo. Las actualizaciones de código van por `pz-ctl.sh provision`.
- `pz-provision` nunca cae a otra revisión: si el commit no existe o `HEAD` no coincide, aborta.
- Nunca hacer snapshot ni detener la EC2 sin una detención del juego confirmada (salvo `FORCE_SNAPSHOT`/`FORCE_STOP`). Toda llamada nueva a AWS/SSH/Terraform en los scripts necesita su comportamiento en los stubs de `tests/script/bin`. Dentro de `$(...)`, comprobar los errores de forma explícita (`inherit_errexit` está activo en `common.sh`).
- Los snapshots que elige la restauración automática (`Name=pz-world-data-snapshot`) tienen que ser consistentes. Los automáticos (`tasks/auto_snapshot.yml` + `files/pz-auto-snapshot.py`, un timer en la instancia, así que solo con ella prendida) se etiquetan `-auto`/`crash`, y el rol de la instancia solo borra `pz-backup=auto` de su servidor.
- Secretos (contraseñas de admin e ingreso) solo en el host (0600), nunca en Terraform, `user_data`, Git ni logs: `no_log` en las tareas que los manejan. El renderizador de configuración nunca imprime valores.
- La configuración en uso solo se reemplaza cuando cambia la revisión renderizada; los cambios manuales se avisan, no se pisan. Nunca se toca el orden de `Mods=`/`Map=`.
- pzsvrtool trabaja en el directorio actual e imprime "Installation Completed" aunque falle: `chdir: "{{ pz_home }}"` y una verificación posterior (D24).
- Tests de Terraform: cada archivo necesita los `override_data`/`override_resource` comunes (tipo de instancia, documentos IAM, cuenta, ARN del rol) y `repo_commit`. Los `check` que fallan hacen fallar el run: declararlos en `expect_failures` cuando el aviso es lo esperado.
- En los tests de Ansible, los reemplazos van por `-e`: `vars_files` gana sobre `vars` del play.

## Flujo de trabajo

Los cambios se hacen guiados por specs con OpenSpec (comandos `/opsx:*`; las skills de `.claude/` están en el directorio padre). `openspec/specs/` tiene los contratos de comportamiento; los cambios terminados van en `openspec/changes/archive/`. Validar con `openspec validate --all --strict`. `openspec/config.yaml` fija el idioma (castellano) y las reglas de tests offline. Nunca usar AWS real sin una cuenta de prueba acordada (mínimos recursos y `destroy` al terminar; D37).

## Reglas de documentación

`docs/` contiene arquitectura, flujos, spec (estado actual), operación (runbook del día a día), costos y el registro de decisiones. En la raíz solo viven README, CLAUDE.md y CHANGELOG.md. Todo cambio tiene que:

- actualizar `docs/spec.md` (y `architecture.md`/`flows.md`/`operations.md` si corresponde);
- agregar una entrada numerada y fechada `D<n>` en `docs/decisions.md` (decisión, por qué, consecuencias);
- agregar una entrada en `[Sin publicar]` de `CHANGELOG.md`.

El README mantiene siempre una sección breve de **costos estimados** con los valores por defecto y la arquitectura (detalle en `docs/costs.md`); si cambia un valor por defecto que afecta el costo, actualizar ambos. Todo en castellano.
