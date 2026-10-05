# CLAUDE.md

Este archivo orienta a Claude Code (claude.ai/code) cuando trabaja con el código de este repositorio.

## Qué es

Infraestructura como código para alojar un servidor dedicado de Project Zomboid en una sola instancia EC2 de AWS. No hay código de aplicación ni paso de build: el repo es Terraform + un playbook de Ansible + un script de Bash, con una suite de tests offline (con mocks). Toda la documentación está en castellano; los identificadores y comandos, en inglés.

## Comandos

Terraform (correr desde `terraform/`; el estado es local, sin backend):

```bash
terraform init
terraform fmt -check && terraform validate
terraform plan
terraform apply
terraform output -raw public_ip
```

Suite de tests offline (sin credenciales de AWS; el provider está simulado). Necesita Terraform >= 1.9 (instalado en `~/.local/bin/terraform` en esta máquina):

```bash
make test                                                     # todos los chequeos
make tf-test                                                  # init + fmt -check + validate + terraform test
make user-data-check                                          # renderiza el script de arranque, bash -n + shellcheck
make script-test                                              # script de backup contra stubs de aws/ssh/terraform (tests/script/bin)
make ansible-test                                             # validación/generación de la contraseña de admin en localhost
terraform -chdir=terraform test -filter=tests/ami.tftest.hcl  # una sola suite
```

Ansible (validar localmente sin host destino):

```bash
ansible-playbook --syntax-check -i playbook/inventory.ini playbook/project-zomboid-server-install.yml
ansible-lint playbook/project-zomboid-server-install.yml   # si está instalado
# Reemplazar variables en lugar de editar los valores por defecto (playbook/vars/main.yml), p. ej. una contraseña de admin provista:
ansible-playbook -i playbook/inventory.ini playbook/project-zomboid-server-install.yml -e pz_admin_password=...
```

Baja con backup: `script/destroy-and-backup.sh` (desde cualquier directorio; usa `terraform -chdir=<repo>/terraform`, la configuración sale de los outputs y se reemplaza con `S3_BUCKET`/`AWS_REGION`/`PZ_SERVER_NAME`/`TF_DIR`).

## Arquitectura: cómo se conectan las piezas

1. **Terraform** (`terraform/main.tf`) crea un security group (UDP 16261-16262, 8766; TCP 22) y una instancia EC2 Ubuntu con un volumen raíz gp3 de 30 GB con tag `pz-world-data-root`.
2. **`user_data` de la EC2** (`terraform/templates/user_data.sh.tftpl`) instala Ansible, clona este repo **desde GitHub (`VictorRoe/project-zomboid-infrastructure-aws`)** (o, en un disco restaurado, hace fetch/reset como `ubuntu`) y corre el playbook contra `localhost`. Consecuencia: los cambios al playbook solo llegan a instancias nuevas después de pushearlos a la rama por defecto de ese repo.
3. **El playbook de Ansible** (`playbook/project-zomboid-server-install.yml`, `inventory.ini` = conexión local) configura el host:
   - Crea el usuario `pzserver` y el archivo de swap, e instala el `.deb` de `pzsvrtool` con versión fija (Lu5ck/pzsvrtool), que envuelve SteamCMD (app 380870) y tmux.
   - Corre el servidor como **servicio systemd de usuario** `pzsvrtool@<pz_server_name>.service` de `pzserver`, con linger activo. Todas las llamadas a `systemctl --user` pasan por `runuser` con `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` explícitos; mantener ese patrón al agregar tareas.
   - Los valores por defecto están en `playbook/vars/main.yml`; la validación, en `tasks/validate.yml`. La contraseña de admin se provee o se genera y se persiste en `~pzserver/pzsvrtool/.admin_password` (`tasks/admin_password.yml`), y después se escribe en `pzsvrtool.config`. Nunca pasar secretos por Terraform/user_data, y mantener `no_log` en las tareas que manejan la contraseña.
   - Instala un `pz-auto-update.sh` embebido más un `.service`/`.timer` de usuario que consulta Steam y solo actualiza dentro de una ventana horaria (cuenta regresiva ordenada → espera del apagado → backup → reinstalación → verificación del buildid → reinicio, con reinicio de recuperación si falla).
   - Configura UFW al final (SSH permitido antes de activarlo). Los puertos de UFW tienen que coincidir con el security group de Terraform.
4. **Backup/restauración:** `destroy-and-backup.sh` detiene el servicio por SSH (necesita `ssh_public_key`/`ssh_key_name`; aborta si no se confirma que el proceso del juego terminó), hace snapshot del volumen raíz con el tag `pz-world-data-snapshot`, escribe el ID del snapshot en S3 y ejecuta `terraform destroy`. En la siguiente creación, `main.tf` registra una imagen (`aws_ami.restored`) desde el último snapshot con tag (o `restore_snapshot_id`) y arranca desde ella; `restore_from_snapshot = false` lo desactiva.

## Invariantes

- La configuración fluye variables de Terraform → outputs → script de backup, y → `user_data` → playbook (`pz_server_name`). No hardcodear bucket/región/nombre del servidor en otro lado. El bucket S3 no lo gestiona este stack a propósito.
- `aws_instance.pz_server` ignora los cambios de `ami` a propósito: el disco raíz es el mundo, así que ni una imagen de Ubuntu más nueva ni un snapshot más nuevo pueden reemplazar un servidor en marcha. Nunca quitarlo sin una estrategia de backup.
- El script de backup nunca debe hacer snapshot sin una detención confirmada; toda llamada nueva a AWS/SSH/Terraform en él necesita su comportamiento en los stubs de `tests/script/bin`.
- Los tests de Terraform simulan AWS; un `aws_ebs_snapshot_ids` simulado no devuelve IDs, así que los tests que necesitan un snapshot tienen que hacer `override_data` de cada data source de snapshot por dirección completa (ver `terraform/tests/restore.tftest.hcl`).

## Flujo de trabajo

Los cambios se hacen guiados por specs con OpenSpec (comandos `/opsx:*`; las skills de `.claude/` están en el directorio padre). `openspec/specs/` contiene los contratos de comportamiento (capacidades: `compute-image-selection`, `world-data-restore`, `instance-access`, `world-backup`, `admin-credentials`); los cambios en curso van en `openspec/changes/` y los terminados en `openspec/changes/archive/`. Validar con `openspec validate --all --strict`. `openspec/config.yaml` fija el idioma (castellano) y las reglas de tests offline.

Los problemas abiertos (#7–#13) están listados con prioridad en `docs/architecture.md`; cada uno se trabaja como un cambio de OpenSpec propio.

## Reglas de documentación

`docs/` contiene arquitectura, flujos, spec (estado actual), operación y el registro de decisiones; en la raíz solo viven README, CLAUDE.md y CHANGELOG.md. Todo cambio tiene que actualizar `docs/spec.md` (y `architecture.md`/`flows.md` si corresponde), agregar una entrada numerada y fechada `D<n>` en `docs/decisions.md` (decisión, por qué, consecuencias) y una entrada en la sección `[Sin publicar]` de `CHANGELOG.md`. Todo en castellano.
