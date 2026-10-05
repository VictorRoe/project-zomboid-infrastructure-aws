#!/bin/bash
# Entorno local: VM Ubuntu 24.04 con QEMU/KVM que imita la EC2. Arranca la misma
# imagen cloud que AWS y le pasa por cloud-init (NoCloud) el user_data que
# renderiza Terraform, sin cambios. No usa AWS. Ver docs/operations.md.
#
# Uso: local/vm.sh up|ssh|wait|check|config-test|reboot-test|restore-test|backup-test|down|clean
#
# La VM clona este repo desde un servidor git HTTP en el host (10.0.2.2 dentro de QEMU)
# con el commit actual fijado (repo_commit = HEAD), así que no hace falta pushear ni que
# el repo sea público. LOCAL_REPO_SOURCE=github clona desde GitHub (rama pusheada).
#
# Los comandos remotos van entre comillas simples a propósito: se expanden en la VM.
# shellcheck disable=SC2016
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="${LOCAL_VM_DIR:-$REPO/.local-vm}"
IMG_URL="https://cloud-images.ubuntu.com/noble/current"
IMG_NAME="noble-server-cloudimg-amd64.img"
BASE="$STATE/$IMG_NAME"
DISK="$STATE/disk.qcow2"
SEED="$STATE/seed.iso"
KEY="$STATE/id_ed25519"
PIDFILE="$STATE/qemu.pid"
GIT_PIDFILE="$STATE/git-http.pid"
TF="${TF:-terraform}"
GIT_PORT="${LOCAL_GIT_PORT:-8730}"
REPO_SOURCE="${LOCAL_REPO_SOURCE:-local}"
FIXTURE="$REPO/tests/ansible/fixtures/world1"

SSH_PORT="${LOCAL_SSH_PORT:-2222}"
VM_MEM="${LOCAL_VM_MEM:-10240}"
VM_CPUS="${LOCAL_VM_CPUS:-4}"
DISK_SIZE="${LOCAL_VM_DISK:-40G}"
PZ_SERVER_NAME="${PZ_SERVER_NAME:-zomboid}"
PROVISION_TIMEOUT="${PROVISION_TIMEOUT:-3600}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-600}"

FAILS=0

log() { printf '[local-vm] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

pass() { log "PASA  $1"; }
fail() { log "FALLA $1"; FAILS=$((FAILS + 1)); }
# expect <descripción> <comando...>: registra PASA/FALLA según el exit code.
expect() {
  local desc="$1"; shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}
finish() {
  if [ "$FAILS" -gt 0 ]; then die "$1: $FAILS chequeo(s) fallaron"; fi
  log "$1: todos los chequeos pasaron"
}

vm_ssh() {
  ssh -i "$KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -o ServerAliveInterval=30 -o BatchMode=yes -o LogLevel=ERROR \
    ubuntu@127.0.0.1 "$@"
}

# Ejecuta systemctl/journalctl --user como pzserver con el bus de usuario.
PZ_USER_ENV='sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/$(id -u pzserver)'

running() { [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }

require_tools() {
  local t
  for t in qemu-system-x86_64 qemu-img cloud-localds curl sha256sum ssh ssh-keygen python3 "$TF"; do
    command -v "$t" >/dev/null || die "falta '$t' en el PATH"
  done
  [ -w /dev/kvm ] || die "sin acceso a /dev/kvm"
}

verify_image() {
  curl -fsSL "$IMG_URL/SHA256SUMS" -o "$STATE/SHA256SUMS"
  (cd "$STATE" && grep -E " \*?${IMG_NAME}\$" SHA256SUMS | sha256sum -c --status -)
}

ensure_image() {
  mkdir -p "$STATE"
  if [ -f "$BASE" ] && verify_image; then
    return
  fi
  log "Descargando $IMG_NAME..."
  curl -fL --progress-bar -o "$BASE.part" "$IMG_URL/$IMG_NAME"
  mv "$BASE.part" "$BASE"
  verify_image || { rm -f "$BASE"; die "el checksum de $IMG_NAME no coincide con SHA256SUMS"; }
  log "Imagen verificada contra SHA256SUMS."
}

ensure_key() {
  [ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C pz-local-vm -f "$KEY"
}

git_running() { [ -f "$GIT_PIDFILE" ] && kill -0 "$(cat "$GIT_PIDFILE")" 2>/dev/null; }

# Sirve un espejo del repo por HTTP "dumb" en 127.0.0.1 (la VM lo ve en 10.0.2.2).
serve_repo() {
  [ "$REPO_SOURCE" = local ] || return 0
  rm -rf "$STATE/git/repo.git"
  mkdir -p "$STATE/git"
  git clone -q --mirror "$REPO" "$STATE/git/repo.git"
  git -C "$STATE/git/repo.git" update-server-info
  if ! git_running; then
    python3 -m http.server "$GIT_PORT" --bind 127.0.0.1 --directory "$STATE/git" >"$STATE/git-http.log" 2>&1 &
    echo $! > "$GIT_PIDFILE"
  fi
}

stop_git() {
  git_running && kill "$(cat "$GIT_PIDFILE")" 2>/dev/null
  rm -f "$GIT_PIDFILE"
}

# Revisión que va a ejecutar la VM: el commit actual (sin cambios sin commitear en lo rastreado).
repo_commit() {
  [ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] \
    || die "hay cambios sin commitear: la VM ejecuta el commit actual (repo_commit = HEAD)"
  if [ "$REPO_SOURCE" = github ]; then
    local branch
    branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
    git -C "$REPO" fetch -q origin "$branch" || die "la rama '$branch' no existe en origin; pushearla primero"
    [ -z "$(git -C "$REPO" log --oneline "origin/$branch..HEAD")" ] || die "hay commits sin pushear en '$branch'"
  fi
  git -C "$REPO" rev-parse HEAD
}

render_user_data() {
  local commit="$1"
  local args=(-var "repo_commit=$commit" -var "pz_server_name=$PZ_SERVER_NAME")
  if [ "$REPO_SOURCE" = local ]; then
    args+=(-var "repo_url=http://10.0.2.2:$GIT_PORT/repo.git" -var "repo_branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)")
  else
    args+=(-var "repo_branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)")
  fi
  TF="$TF" "$REPO/tests/render-user-data.sh" "${args[@]}" > "$STATE/user_data.sh"
  bash -n "$STATE/user_data.sh"
}

# make_seed <instance-id>: user-data MIME = clave SSH (lo que en AWS hacen los
# metadatos) + el user_data renderizado, sin modificar.
make_seed() {
  local instance_id="$1"
  python3 - "$KEY.pub" "$STATE/user_data.sh" "$STATE/user-data" <<'EOF'
import sys
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
pub, script, out = sys.argv[1:]
key = open(pub).read().strip()
msg = MIMEMultipart()
msg.attach(MIMEText(f"#cloud-config\nssh_authorized_keys:\n  - {key}\n", "cloud-config"))
msg.attach(MIMEText(open(script).read(), "x-shellscript"))
open(out, "w").write(msg.as_string())
EOF
  printf 'instance-id: %s\nlocal-hostname: pz-local\n' "$instance_id" > "$STATE/meta-data"
  cloud-localds "$SEED" "$STATE/user-data" "$STATE/meta-data"
}

start_vm() {
  running && die "la VM ya está corriendo (pid $(cat "$PIDFILE"))"
  log "Arrancando VM ($VM_CPUS vCPU, ${VM_MEM} MB): SSH 127.0.0.1:$SSH_PORT, juego 127.0.0.1:16261/udp"
  qemu-system-x86_64 -name pz-local -enable-kvm -cpu host -smp "$VM_CPUS" -m "$VM_MEM" \
    -drive "file=$DISK,if=virtio,format=qcow2" \
    -drive "file=$SEED,if=virtio,format=raw,readonly=on" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22,hostfwd=udp:127.0.0.1:16261-:16261,hostfwd=udp:127.0.0.1:16262-:16262,hostfwd=udp:127.0.0.1:8766-:8766" \
    -device virtio-net-pci,netdev=n0 \
    -display none -serial "file:$STATE/console.log" \
    -daemonize -pidfile "$PIDFILE"
}

wait_ssh() {
  local deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  until vm_ssh true 2>/dev/null; do
    [ "$(date +%s)" -ge "$deadline" ] && die "SSH no respondió en ${BOOT_TIMEOUT}s (ver $STATE/console.log)"
    sleep 5
  done
}

# Espera a que cloud-init (user_data + playbook) termine.
wait_provision() {
  log "Esperando a cloud-init (user_data + playbook; la primera vez descarga el juego)..."
  local rc=0
  timeout "$PROVISION_TIMEOUT" ssh -i "$KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=ERROR -o ServerAliveInterval=30 \
    ubuntu@127.0.0.1 'cloud-init status --wait >/dev/null' || rc=$?
  if [ "$rc" -ne 0 ]; then
    vm_ssh 'sudo tail -n 60 /var/log/cloud-init-output.log' || true
    die "cloud-init terminó con error (rc=$rc)"
  fi
  log "cloud-init terminó."
}

wait_game() {
  local deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  until vm_ssh 'pgrep -u pzserver -f ProjectZomboid >/dev/null'; do
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 5
  done
}

# El juego tarda en cargar assets y el mundo antes de abrir el puerto.
wait_port() {
  local deadline=$(( $(date +%s) + BOOT_TIMEOUT ))
  until vm_ssh 'sudo ss -lun | grep -q ":16261 "'; do
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 5
  done
}

stop_vm() {
  running || return 0
  vm_ssh 'sudo systemctl poweroff' 2>/dev/null || true
  local _
  for _ in $(seq 1 60); do
    running || { rm -f "$PIDFILE"; return 0; }
    sleep 2
  done
  log "La VM no se apagó sola; se termina el proceso de QEMU."
  kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
}

svc() { vm_ssh "$PZ_USER_ENV systemctl --user $1"; }

cmd_up() {
  require_tools
  ensure_image
  ensure_key
  serve_repo
  if [ ! -f "$DISK" ]; then
    local commit
    commit="$(repo_commit)"
    log "Commit que va a ejecutar la VM: $commit ($REPO_SOURCE)"
    render_user_data "$commit"
    qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$DISK" "$DISK_SIZE"
    make_seed "i-local-$(date +%s)"
  fi
  start_vm
  wait_ssh
  wait_provision
  cmd_check
}

# Sin configuración subida el juego espera (pz_wait_for_config); con ella, tiene que correr.
cmd_check() {
  FAILS=0
  local ini="/home/pzserver/Zomboid/Server/$PZ_SERVER_NAME.ini" head
  head="$(git -C "$REPO" rev-parse HEAD)"
  expect "cloud-init terminó sin errores" vm_ssh 'cloud-init status | grep -q "status: done"'
  expect "revisión fija verificada (commit=HEAD del repo)" vm_ssh "sudo grep -qx 'commit=$head' /var/lib/pz-provision/revision && sudo grep -qx 'mode=pinned' /var/lib/pz-provision/revision"
  expect "checkout en ese commit" vm_ssh "[ \"\$(git -C /home/ubuntu/repo rev-parse HEAD)\" = $head ]"
  expect "servicio habilitado" vm_ssh "[ \"\$($PZ_USER_ENV systemctl --user is-enabled pzsvrtool@$PZ_SERVER_NAME.service)\" = enabled ]"
  expect "linger activo" vm_ssh '[ "$(loginctl show-user pzserver -p Linger --value)" = yes ]'
  expect "timer de actualización activo" svc "is-active --quiet pz-auto-update.timer"
  expect "contraseña de admin 0600 de pzserver" vm_ssh '[ "$(sudo stat -c "%a %U" /home/pzserver/pzsvrtool/.admin_password)" = "600 pzserver" ]'
  expect "contraseña de admin de 24+ caracteres" vm_ssh '[ "$(sudo cat /home/pzserver/pzsvrtool/.admin_password | wc -c)" -ge 24 ]'
  expect "config de pzsvrtool usa esa contraseña" vm_ssh 'sudo grep -qxF "pzRootAdminPassword=$(sudo cat /home/pzserver/pzsvrtool/.admin_password)" /home/pzserver/pzsvrtool/pzsvrtool.config'
  expect "contraseña de ingreso 0600, 24 caracteres, distinta de la de admin" vm_ssh 'J=/home/pzserver/pzsvrtool/.join_password; [ "$(sudo stat -c "%a %U" $J)" = "600 pzserver" ] && [ "$(sudo cat $J | wc -c)" -eq 24 ] && ! sudo cmp -s $J /home/pzserver/pzsvrtool/.admin_password'
  expect "el .ini tiene la contraseña de ingreso antes de admitir jugadores" vm_ssh "sudo grep -qxF \"Password=\$(sudo cat /home/pzserver/pzsvrtool/.join_password)\" $ini"
  expect "heap fijado en ProjectZomboid64.json" vm_ssh 'sudo grep -q "\"-Xmx5632m\"" /home/pzserver/pzserver/ProjectZomboid64.json'
  expect "UFW activo con 16261/udp" vm_ssh 'sudo ufw status | grep -q "16261/udp.*ALLOW"'
  expect "timer de snapshots diarios activo y persistente" vm_ssh 'systemctl is-active --quiet pz-auto-snapshot.timer && grep -qx "Persistent=true" /etc/systemd/system/pz-auto-snapshot.timer && grep -qx "PZ_SNAPSHOT_RETAIN=4" /etc/pz-auto-snapshot.env'
  expect "el snapshot automático no hace nada fuera de EC2" vm_ssh 'sudo systemctl start pz-auto-snapshot.service && sudo journalctl -u pz-auto-snapshot.service -n 5 | grep -q "no es una instancia de AWS"'
  if vm_ssh 'sudo test -f /home/pzserver/pzsvrtool/config-applied.json || sudo test -d /home/pzserver/Zomboid/Saves/Multiplayer/'"$PZ_SERVER_NAME"; then
    expect "servicio activo" svc "is-active --quiet pzsvrtool@$PZ_SERVER_NAME.service"
    expect "proceso ProjectZomboid corriendo" wait_game
    expect "escucha en 16261/udp" wait_port
  else
    log "Sin configuración subida: el juego tiene que esperar (correr config-test)."
    expect "el juego no arrancó sin configuración" vm_ssh '! pgrep -u pzserver -f ProjectZomboid >/dev/null'
    expect "no se creó ningún mundo" vm_ssh "! sudo test -d /home/pzserver/Zomboid/Saves/Multiplayer/$PZ_SERVER_NAME"
  fi
  finish "check"
}

# Entorno para correr los scripts del operador contra la VM: SSH real, aws/terraform simulados.
ops_env() {
  OPS_BIN="$(mktemp -d)"
  ln -s "$REPO/tests/script/bin/aws" "$REPO/tests/script/bin/terraform" "$OPS_BIN/"
  export STUB_DIR="$OPS_BIN" STUB_LOG="$OPS_BIN/calls.log"
  : > "$STUB_LOG"
  OPS_ENV=(PATH="$OPS_BIN:$PATH" SSH_PORT="$SSH_PORT" SSH_KEY="$KEY"
    STUB_TF_OUT_public_ip=127.0.0.1 STUB_TF_OUT_pz_server_name="$PZ_SERVER_NAME"
    STUB_TF_OUT_aws_region=local STUB_TF_OUT_repo_commit="$(git -C "$REPO" rev-parse HEAD)")
}

ops_join_password() {
  env "${OPS_ENV[@]}" "$REPO/script/pz-ctl.sh" join-password | grep -qE '^[A-Za-z0-9]{24}$'
}

# Sube la configuración de prueba con pz-ctl.sh push-config (SSH real) y verifica que
# el juego arranca con ella; después, una re-ejecución sin cambios no lo reinicia.
cmd_config_test() {
  running || die "la VM no está corriendo"
  FAILS=0
  local cfg ini="/home/pzserver/Zomboid/Server/$PZ_SERVER_NAME.ini" rc=0 pid_before pid_after
  cfg="$(mktemp -d)"
  for f in "$FIXTURE"/*; do cp "$f" "$cfg/$(basename "$f" | sed "s/^world1/$PZ_SERVER_NAME/")"; done
  git -C "$cfg" init -q && git -C "$cfg" add -A && git -C "$cfg" -c user.email=t@t -c user.name=t commit -qm cfg
  ops_env

  log "Subiendo la configuración de prueba con pz-ctl.sh push-config..."
  env "${OPS_ENV[@]}" "$REPO/script/pz-ctl.sh" push-config "$cfg" || rc=$?
  expect "push-config terminó con éxito" test "$rc" -eq 0
  expect "registro de la configuración aplicada con su origen" vm_ssh "sudo grep -q 'git:local@' /home/pzserver/pzsvrtool/config-applied.json"
  expect "el juego arranca con la configuración" wait_game
  expect "escucha en 16261/udp" wait_port
  expect "el .ini tiene la contraseña de ingreso gestionada" vm_ssh "sudo grep -qxF \"Password=\$(sudo cat /home/pzserver/pzsvrtool/.join_password)\" $ini"
  expect "RCON desactivado" vm_ssh "sudo grep -qx 'RCONPassword=' $ini"
  expect "el juego usó el .ini subido (Map y PublicName)" vm_ssh "sudo grep -qx 'Map=Muldraugh, KY' $ini && sudo grep -qx 'PublicName=pz-local-test' $ini"
  expect "el juego completó el .ini mínimo con sus opciones" vm_ssh "sudo grep -q '^PauseEmpty=' $ini"
  expect "el mundo se creó con la configuración" vm_ssh "sudo test -d /home/pzserver/Zomboid/Saves/Multiplayer/$PZ_SERVER_NAME"
  expect "SandboxVars del operador en uso" vm_ssh "sudo grep -q 'StartMonth = 12' /home/pzserver/Zomboid/Server/${PZ_SERVER_NAME}_SandboxVars.lua"
  expect "pz-ctl.sh join-password la muestra" ops_join_password

  pid_before="$(vm_ssh 'pgrep -u pzserver -f ProjectZomboid | head -1')"
  log "Re-ejecutando pz-provision sin cambios (no debe reiniciar el juego)..."
  rc=0
  env "${OPS_ENV[@]}" "$REPO/script/pz-ctl.sh" provision || rc=$?
  pid_after="$(vm_ssh 'pgrep -u pzserver -f ProjectZomboid | head -1')"
  expect "provision sin cambios terminó bien" test "$rc" -eq 0
  expect "el juego no se reinició (mismo PID)" test "$pid_before" = "$pid_after"
  rm -rf "$cfg" "$OPS_BIN"
  finish "config-test"
}

cmd_reboot_test() {
  running || die "la VM no está corriendo"
  FAILS=0
  local boot_before
  boot_before="$(vm_ssh 'cat /proc/sys/kernel/random/boot_id')"
  log "Reiniciando la VM..."
  vm_ssh 'sudo systemctl reboot' 2>/dev/null || true
  sleep 15
  wait_ssh
  expect "la VM se reinició (boot_id nuevo)" vm_ssh "[ \"\$(cat /proc/sys/kernel/random/boot_id)\" != $boot_before ]"
  expect "el juego vuelve a correr solo tras el reinicio" wait_game
  expect "vuelve a escuchar en 16261/udp" wait_port
  expect "servicio activo tras el reinicio" svc "is-active --quiet pzsvrtool@$PZ_SERVER_NAME.service"
  finish "reboot-test"
}

cmd_restore_test() {
  running || die "la VM no está corriendo"
  FAILS=0
  local marker pw_before pw_after old_id new_id resets_before
  marker="restore-$(date +%s)"
  vm_ssh "echo $marker | sudo -u pzserver tee /home/pzserver/restore-marker >/dev/null"
  pw_before="$(vm_ssh 'sudo sha256sum /home/pzserver/pzsvrtool/.admin_password /home/pzserver/pzsvrtool/.join_password /home/pzserver/pzsvrtool/config-applied.json')"
  old_id="$(vm_ssh 'cloud-init query instance_id')"
  resets_before="$(vm_ssh 'sudo grep -c "revisión verificada" /var/log/cloud-init-output.log || true')"

  serve_repo
  log "Apagando la VM y copiando su disco (equivale al snapshot)..."
  stop_vm
  mv "$DISK" "$STATE/disk-before-restore.qcow2"
  qemu-img convert -O qcow2 "$STATE/disk-before-restore.qcow2" "$DISK"
  new_id="i-restored-$(date +%s)"
  make_seed "$new_id"

  log "Arrancando la VM 'restaurada' con instance-id $new_id..."
  start_vm
  wait_ssh
  wait_provision
  pw_after="$(vm_ssh 'sudo sha256sum /home/pzserver/pzsvrtool/.admin_password /home/pzserver/pzsvrtool/.join_password /home/pzserver/pzsvrtool/config-applied.json')"

  expect "instance-id nuevo ($old_id -> $new_id)" vm_ssh "[ \"\$(cloud-init query instance_id)\" = $new_id ]"
  expect "user_data volvió a verificar la revisión fija" vm_ssh "[ \"\$(sudo grep -c 'revisión verificada' /var/log/cloud-init-output.log)\" -gt $resets_before ]"
  expect "los datos del disco siguen ahí" vm_ssh "[ \"\$(sudo cat /home/pzserver/restore-marker)\" = $marker ]"
  expect "la partida guardada sigue ahí" vm_ssh "sudo test -d /home/pzserver/Zomboid/Saves/Multiplayer/$PZ_SERVER_NAME"
  expect "las contraseñas y la configuración aplicada no cambiaron" test "$pw_before" = "$pw_after"
  expect "el juego vuelve a correr" wait_game
  expect "servicio activo" svc "is-active --quiet pzsvrtool@$PZ_SERVER_NAME.service"
  finish "restore-test"
}

# Corre script/destroy-and-backup.sh con SSH real contra la VM y aws/terraform
# simulados (tests/script/bin): verifica la detención antes del snapshot.
cmd_backup_test() {
  running || die "la VM no está corriendo"
  FAILS=0
  local rc=0
  ops_env
  wait_game || die "el juego no está corriendo antes del backup"

  env "${OPS_ENV[@]}" "$REPO/script/destroy-and-backup.sh" || rc=$?

  expect "el script terminó con éxito" test "$rc" -eq 0
  expect "no queda proceso ProjectZomboid" vm_ssh '! pgrep -u pzserver -f ProjectZomboid >/dev/null'
  expect "snapshot (simulado) después de detener" grep -q "ec2 create-snapshot" "$STUB_LOG"
  expect "destroy (simulado) invocado" grep -q "destroy -auto-approve" "$STUB_LOG"

  log "Volviendo a iniciar el servidor con systemctl --user start (comando documentado)..."
  svc "start pzsvrtool@$PZ_SERVER_NAME.service" || true
  expect "el juego vuelve a iniciar con systemctl --user start" wait_game
  rm -rf "$OPS_BIN"
  finish "backup-test"
}

cmd_down() {
  stop_vm
  stop_git
  log "VM apagada (el disco se conserva; 'up' la vuelve a arrancar)."
}

cmd_clean() {
  stop_vm
  stop_git
  rm -rf "$STATE/git" "$STATE/git-http.log"
  rm -f "$DISK" "$STATE/disk-before-restore.qcow2" "$SEED" "$STATE/user-data" "$STATE/meta-data" \
    "$STATE/user_data.sh" "$KEY" "$KEY.pub" "$STATE/console.log"
  log "Discos, seed y claves borrados (la imagen base se conserva)."
}

case "${1:-}" in
  up) cmd_up ;;
  ssh) shift; vm_ssh "$@" ;;
  wait) wait_ssh; wait_provision ;;
  check) cmd_check ;;
  config-test) cmd_config_test ;;
  reboot-test) cmd_reboot_test ;;
  restore-test) cmd_restore_test ;;
  backup-test) cmd_backup_test ;;
  down) cmd_down ;;
  clean) cmd_clean ;;
  *) echo "uso: $0 up|ssh [cmd]|wait|check|config-test|reboot-test|restore-test|backup-test|down|clean" >&2; exit 2 ;;
esac
