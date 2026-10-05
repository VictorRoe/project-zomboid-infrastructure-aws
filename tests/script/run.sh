#!/bin/bash
# Los chequeos van entre comillas simples a propósito: check() los evalúa tras cada ejecución.
# shellcheck disable=SC2016,SC2034
# Tests offline de script/destroy-and-backup.sh: aws, ssh y terraform se reemplazan
# por stubs en tests/script/bin, así que nada llega a AWS ni a un servidor.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/../../script/destroy-and-backup.sh"
PASS=0
FAIL=0

# run_case <nombre> [VAR=valor ...]: corre el script en un dir temporal con stubs.
run_case() {
  CASE="$1"; shift
  STUB_DIR="$(mktemp -d)"
  export STUB_DIR STUB_LOG="$STUB_DIR/calls.log"
  : > "$STUB_LOG"
  (cd "${CASE_CWD:-$STUB_DIR}" && env PATH="$HERE/bin:$PATH" POLL_INTERVAL=0 "$@" "$SCRIPT") > "$STUB_DIR/out.log" 2>&1
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

# --- instance-ssh-access (#5) ---

run_case "detención confirmada" STUB_PZ_RUNNING_POLLS=2
check "sale con 0" '[ "$RC" -eq 0 ]'
check "detiene el servicio con el entorno del bus de usuario, expandido en remoto" 'called "sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/\$(id -u pzserver) systemctl --user stop pzsvrtool@"'
check "consulta hasta que el proceso termina" '[ "$(grep -c pgrep "$STUB_LOG")" -eq 3 ]'
check "snapshot creado" 'called "ec2 create-snapshot"'
check "se ejecuta destroy" 'called "terraform -chdir=$REPO/terraform destroy -auto-approve"'
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
check "advierte" 'grep -q WARNING "$STUB_DIR/out.log"'
check "snapshot creado" 'called "ec2 create-snapshot"'

run_case "clave ssh" SSH_KEY=/keys/pz.pem
check "usa el archivo de identidad" 'called "-i /keys/pz.pem"'

# --- backup-script-config (#2) ---

run_case "configuración desde outputs de terraform"
check "sale con 0" '[ "$RC" -eq 0 ]'
check "servicio desde el output pz_server_name" 'called "systemctl --user stop pzsvrtool@world1.service"'
check "región desde el output aws_region" 'called "ec2 create-snapshot --volume-id vol-output" && called "--region sa-east-1"'
check "bucket desde el output backup_bucket_name" 'called "s3://bucket-from-output/latest/snapshot_meta.txt"'
check "volumen desde root_volume_id, no por tag" '! called "describe-volumes"'
check "terraform apunta a terraform/ del repo desde cualquier cwd" '! grep -q "^terraform output" "$STUB_LOG" && called "terraform -chdir=$REPO/terraform output -raw public_ip"'
check "no deja archivo de metadatos en el cwd" '[ ! -e "$STUB_DIR/snapshot_meta.txt" ]'

run_case "reemplazos por entorno" S3_BUCKET=override AWS_REGION=eu-west-1 PZ_SERVER_NAME=other
check "reemplazo del bucket" 'called "s3://override/latest/snapshot_meta.txt"'
check "reemplazo de región" 'called "--region eu-west-1" && ! called "--region sa-east-1"'
check "reemplazo del nombre del servidor" 'called "pzsvrtool@other.service"'

for missing in backup_bucket_name aws_region pz_server_name public_ip root_volume_id; do
  run_case "falta $missing" STUB_TF_MISSING="$missing"
  check "sale con error" '[ "$RC" -ne 0 ]'
  check "sin llamadas SSH ni AWS" '! called "ssh " && ! called "aws "'
  check "nombra el valor faltante" 'grep -q "no se pudo resolver" "$STUB_DIR/out.log"'
done

CASE_CWD="$REPO" run_case "ejecución desde la raíz del repo"
check "sale con 0" '[ "$RC" -eq 0 ]'
check "terraform apunta a terraform/" 'called "terraform -chdir=$REPO/terraform destroy -auto-approve"'

echo "tests del script: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
