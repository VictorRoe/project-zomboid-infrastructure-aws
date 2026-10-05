#!/bin/bash
# Entorno local: VM Ubuntu 24.04 con QEMU/KVM que imita la EC2. Arranca la misma
# imagen cloud que AWS y le pasa por cloud-init (NoCloud) el user_data que
# renderiza Terraform, sin cambios. No usa AWS. Ver docs/operations.md.
#
# Uso: local/vm.sh up|ssh|wait|check|reboot-test|restore-test|backup-test|down|clean
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
TF="${TF:-terraform}"

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

# La VM clona la rama desde GitHub: tiene que estar pusheada.
repo_branch() {
  local branch
  branch="${LOCAL_REPO_BRANCH:-$(git -C "$REPO" rev-parse --abbrev-ref HEAD)}"
  git -C "$REPO" fetch -q origin "$branch" || die "la rama '$branch' no existe en origin; pushearla primero"
  if [ -n "$(git -C "$REPO" log --oneline "origin/$branch..HEAD" 2>/dev/null)" ]; then
    die "hay commits sin pushear en '$branch'; la VM clona desde GitHub"
  fi
  printf '%s' "$branch"
}

render_user_data() {
  local branch="$1"
  "$TF" -chdir="$REPO/terraform" init -backend=false -input=false >/dev/null
  echo 'local.user_data' | "$TF" -chdir="$REPO/terraform" console -var "repo_branch=$branch" \
    | sed '1d;$d' > "$STATE/user_data.sh"
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
  if [ ! -f "$DISK" ]; then
    local branch
    branch="$(repo_branch)"
    log "Rama que va a clonar la VM: $branch"
    render_user_data "$branch"
    qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$DISK" "$DISK_SIZE"
    make_seed "i-local-$(date +%s)"
  fi
  start_vm
  wait_ssh
  wait_provision
  cmd_check
}

cmd_check() {
  FAILS=0
  expect "cloud-init terminó sin errores" vm_ssh 'cloud-init status | grep -q "status: done"'
  expect "servicio habilitado" vm_ssh "[ \"\$($PZ_USER_ENV systemctl --user is-enabled pzsvrtool@$PZ_SERVER_NAME.service)\" = enabled ]"
  expect "servicio activo" svc "is-active --quiet pzsvrtool@$PZ_SERVER_NAME.service"
  expect "proceso ProjectZomboid corriendo" wait_game
  expect "escucha en 16261/udp" vm_ssh 'sudo ss -lunp | grep -q ":16261 "'
  expect "linger activo" vm_ssh '[ "$(loginctl show-user pzserver -p Linger --value)" = yes ]'
  expect "timer de actualización activo" svc "is-active --quiet pz-auto-update.timer"
  expect "contraseña de admin 0600 de pzserver" vm_ssh '[ "$(sudo stat -c "%a %U" /home/pzserver/pzsvrtool/.admin_password)" = "600 pzserver" ]'
  expect "contraseña de admin de 24+ caracteres" vm_ssh '[ "$(sudo cat /home/pzserver/pzsvrtool/.admin_password | wc -c)" -ge 24 ]'
  expect "config de pzsvrtool usa esa contraseña" vm_ssh 'sudo grep -qxF "pzRootAdminPassword=$(sudo cat /home/pzserver/pzsvrtool/.admin_password)" /home/pzserver/pzsvrtool/pzsvrtool.config'
  expect "UFW activo con 16261/udp" vm_ssh 'sudo ufw status | grep -q "16261/udp.*ALLOW"'
  finish "check"
}

cmd_reboot_test() {
  running || die "la VM no está corriendo"
  FAILS=0
  log "Reiniciando la VM..."
  vm_ssh 'sudo systemctl reboot' 2>/dev/null || true
  sleep 15
  wait_ssh
  expect "el juego vuelve a correr solo tras el reinicio" wait_game
  expect "servicio activo tras el reinicio" svc "is-active --quiet pzsvrtool@$PZ_SERVER_NAME.service"
  finish "reboot-test"
}

cmd_restore_test() {
  running || die "la VM no está corriendo"
  FAILS=0
  local marker pw_before pw_after old_id new_id
  marker="restore-$(date +%s)"
  vm_ssh "echo $marker | sudo -u pzserver tee /home/pzserver/restore-marker >/dev/null"
  pw_before="$(vm_ssh 'sudo sha256sum /home/pzserver/pzsvrtool/.admin_password')"
  old_id="$(vm_ssh 'cloud-init query instance_id')"

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
  pw_after="$(vm_ssh 'sudo sha256sum /home/pzserver/pzsvrtool/.admin_password')"

  expect "instance-id nuevo ($old_id -> $new_id)" vm_ssh "[ \"\$(cloud-init query instance_id)\" = $new_id ]"
  expect "user_data actualizó el checkout en lugar de clonar" vm_ssh 'sudo grep -q "HEAD is now at" /var/log/cloud-init-output.log'
  expect "los datos del disco siguen ahí" vm_ssh "[ \"\$(cat /home/pzserver/restore-marker)\" = $marker ]"
  expect "la contraseña de admin no cambió" test "$pw_before" = "$pw_after"
  expect "el juego vuelve a correr" wait_game
  expect "servicio activo" svc "is-active --quiet pzsvrtool@$PZ_SERVER_NAME.service"
  finish "restore-test"
}

# Corre script/destroy-and-backup.sh con SSH real contra la VM y aws/terraform
# simulados (tests/script/bin): verifica la detención antes del snapshot.
cmd_backup_test() {
  running || die "la VM no está corriendo"
  FAILS=0
  local bin rc=0
  bin="$(mktemp -d)"
  ln -s "$REPO/tests/script/bin/aws" "$REPO/tests/script/bin/terraform" "$bin/"
  export STUB_DIR="$bin" STUB_LOG="$bin/calls.log"
  : > "$STUB_LOG"
  wait_game || die "el juego no está corriendo antes del backup"

  env PATH="$bin:$PATH" SSH_PORT="$SSH_PORT" SSH_KEY="$KEY" \
    STUB_TF_OUT_public_ip=127.0.0.1 STUB_TF_OUT_pz_server_name="$PZ_SERVER_NAME" \
    STUB_TF_OUT_aws_region=local STUB_TF_OUT_backup_bucket_name=local-bucket \
    "$REPO/script/destroy-and-backup.sh" || rc=$?

  expect "el script terminó con éxito" test "$rc" -eq 0
  expect "no queda proceso ProjectZomboid" vm_ssh '! pgrep -u pzserver -f ProjectZomboid >/dev/null'
  expect "snapshot (simulado) después de detener" grep -q "ec2 create-snapshot" "$STUB_LOG"
  expect "destroy (simulado) invocado" grep -q "destroy -auto-approve" "$STUB_LOG"

  log "Volviendo a iniciar el servidor con systemctl --user start (comando documentado)..."
  svc "start pzsvrtool@$PZ_SERVER_NAME.service" || true
  expect "el juego vuelve a iniciar con systemctl --user start" wait_game
  rm -rf "$bin"
  finish "backup-test"
}

cmd_down() {
  stop_vm
  log "VM apagada (el disco se conserva; 'up' la vuelve a arrancar)."
}

cmd_clean() {
  stop_vm
  rm -f "$DISK" "$STATE/disk-before-restore.qcow2" "$SEED" "$STATE/user-data" "$STATE/meta-data" \
    "$STATE/user_data.sh" "$KEY" "$KEY.pub" "$STATE/console.log"
  log "Discos, seed y claves borrados (la imagen base se conserva)."
}

case "${1:-}" in
  up) cmd_up ;;
  ssh) shift; vm_ssh "$@" ;;
  wait) wait_ssh; wait_provision ;;
  check) cmd_check ;;
  reboot-test) cmd_reboot_test ;;
  restore-test) cmd_restore_test ;;
  backup-test) cmd_backup_test ;;
  down) cmd_down ;;
  clean) cmd_clean ;;
  *) echo "uso: $0 up|ssh [cmd]|wait|check|reboot-test|restore-test|backup-test|down|clean" >&2; exit 2 ;;
esac
