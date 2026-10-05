#!/bin/bash
# Los chequeos van entre comillas simples a propósito: check() los evalúa tras cada ejecución.
# shellcheck disable=SC2016,SC2034
# Tests offline de script/destroy-and-backup.sh y script/pz-ctl.sh: aws, ssh y terraform
# se reemplazan por stubs en tests/script/bin, así que nada llega a AWS ni a un servidor.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
DESTROY="$REPO/script/destroy-and-backup.sh"
CTL="$REPO/script/pz-ctl.sh"
PASS=0
FAIL=0

# run_case <nombre> [VAR=valor ...]: corre destroy-and-backup.sh en un dir temporal con stubs.
run_case() {
  CASE="$1"; shift
  run_in "$DESTROY" "$@"
}

# ctl_case <nombre> "<args de pz-ctl>" [VAR=valor ...]
ctl_case() {
  CASE="pz-ctl $1"; local args="$2"; shift 2
  # shellcheck disable=SC2086
  run_in "$CTL" "$@" -- $args
}

# run_in <script> [VAR=valor ...] [-- args del script]
run_in() {
  local script="$1"; shift
  local envs=() args=()
  while [ $# -gt 0 ]; do
    if [ "$1" = "--" ]; then shift; args=("$@"); break; fi
    envs+=("$1"); shift
  done
  STUB_DIR="$(mktemp -d)"
  export STUB_DIR STUB_LOG="$STUB_DIR/calls.log"
  : > "$STUB_LOG"
  (cd "${CASE_CWD:-$STUB_DIR}" && env PATH="$HERE/bin:$PATH" POLL_INTERVAL=0 ${envs[@]+"${envs[@]}"} "$script" ${args[@]+"${args[@]}"}) > "$STUB_DIR/out.log" 2>&1
  RC=$?
}

check() {
  if eval "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FALLA [$CASE] $1"
    sed 's/^/    | /' "$STUB_LOG" "$STUB_DIR/out.log"
  fi
}

called() { grep -qF -- "$1" "$STUB_LOG"; }
count() { grep -cF -- "$1" "$STUB_LOG"; }
out_has() { grep -qF -- "$1" "$STUB_DIR/out.log"; }
# Posición (línea) de la primera llamada que contiene el texto.
line_of() { grep -nF -- "$1" "$STUB_LOG" | head -1 | cut -d: -f1; }

# =============================================================================
# destroy-and-backup.sh
# =============================================================================

run_case "detención confirmada" STUB_PZ_RUNNING_POLLS=2
check "sale con 0" '[ "$RC" -eq 0 ]'
check "detiene el servicio con el entorno del bus de usuario, expandido en remoto" 'called "sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/\$(id -u pzserver) systemctl --user stop pzsvrtool@"'
check "consulta hasta que el proceso termina" '[ "$(count pgrep)" -eq 3 ]'
check "snapshot creado" 'called "ec2 create-snapshot"'
check "snapshot marcado consistente y manual, con el servidor" 'called "Key=pz-consistency,Value=application" && called "Key=pz-backup,Value=manual" && called "Key=pz-server,Value=world1"'
check "el tag Name sigue siendo el que usa la restauración" 'called "Key=Name,Value=pz-world-data-snapshot}"'
check "se ejecuta destroy después del snapshot" '[ "$(line_of "destroy -auto-approve")" -gt "$(line_of "create-snapshot")" ]'
check "sin fijar host key" 'called "UserKnownHostsFile=/dev/null"'

run_case "ssh inaccesible" STUB_SSH_FAIL=1
check "sale con error" '[ "$RC" -ne 0 ]'
check "sin snapshot" '! called "create-snapshot"'
check "sin destroy" '! called "destroy"'

run_case "el proceso nunca se detiene" STUB_PZ_RUNNING_POLLS=999 STOP_TIMEOUT=0
check "sale con error" '[ "$RC" -ne 0 ]'
check "sin snapshot" '! called "create-snapshot"'
check "sin destroy" '! called "destroy"'

run_case "forzado" STUB_SSH_FAIL=1 FORCE_SNAPSHOT=1
check "sale con 0" '[ "$RC" -eq 0 ]'
check "advierte" 'out_has WARNING'
check "snapshot creado" 'called "ec2 create-snapshot"'
check "no declara consistencia" 'called "Value=unconfirmed" && ! called "Value=application"'

run_case "falla el snapshot" STUB_AWS_FAIL="ec2 create-snapshot"
check "sale con error" '[ "$RC" -ne 0 ]'
check "sin destroy" '! called "destroy"'

run_case "el snapshot no se completa" STUB_AWS_FAIL="ec2 wait"
check "sale con error sin destroy" '[ "$RC" -ne 0 ] && ! called "destroy"'

run_case "instancia ya detenida (pz-ctl.sh stop)" STUB_EC2_STATES=stopped
check "sale con 0" '[ "$RC" -eq 0 ]'
check "no usa SSH" '! called "ssh "'
check "snapshot consistente" 'called "Value=application"'
check "destroy" 'called "destroy -auto-approve"'

run_case "preflight: SSH no configurado" STUB_TF_OUT_ssh_enabled=false
check "sale con error" '[ "$RC" -ne 0 ]'
check "explica cómo configurar SSH" 'out_has "ssh_allowed_cidrs"'
check "sin llamadas SSH ni snapshot" '! called "ssh " && ! called "create-snapshot"'

run_case "clave ssh" SSH_KEY=/keys/pz.pem
check "usa el archivo de identidad" 'called "-i /keys/pz.pem"'
check "puerto 22 por defecto" 'called "-p 22"'

run_case "puerto ssh" SSH_PORT=2222
check "usa el puerto indicado" 'called "-p 2222" && ! called "-p 22 "'

run_case "configuración desde outputs de terraform"
check "sale con 0" '[ "$RC" -eq 0 ]'
check "servicio desde el output pz_server_name" 'called "systemctl --user stop pzsvrtool@world1.service"'
check "región desde el output aws_region" 'called "ec2 create-snapshot --volume-id vol-output" && called "--region sa-east-1"'
check "instancia desde el output instance_id" 'called "describe-instances --instance-ids i-output"'
check "volumen desde root_volume_id, no por tag" '! called "describe-volumes"'
check "terraform apunta a terraform/ del repo desde cualquier cwd" '! grep -q "^terraform output" "$STUB_LOG" && called "terraform -chdir=$REPO/terraform output -raw public_ip"'
check "sin bucket S3 de metadatos (#17)" '! called "aws s3"'

run_case "reemplazos por entorno" AWS_REGION=eu-west-1 PZ_SERVER_NAME=other INSTANCE_ID=i-env
check "reemplazo de región" 'called "--region eu-west-1" && ! called "--region sa-east-1"'
check "reemplazo del nombre del servidor" 'called "pzsvrtool@other.service"'
check "reemplazo de la instancia" 'called "--instance-ids i-env"'

for missing in aws_region pz_server_name public_ip root_volume_id instance_id; do
  run_case "falta $missing" STUB_TF_MISSING="$missing"
  check "sale con error" '[ "$RC" -ne 0 ]'
  check "sin llamadas SSH ni AWS" '! called "ssh " && ! called "aws "'
  check "nombra el valor faltante" 'out_has "no se pudo resolver"'
done

CASE_CWD="$REPO" run_case "ejecución desde la raíz del repo"
check "sale con 0" '[ "$RC" -eq 0 ]'
check "terraform apunta a terraform/" 'called "terraform -chdir=$REPO/terraform destroy -auto-approve"'

# =============================================================================
# pz-ctl.sh: sesiones con stop/start (#9)
# =============================================================================

ctl_case "stop con el juego corriendo" stop STUB_EC2_STATES=running,running,stopping,stopped STUB_PZ_RUNNING_POLLS=1
check "sale con 0" '[ "$RC" -eq 0 ]'
check "apaga el juego antes de detener la EC2" '[ "$(line_of "systemctl --user stop")" -lt "$(line_of "ec2 stop-instances")" ]'
check "espera a que el proceso termine" '[ "$(line_of pgrep)" -lt "$(line_of "ec2 stop-instances")" ]'
check "detiene la instancia de los outputs" 'called "ec2 stop-instances --instance-ids i-output --region sa-east-1"'
check "espera el estado stopped" '[ "$(count describe-instances)" -ge 3 ]'
check "avisa los costos que siguen" 'out_has "Elastic IP"'

ctl_case "stop sin confirmación del juego" stop STUB_PZ_RUNNING_POLLS=999 STOP_TIMEOUT=0
check "sale con error" '[ "$RC" -ne 0 ]'
check "la EC2 sigue encendida" '! called "stop-instances"'

ctl_case "stop con SSH caído" stop STUB_SSH_FAIL=1
check "sale con error" '[ "$RC" -ne 0 ]'
check "sin force implícito" '! called "stop-instances"'

ctl_case "stop forzado" stop STUB_SSH_FAIL=1 FORCE_STOP=1 STUB_EC2_STATES=running,stopped
check "sale con 0" '[ "$RC" -eq 0 ]'
check "advierte" 'out_has WARNING'
check "detiene la EC2" 'called "stop-instances"'

ctl_case "stop sin SSH configurado" stop STUB_TF_OUT_ssh_enabled=false
check "sale con error" '[ "$RC" -ne 0 ]'
check "explica la configuración de SSH" 'out_has "ssh_allowed_cidrs"'
check "no detiene la EC2" '! called "stop-instances"'

ctl_case "stop con la instancia ya detenida" stop STUB_EC2_STATES=stopped
check "sale con 0" '[ "$RC" -eq 0 ]'
check "no hace nada" '! called "stop-instances" && ! called "ssh "'

ctl_case "stop mientras se está deteniendo" stop STUB_EC2_STATES=stopping,stopping,stopped
check "sale con 0 tras esperar" '[ "$RC" -eq 0 ] && [ "$(count describe-instances)" -eq 3 ]'

ctl_case "stop: falla la API de AWS" stop STUB_AWS_FAIL="ec2 stop-instances"
check "propaga el error" '[ "$RC" -ne 0 ]'

ctl_case "stop: la EC2 no llega a stopped" stop STUB_EC2_STATES=running,stopping INSTANCE_TIMEOUT=0
check "sale con error por timeout" '[ "$RC" -ne 0 ] && out_has "stopping"'

ctl_case "start desde detenida" start STUB_EC2_STATES=stopped,pending,running
check "sale con 0" '[ "$RC" -eq 0 ]'
check "inicia la instancia" 'called "ec2 start-instances --instance-ids i-output"'
check "informa la IP estable" 'out_has "203.0.113.10:16261"'

ctl_case "start ya corriendo" start
check "sale con 0" '[ "$RC" -eq 0 ]'
check "no la vuelve a iniciar" '! called "start-instances"'

ctl_case "start mientras se detiene" start STUB_EC2_STATES=stopping,stopped,running
check "espera stopped y después inicia" '[ "$RC" -eq 0 ] && called "start-instances"'

ctl_case "start de una instancia terminada" start STUB_EC2_STATES=terminated
check "sale con error" '[ "$RC" -ne 0 ] && ! called "start-instances"'

ctl_case "start: no llega a running" start STUB_EC2_STATES=stopped,pending INSTANCE_TIMEOUT=0
check "sale con error por timeout" '[ "$RC" -ne 0 ]'

ctl_case "status" status
check "muestra instancia, IP y juego" '[ "$RC" -eq 0 ] && out_has "i-output (running)" && out_has "203.0.113.10" && out_has "detenido"'

# =============================================================================
# pz-ctl.sh: backup consistente sin destruir (#10)
# =============================================================================

ctl_case "backup con el juego corriendo" backup
check "sale con 0" '[ "$RC" -eq 0 ]'
check "snapshot después de detener el juego" '[ "$(line_of "systemctl --user stop")" -lt "$(line_of create-snapshot)" ]'
check "vuelve a iniciar el juego después" '[ "$(line_of "systemctl --user start")" -gt "$(line_of create-snapshot)" ]'
check "consistente" 'called "Value=application"'
check "no destruye" '! called destroy'

ctl_case "backup: falla el snapshot" backup STUB_AWS_FAIL="ec2 create-snapshot"
check "sale con error" '[ "$RC" -ne 0 ]'
check "igual vuelve a iniciar el juego" 'called "systemctl --user start"'

ctl_case "backup: no se confirma la detención" backup STUB_PZ_RUNNING_POLLS=999 STOP_TIMEOUT=0
check "sale con error sin snapshot" '[ "$RC" -ne 0 ] && ! called create-snapshot'

ctl_case "backup con la EC2 detenida" backup STUB_EC2_STATES=stopped
check "snapshot sin SSH" '[ "$RC" -eq 0 ] && called create-snapshot && ! called "ssh "'

# =============================================================================
# pz-ctl.sh: revisión fija (#18), configuración (#8) y contraseña de ingreso (#13)
# =============================================================================

ctl_case "provision" provision
check "usa el commit del output repo_commit" 'called "sudo /usr/local/sbin/pz-provision --commit 0123456789abcdef0123456789abcdef01234567"'

ctl_case "provision en modo rama" provision STUB_TF_OUT_repo_commit=
check "advierte que la rama es mutable" '[ "$RC" -eq 0 ] && out_has WARNING && called "sudo /usr/local/sbin/pz-provision"'

ctl_case "provision con la EC2 detenida" provision STUB_EC2_STATES=stopped
check "sale con error" '[ "$RC" -ne 0 ] && ! called "pz-provision"'

CFG="$(mktemp -d)"
git -C "$CFG" init -q
printf 'Mods=b;a\nWorkshopItems=2;1\nMap=Muldraugh, KY\nPassword=\n' > "$CFG/world1.ini"
printf 'SandboxVars = { VERSION = 6, }\n' > "$CFG/world1_SandboxVars.lua"
printf 'otro\n' > "$CFG/ajeno.txt"
git -C "$CFG" add world1.ini world1_SandboxVars.lua
git -C "$CFG" -c user.email=t@t -c user.name=t commit -qm cfg
CFG_SHA="$(git -C "$CFG" rev-parse HEAD)"

ctl_case "push-config" "push-config $CFG"
check "sale con 0" '[ "$RC" -eq 0 ]'
check "sube solo los archivos del contrato" '[ -f "$STUB_DIR/upload/world1.ini" ] && [ -f "$STUB_DIR/upload/world1_SandboxVars.lua" ] && [ ! -e "$STUB_DIR/upload/ajeno.txt" ]'
check "registra el commit de origen" 'grep -q "^source=git:local@$CFG_SHA$" "$STUB_DIR/upload/SOURCE"'
check "el contenido llega sin cambios (orden de Mods)" 'cmp -s "$CFG/world1.ini" "$STUB_DIR/upload/world1.ini"'
check "valida en el host antes de reemplazar" 'called "pz-config-render.py render --stage"'
check "aplica con pz-provision en el commit fijado" '[ "$(line_of "pz-provision --commit")" -gt "$(line_of "tar -C")" ]'

printf 'Mods=c\n' >> "$CFG/world1.ini"
ctl_case "push-config con cambios sin commitear" "push-config $CFG"
check "se rechaza" '[ "$RC" -ne 0 ] && out_has "sin commitear" && ! called "ssh "'

ctl_case "push-config con cambios sin commitear permitidos" "push-config $CFG" ALLOW_DIRTY=1
check "marca la revisión como dirty" '[ "$RC" -eq 0 ] && grep -q "$CFG_SHA-dirty" "$STUB_DIR/upload/SOURCE"'

ctl_case "push-config rechazado en el host" "push-config $CFG" ALLOW_DIRTY=1 STUB_REMOTE_FAIL="pz-config-render.py"
check "sale con error sin aplicar" '[ "$RC" -ne 0 ] && ! called "pz-provision"'

NOGIT="$(mktemp -d)"
cp "$CFG/world1.ini" "$CFG/world1_SandboxVars.lua" "$NOGIT/"
ctl_case "push-config fuera de git" "push-config $NOGIT"
check "se rechaza sin ALLOW_UNVERSIONED" '[ "$RC" -ne 0 ] && out_has "repositorio git"'

rm "$NOGIT/world1_SandboxVars.lua"
ctl_case "push-config sin SandboxVars" "push-config $NOGIT" ALLOW_UNVERSIONED=1
check "se rechaza localmente" '[ "$RC" -ne 0 ] && out_has "_SandboxVars.lua" && ! called "tar -C"'

ctl_case "join-password" join-password
check "lee el archivo del host por SSH" '[ "$RC" -eq 0 ] && called "sudo cat /home/pzserver/pzsvrtool/.join_password" && out_has JoinPw123456789'

ctl_case "rotate-join-password" rotate-join-password
check "reaprovisiona con rotación" 'called "pz-provision --commit 0123456789abcdef0123456789abcdef01234567 -- -e pz_join_password_rotate=true"'

ctl_case "metrics" "metrics 2 1"
check "mide por SSH" '[ "$RC" -eq 0 ] && called "bash -s -- 2 1"'

ctl_case "metrics con argumentos inválidos" "metrics x"
check "sale con error" '[ "$RC" -ne 0 ] && ! called "ssh "'

ctl_case "subcomando desconocido" foo
check "muestra el uso" '[ "$RC" -eq 2 ] && out_has "push-config"'

echo "tests de los scripts: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
