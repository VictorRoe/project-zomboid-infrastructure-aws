# shellcheck shell=bash
# Las variables que carga load_config las usan los scripts que lo incluyen.
# shellcheck disable=SC2034
# Funciones compartidas por los scripts del operador (se carga con `source`).
# La configuración sale de los outputs de Terraform; AWS_REGION, PZ_SERVER_NAME,
# INSTANCE_ID y TF_DIR tienen prioridad.

# set -e también dentro de $(...): un fallo de aws no puede devolver un ID vacío.
shopt -s inherit_errexit

TF_DIR="${TF_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform" && pwd)}"

# Segundos máximos para que el proceso del juego termine (el countdown de pzsvrtool es de 3 min).
STOP_TIMEOUT="${STOP_TIMEOUT:-600}"
# Segundos máximos para que la EC2 llegue al estado pedido.
INSTANCE_TIMEOUT="${INSTANCE_TIMEOUT:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

# cloud-init regenera las host keys en cada instancia nueva (también al restaurar),
# así que no se fija known_hosts para la IP.
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR -p "${SSH_PORT:-22}")
if [ -n "${SSH_KEY:-}" ]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

die() { echo "Error: $*" >&2; exit 1; }

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || true
}

require() {
  if [ -z "$2" ]; then
    die "no se pudo resolver $1 (output de Terraform en $TF_DIR o variable de entorno)."
  fi
}

# Carga la configuración común; cada script pide después lo que necesita con require.
load_config() {
  REGION="${AWS_REGION:-$(tf_out aws_region)}"
  PZ_SERVER_NAME="${PZ_SERVER_NAME:-$(tf_out pz_server_name)}"
  INSTANCE_ID="${INSTANCE_ID:-$(tf_out instance_id)}"
  INSTANCE_IP="$(tf_out public_ip)"
  # Disco raíz exacto de la EC2 actual (un filtro por tag podría devolver un volumen viejo).
  VOLUME_ID="$(tf_out root_volume_id)"
  SSH_ENABLED="$(tf_out ssh_enabled)"
  REPO_COMMIT="$(tf_out repo_commit)"
  require "la región (aws_region / AWS_REGION)" "$REGION"
  require "el nombre del servidor (pz_server_name / PZ_SERVER_NAME)" "$PZ_SERVER_NAME"
  PZ_SERVICE="pzsvrtool@${PZ_SERVER_NAME}.service"
}

# Preflight de SSH: Terraform informa si hay key pair y redes administrativas.
require_ssh() {
  require "la IP pública (public_ip)" "$INSTANCE_IP"
  if [ "$SSH_ENABLED" = "false" ]; then
    die "SSH no está configurado (ssh_public_key/ssh_key_name y ssh_allowed_cidrs en terraform.tfvars): no se puede $1."
  fi
}

remote() {
  # The command string is built locally on purpose; remote-side expansions are single-quoted by callers.
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "ubuntu@$INSTANCE_IP" "$1"
}

# Comillas simples: $(id -u pzserver) se expande en el servidor, no en esta máquina.
# shellcheck disable=SC2016
PZ_USER_ENV='sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/$(id -u pzserver)'

# Detiene el servicio y espera a que no quede proceso ProjectZomboid.
# Devuelve 1 si no puede confirmarlo (SSH caído, stop fallido o timeout).
stop_game() {
  if ! remote "$PZ_USER_ENV systemctl --user stop $PZ_SERVICE"; then
    echo "No se pudo detener $PZ_SERVICE por SSH." >&2
    return 1
  fi

  local deadline state
  deadline=$(( $(date +%s) + STOP_TIMEOUT ))
  while :; do
    state="$(remote 'if pgrep -u pzserver -f ProjectZomboid >/dev/null; then echo running; else echo stopped; fi' || true)"
    if [ "$state" = "stopped" ]; then
      return 0
    fi
    if [ -z "$state" ]; then
      echo "Se perdió la conexión SSH al verificar el proceso." >&2
      return 1
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "ProjectZomboid sigue corriendo tras ${STOP_TIMEOUT}s." >&2
      return 1
    fi
    sleep "$POLL_INTERVAL"
  done
}

start_game() {
  remote "$PZ_USER_ENV systemctl --user start $PZ_SERVICE"
}

instance_state() {
  aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
    --query 'Reservations[0].Instances[0].State.Name' --output text
}

# wait_state <estado>: consulta hasta llegar al estado o vencer INSTANCE_TIMEOUT.
wait_state() {
  local want="$1" deadline state
  deadline=$(( $(date +%s) + INSTANCE_TIMEOUT ))
  while :; do
    state="$(instance_state)" || die "no se pudo consultar el estado de $INSTANCE_ID."
    [ "$state" = "$want" ] && return 0
    case "$state" in
      terminated|shutting-down) die "la instancia $INSTANCE_ID está $state." ;;
    esac
    if [ "$(date +%s)" -ge "$deadline" ]; then
      die "$INSTANCE_ID sigue en '$state' tras ${INSTANCE_TIMEOUT}s (se esperaba '$want')."
    fi
    sleep "$POLL_INTERVAL"
  done
}

# snapshot_world <consistencia> <descripción>: snapshot del disco raíz con los tags que
# usa la restauración; espera a que se complete e imprime el ID.
# consistencia: application (juego detenido y confirmado) | unconfirmed (forzado).
snapshot_world() {
  local consistency="$1" description="$2" snapshot_id
  snapshot_id=$(aws ec2 create-snapshot \
    --volume-id "$VOLUME_ID" \
    --description "$description" \
    --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=pz-world-data-snapshot},{Key=pz-server,Value=$PZ_SERVER_NAME},{Key=pz-backup,Value=manual},{Key=pz-consistency,Value=$consistency}]" \
    --region "$REGION" \
    --query "SnapshotId" --output text) || { echo "No se pudo crear el snapshot de $VOLUME_ID." >&2; return 1; }
  [ -n "$snapshot_id" ] || { echo "create-snapshot no devolvió un ID." >&2; return 1; }
  echo "Snapshot creada: $snapshot_id. Esperando confirmación..." >&2
  aws ec2 wait snapshot-completed --snapshot-id "$snapshot_id" --region "$REGION" \
    || { echo "El snapshot $snapshot_id no se completó." >&2; return 1; }
  echo "$snapshot_id"
}
