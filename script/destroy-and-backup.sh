#!/bin/bash
set -euo pipefail

S3_BUCKET="tu-bucket-zomboid-backups"
REGION="us-east-1"
PZ_SERVICE="pzsvrtool@zomboid.service"

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

echo "=== 1. Obteniendo IDs de la infraestructura actual ==="
INSTANCE_IP=$(terraform output -raw public_ip 2>/dev/null)

# Obtener el Volume ID del DISCO RAÍZ único asignado a la EC2
VOLUME_ID=$(aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=pz-world-data-root" \
  --query "Volumes[0].VolumeId" --output text --region "$REGION")

if [ -z "$VOLUME_ID" ] || [ "$VOLUME_ID" == "None" ]; then
  echo "Error: No se encontró el disco raíz con el tag 'pz-world-data-root'."
  exit 1
fi

echo "=== 2. Apagando servicio de Project Zomboid vía SSH ==="
if stop_server; then
  echo "Servidor detenido."
elif [ "$FORCE_SNAPSHOT" = "1" ]; then
  echo "WARNING: no se confirmó la detención; FORCE_SNAPSHOT=1, el snapshot puede quedar inconsistente." >&2
else
  echo "Abortando: no se toma snapshot de un servidor en ejecución (use FORCE_SNAPSHOT=1 para forzar)." >&2
  exit 1
fi

echo "=== 3. Creando Snapshot del disco único de 30 GB ==="
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id "$VOLUME_ID" \
  --description "Backup completo de EC2 previo a destruccion" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=pz-world-data-snapshot}]' \
  --region "$REGION" \
  --query "SnapshotId" --output text)

echo "Snapshot creada: $SNAPSHOT_ID. Esperando confirmación..."
aws ec2 wait snapshot-completed --snapshot-id "$SNAPSHOT_ID" --region "$REGION"

echo "=== 4. Guardando metadatos en Amazon S3 ==="
aws s3 sync "s3://$S3_BUCKET/latest/" "s3://$S3_BUCKET/archive/$(date +%Y-%m-%d)/" || true
echo "snapshot_id=$SNAPSHOT_ID" > snapshot_meta.txt
aws s3 cp snapshot_meta.txt "s3://$S3_BUCKET/latest/snapshot_meta.txt"

echo "=== 5. Destruyendo infraestructura con Terraform ==="
terraform destroy -auto-approve

echo "=== Proceso completado. La instancia y su disco fueron eliminados. Snapshot guardada en AWS. ==="
