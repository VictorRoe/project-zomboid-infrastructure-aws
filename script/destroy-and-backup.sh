#!/bin/bash
# Baja definitiva con backup: detener el juego → snapshot consistente → terraform destroy.
# Para las sesiones de juego usar script/pz-ctl.sh stop/start (conserva disco e IP).
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# FORCE_SNAPSHOT=1 permite tomar el snapshot aunque no se pueda confirmar que el servidor se detuvo.
FORCE_SNAPSHOT="${FORCE_SNAPSHOT:-0}"

echo "=== 1. Obteniendo configuración e IDs de la infraestructura actual ==="
load_config
require "la IP pública (public_ip)" "$INSTANCE_IP"
require "el volumen raíz (root_volume_id)" "$VOLUME_ID"
require "la instancia (instance_id / INSTANCE_ID)" "$INSTANCE_ID"
if [ "$SSH_ENABLED" = "false" ] && [ "$FORCE_SNAPSHOT" != "1" ]; then
  require_ssh "detener el juego antes del snapshot"
fi

STATE="$(instance_state)" || die "no se pudo consultar el estado de $INSTANCE_ID."
CONSISTENCY=application

echo "=== 2. Apagando servicio de Project Zomboid ==="
if [ "$STATE" = "stopped" ]; then
  # pz-ctl.sh stop ya detuvo el juego en orden antes de apagar la EC2.
  echo "La instancia está detenida: el disco ya es consistente."
elif stop_game; then
  echo "Servidor detenido."
elif [ "$FORCE_SNAPSHOT" = "1" ]; then
  echo "WARNING: no se confirmó la detención; FORCE_SNAPSHOT=1, el snapshot puede quedar inconsistente." >&2
  CONSISTENCY=unconfirmed
else
  echo "Abortando: no se toma snapshot de un servidor en ejecución (use FORCE_SNAPSHOT=1 para forzar)." >&2
  exit 1
fi

echo "=== 3. Creando snapshot del disco raíz $VOLUME_ID ==="
SNAPSHOT_ID="$(snapshot_world "$CONSISTENCY" "Backup completo de EC2 previo a destruccion")" \
  || die "falló el snapshot; no se destruye nada."

echo "=== 4. Destruyendo infraestructura con Terraform ==="
terraform -chdir="$TF_DIR" destroy -auto-approve

echo "=== Proceso completado. La instancia, su disco y la Elastic IP fueron eliminados. Snapshot $SNAPSHOT_ID guardada en AWS. ==="
