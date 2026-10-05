#!/bin/bash
# Operación del servidor desde la máquina del operador. Lee la configuración de los
# outputs de Terraform (AWS_REGION, PZ_SERVER_NAME, INSTANCE_ID y TF_DIR la reemplazan).
#
#   status                 estado de la EC2, IP y proceso del juego
#   start                  inicia la EC2 (el juego arranca solo) y espera a que corra
#   stop                   apagado ordenado del juego y después stop de la EC2 (FORCE_STOP=1: sin confirmar)
#   backup                 snapshot consistente sin destruir (detiene el juego y lo vuelve a iniciar)
#   provision              vuelve a correr el playbook en el commit fijado (output repo_commit)
#   push-config <dir>      sube <nombre>.ini, _SandboxVars.lua, _spawnregions.lua, _spawnpoints.lua y aplica
#   join-password          muestra la contraseña de ingreso de los jugadores
#   rotate-join-password   genera una contraseña de ingreso nueva (reinicia el juego)
#   metrics [n] [seg]      n muestras de RAM, swap, CPU y memoria del juego (CSV)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
. "$HERE/lib/common.sh"

FORCE_STOP="${FORCE_STOP:-0}"
STAGE_DIR=/home/pzserver/pzsvrtool/config-staged
RENDERER=/home/pzserver/pzsvrtool/pz-config-render.py

usage() {
  sed -n '2,13s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
  exit 2
}

need_instance() {
  require "la instancia (instance_id / INSTANCE_ID)" "$INSTANCE_ID"
}

need_running() {
  need_instance
  local state
  state="$(instance_state)" || die "no se pudo consultar el estado de $INSTANCE_ID."
  [ "$state" = "running" ] || die "la instancia está '$state'; iniciarla con: $0 start"
}

cmd_status() {
  need_instance
  local state game="desconocido (sin SSH)"
  state="$(instance_state)" || die "no se pudo consultar el estado de $INSTANCE_ID."
  if [ "$state" = "running" ] && [ "$SSH_ENABLED" != "false" ] && [ -n "$INSTANCE_IP" ]; then
    case "$(remote 'if pgrep -u pzserver -f ProjectZomboid >/dev/null; then echo running; else echo stopped; fi' || true)" in
      running) game="corriendo" ;;
      stopped) game="detenido" ;;
      *) game="sin respuesta por SSH" ;;
    esac
  elif [ "$state" != "running" ]; then
    game="detenido"
  fi
  echo "instancia: $INSTANCE_ID ($state)"
  echo "ip:        ${INSTANCE_IP:-?}  (juego: ${INSTANCE_IP:-?}:16261/udp)"
  echo "juego:     $game"
}

cmd_start() {
  need_instance
  local state
  state="$(instance_state)" || die "no se pudo consultar el estado de $INSTANCE_ID."
  case "$state" in
    running) echo "La instancia ya está corriendo." ;;
    pending) wait_state running ;;
    stopping) wait_state stopped; aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null; wait_state running ;;
    stopped) aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null; wait_state running ;;
    *) die "no se puede iniciar una instancia en estado '$state'." ;;
  esac
  echo "Instancia corriendo. El juego arranca solo en unos minutos: ${INSTANCE_IP:-?}:16261"
}

cmd_stop() {
  need_instance
  local state
  state="$(instance_state)" || die "no se pudo consultar el estado de $INSTANCE_ID."
  case "$state" in
    stopped) echo "La instancia ya está detenida."; return 0 ;;
    stopping) wait_state stopped; echo "Instancia detenida."; return 0 ;;
    pending) wait_state running ;;
    running) ;;
    *) die "no se puede detener una instancia en estado '$state'." ;;
  esac

  if [ "$FORCE_STOP" = "1" ]; then
    echo "WARNING: FORCE_STOP=1, se detiene la EC2 sin confirmar el apagado del juego." >&2
  else
    require_ssh "confirmar el apagado ordenado del juego (FORCE_STOP=1 lo omite)"
    echo "Apagando el juego en orden (cuenta regresiva de pzsvrtool)..."
    stop_game || die "no se confirmó el apagado del juego; la EC2 sigue encendida (FORCE_STOP=1 para forzar)."
  fi
  aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null
  wait_state stopped
  echo "Instancia detenida. Siguen cobrándose el disco, los snapshots y la Elastic IP."
}

cmd_backup() {
  need_instance
  require "el volumen raíz (root_volume_id)" "$VOLUME_ID"
  local state snapshot_id
  state="$(instance_state)" || die "no se pudo consultar el estado de $INSTANCE_ID."
  if [ "$state" = "stopped" ]; then
    snapshot_id="$(snapshot_world application "Backup manual (EC2 detenida)")" || die "falló el backup."
  elif [ "$state" = "running" ]; then
    require_ssh "detener el juego antes del snapshot"
    stop_game || die "no se confirmó el apagado del juego; no se toma el snapshot."
    # El juego vuelve a iniciar aunque falle el snapshot.
    trap 'start_game || echo "WARNING: no se pudo volver a iniciar el juego." >&2' EXIT
    snapshot_id="$(snapshot_world application "Backup manual (juego detenido)")" || die "falló el backup."
  else
    die "no se puede hacer backup con la instancia en estado '$state'."
  fi
  echo "Backup consistente: $snapshot_id"
}

cmd_provision() {
  need_running
  require_ssh "reaprovisionar"
  if [ -n "$REPO_COMMIT" ]; then
    echo "Reaprovisionando en el commit $REPO_COMMIT..."
    remote "sudo /usr/local/sbin/pz-provision --commit $REPO_COMMIT"
  else
    echo "WARNING: repo_commit vacío (modo que sigue una rama); se usa la punta de la rama." >&2
    remote "sudo /usr/local/sbin/pz-provision"
  fi
}

# Identifica la revisión del directorio de configuración: commit de git, sin cambios sin commitear.
config_source() {
  local dir="$1"; shift
  if git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then
    local sha
    sha="$(git -C "$dir" rev-parse HEAD)"
    if [ -n "$(git -C "$dir" status --porcelain -- "$@")" ]; then
      [ "${ALLOW_DIRTY:-0}" = "1" ] || die "$dir tiene cambios sin commitear; commitearlos (o ALLOW_DIRTY=1)."
      sha="$sha-dirty"
    fi
    printf 'git:%s@%s' "$(git -C "$dir" remote get-url origin 2>/dev/null || echo local)" "$sha"
  else
    [ "${ALLOW_UNVERSIONED:-0}" = "1" ] || die "$dir no está en un repositorio git; versionarlo (o ALLOW_UNVERSIONED=1)."
    printf 'sin-git:%s' "$(cd "$dir" && cat -- "$@" | sha256sum | cut -c1-16)"
  fi
}

cmd_push_config() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || die "uso: $0 push-config <directorio>"
  need_running
  require_ssh "subir la configuración"

  local files=() f
  for f in "$PZ_SERVER_NAME.ini" "${PZ_SERVER_NAME}_SandboxVars.lua" "${PZ_SERVER_NAME}_spawnregions.lua" "${PZ_SERVER_NAME}_spawnpoints.lua"; do
    [ -f "$dir/$f" ] && files+=("$f")
  done
  [ -f "$dir/$PZ_SERVER_NAME.ini" ] && [ -f "$dir/${PZ_SERVER_NAME}_SandboxVars.lua" ] \
    || die "$dir tiene que contener $PZ_SERVER_NAME.ini y ${PZ_SERVER_NAME}_SandboxVars.lua (nombres = pz_server_name)."

  local source tmp
  source="$(config_source "$dir" "${files[@]}")"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  cp -- "${files[@]/#/$dir/}" "$tmp/"
  printf 'source=%s\npushed_by=%s\npushed_at=%s\n' "$source" "$(id -un)@$(hostname)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp/SOURCE"

  echo "Subiendo ${#files[@]} archivo(s) de $source..."
  # Se valida en el host con el mismo renderizador del playbook antes de reemplazar lo subido antes.
  tar -C "$tmp" -cf - . | remote "sudo bash -c 'set -e
    s=$STAGE_DIR; rm -rf \"\$s.new\"; install -d -m 0700 \"\$s.new\"; tar -C \"\$s.new\" -xf -
    out=\$(mktemp -d); trap \"rm -rf \$out\" EXIT
    PZ_JOIN_PASSWORD=validacion python3 $RENDERER render --stage \"\$s.new\" --name $PZ_SERVER_NAME --out \"\$out\" >/dev/null
    chown -R pzserver:pzserver \"\$s.new\"; rm -rf \"\$s\"; mv \"\$s.new\" \"\$s\"'" \
    || die "la configuración no pasó la validación en el host; no se cambió nada."

  echo "Aplicando (el juego se detiene en orden si estaba corriendo)..."
  cmd_provision
}

cmd_join_password() {
  need_running
  require_ssh "leer la contraseña"
  remote 'sudo cat /home/pzserver/pzsvrtool/.join_password'
  echo
}

cmd_rotate_join_password() {
  need_running
  require_ssh "rotar la contraseña"
  echo "Generando una contraseña de ingreso nueva; el juego se reinicia y los jugadores tienen que usarla al reconectar."
  local extra="-- -e pz_join_password_rotate=true"
  if [ -n "$REPO_COMMIT" ]; then
    remote "sudo /usr/local/sbin/pz-provision --commit $REPO_COMMIT $extra"
  else
    remote "sudo /usr/local/sbin/pz-provision $extra"
  fi
  cmd_join_password
}

cmd_metrics() {
  local count="${1:-1}" interval="${2:-60}"
  [[ "$count" =~ ^[0-9]+$ && "$interval" =~ ^[0-9]+$ ]] || die "uso: $0 metrics [muestras] [segundos]"
  need_running
  require_ssh "medir"
  remote "bash -s -- $count $interval" <<'REMOTE'
n="$1"; i="$2"
echo "fecha,ram_total_mb,ram_disponible_mb,swap_usada_mb,carga_1m,cpu_steal_pct,juego_rss_mb"
while [ "$n" -gt 0 ]; do
  kb() { awk -v k="$1:" '$1 == k {print int($2 / 1024)}' /proc/meminfo; }
  steal=$(vmstat 1 2 | awk 'NR == 2 {for (c = 1; c <= NF; c++) if ($c == "st") col = c} NR == 4 {print $col}')
  rss=$(ps -u pzserver -o rss=,args= | awk '/ProjectZomboid/ {s += $1} END {print int(s / 1024)}')
  echo "$(date -u +%FT%TZ),$(kb MemTotal),$(kb MemAvailable),$(( $(kb SwapTotal) - $(kb SwapFree) )),$(cut -d' ' -f1 /proc/loadavg),$steal,$rss"
  n=$((n - 1))
  if [ "$n" -gt 0 ]; then sleep "$i"; fi
done
REMOTE
}

[ $# -ge 1 ] || usage
cmd="$1"; shift
load_config
case "$cmd" in
  status) cmd_status ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  backup) cmd_backup ;;
  provision) cmd_provision ;;
  push-config) cmd_push_config "$@" ;;
  join-password) cmd_join_password ;;
  rotate-join-password) cmd_rotate_join_password ;;
  metrics) cmd_metrics "$@" ;;
  *) usage ;;
esac
