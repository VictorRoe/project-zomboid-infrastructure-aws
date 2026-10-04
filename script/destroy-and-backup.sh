#!/bin/bash
set -euo pipefail

# La configuración sale de los outputs de Terraform; las variables de entorno
# S3_BUCKET, AWS_REGION, PZ_SERVER_NAME y TF_DIR tienen prioridad.
TF_DIR="${TF_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)}"

# Segundos máximos para que el proceso del juego termine (el countdown de pzsvrtool es de 5 min).
STOP_TIMEOUT="${STOP_TIMEOUT:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
# FORCE_SNAPSHOT=1 permite tomar el snapshot aunque no se pueda confirmar que el servidor se detuvo.
FORCE_SNAPSHOT="${FORCE_SNAPSHOT:-0}"

# cloud-init regenera las host keys en cada instancia nueva (también al restaurar),
# así que no se fija known_hosts para la IP recién creada.
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes)
if [ -n "${SSH_KEY:-}" ]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

remote() {
  # The command string is built locally on purpose; remote-side expansions are single-quoted by callers.
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "ubuntu@$INSTANCE_IP" "$1"
}

# Detiene el servicio y espera a que no quede proceso ProjectZomboid.
# Devuelve 1 si no puede confirmarlo (SSH caído, stop fallido o timeout).
stop_server() {
  # Comillas simples: $(id -u pzserver) se expande en el servidor, no en esta máquina.
  # shellcheck disable=SC2016
  if ! remote 'sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/$(id -u pzserver) systemctl --user stop '"$PZ_SERVICE"; then
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

tf_out() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || true
}

require() {
  if [ -z "$2" ]; then
    echo "Error: no se pudo resolver $1 (output de Terraform en $TF_DIR o variable de entorno)." >&2
    exit 1
  fi
}

echo "=== 1. Obteniendo configuración e IDs de la infraestructura actual ==="
S3_BUCKET="${S3_BUCKET:-$(tf_out backup_bucket_name)}"
REGION="${AWS_REGION:-$(tf_out aws_region)}"
PZ_SERVER_NAME="${PZ_SERVER_NAME:-$(tf_out pz_server_name)}"
INSTANCE_IP="$(tf_out public_ip)"
# Disco raíz exacto de la EC2 actual (un filtro por tag podría devolver un volumen viejo).
VOLUME_ID="$(tf_out root_volume_id)"

require "el bucket S3 (backup_bucket_name / S3_BUCKET)" "$S3_BUCKET"
require "la región (aws_region / AWS_REGION)" "$REGION"
require "el nombre del servidor (pz_server_name / PZ_SERVER_NAME)" "$PZ_SERVER_NAME"
require "la IP pública (public_ip)" "$INSTANCE_IP"
require "el volumen raíz (root_volume_id)" "$VOLUME_ID"
PZ_SERVICE="pzsvrtool@${PZ_SERVER_NAME}.service"

echo "=== 2. Apagando servicio de Project Zomboid vía SSH ==="
if stop_server; then
  echo "Servidor detenido."
elif [ "$FORCE_SNAPSHOT" = "1" ]; then
  echo "WARNING: no se confirmó la detención; FORCE_SNAPSHOT=1, el snapshot puede quedar inconsistente." >&2
else
  echo "Abortando: no se toma snapshot de un servidor en ejecución (use FORCE_SNAPSHOT=1 para forzar)." >&2
  exit 1
fi

echo "=== 3. Creando snapshot del disco raíz $VOLUME_ID ==="
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id "$VOLUME_ID" \
  --description "Backup completo de EC2 previo a destruccion" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=pz-world-data-snapshot}]' \
  --region "$REGION" \
  --query "SnapshotId" --output text)

echo "Snapshot creada: $SNAPSHOT_ID. Esperando confirmación..."
aws ec2 wait snapshot-completed --snapshot-id "$SNAPSHOT_ID" --region "$REGION"

echo "=== 4. Guardando metadatos en Amazon S3 ==="
aws s3 sync "s3://$S3_BUCKET/latest/" "s3://$S3_BUCKET/archive/$(date +%Y-%m-%d)/" --region "$REGION" || true
META_FILE="$(mktemp)"
trap 'rm -f "$META_FILE"' EXIT
echo "snapshot_id=$SNAPSHOT_ID" > "$META_FILE"
aws s3 cp "$META_FILE" "s3://$S3_BUCKET/latest/snapshot_meta.txt" --region "$REGION"

echo "=== 5. Destruyendo infraestructura con Terraform ==="
terraform -chdir="$TF_DIR" destroy -auto-approve

echo "=== Proceso completado. La instancia y su disco fueron eliminados. Snapshot guardada en AWS. ==="
