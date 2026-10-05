#!/bin/bash
# Obtiene la revisión exacta de este repo y corre el playbook en la propia instancia.
# user_data lo instala en /usr/local/sbin/pz-provision y lo ejecuta en el primer arranque
# de cada instancia (nueva o restaurada); script/pz-ctl.sh provision lo vuelve a correr.
#
# Uso: pz-provision [--commit <sha>] [-- <args extra de ansible-playbook>]
#   --commit fija otra revisión y, si el playbook termina bien, la registra en el .env.
#
# Configuración: /etc/pz-provision.env (lo escribe user_data a partir de Terraform).
# Nunca cae en silencio a otra revisión: si el commit no existe o HEAD no coincide, aborta.
set -euo pipefail

ENV_FILE="${PZ_PROVISION_ENV:-/etc/pz-provision.env}"
STATE_FILE="${PZ_PROVISION_STATE:-/var/lib/pz-provision/revision}"
RUN_AS="${RUN_AS:-ubuntu}"
ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-ansible-playbook}"

log() { printf 'pz-provision: %s\n' "$*"; }
die() { printf 'pz-provision: ERROR: %s\n' "$*" >&2; exit 1; }

[ -r "$ENV_FILE" ] || die "no se puede leer $ENV_FILE"
# shellcheck source=/dev/null
. "$ENV_FILE"

new_commit=""
extra_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --commit) new_commit="${2:-}"; shift 2 || die "--commit necesita un SHA" ;;
    --) shift; extra_args=("$@"); break ;;
    *) die "argumento desconocido: $1" ;;
  esac
done

if [ -n "$new_commit" ]; then
  REPO_COMMIT="$new_commit"
  REPO_FOLLOW_BRANCH=false
fi

# Git y Ansible corren como RUN_AS (git rechaza repos de otro usuario: "dubious ownership").
as_user() {
  if [ "$(id -un)" = "$RUN_AS" ]; then
    "$@"
  else
    runuser -u "$RUN_AS" -- env HOME="$(getent passwd "$RUN_AS" | cut -d: -f6)" "$@"
  fi
}
git_repo() { as_user git -C "$REPO_DIR" "$@"; }

if [ "$REPO_FOLLOW_BRANCH" = "true" ]; then
  [ -z "$REPO_COMMIT" ] || die "REPO_COMMIT y REPO_FOLLOW_BRANCH=true son excluyentes"
  log "MODO DE PRUEBA MUTABLE: se sigue la punta de la rama $REPO_BRANCH"
elif ! [[ "$REPO_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  die "REPO_COMMIT ('$REPO_COMMIT') no es un SHA completo de 40 caracteres; no se usa ninguna rama por defecto"
fi

if [ -d "$REPO_DIR/.git" ]; then
  # Disco restaurado o reaprovisionamiento: el checkout ya existe.
  git_repo remote set-url origin "$REPO_URL"
else
  install -d -o "$RUN_AS" -g "$RUN_AS" "$REPO_DIR"
  as_user git clone --quiet --no-checkout "$REPO_URL" "$REPO_DIR"
fi
git_repo fetch --quiet origin "+refs/heads/$REPO_BRANCH:refs/remotes/origin/$REPO_BRANCH" \
  || die "no se pudo obtener la rama $REPO_BRANCH de $REPO_URL"

if [ "$REPO_FOLLOW_BRANCH" = "true" ]; then
  target="$(git_repo rev-parse "refs/remotes/origin/$REPO_BRANCH^{commit}")"
  mode="follow:$REPO_BRANCH"
else
  target="$REPO_COMMIT"
  if ! git_repo cat-file -e "$target^{commit}" 2>/dev/null; then
    # Fuera de la historia de la rama: GitHub permite pedir un commit alcanzable por SHA.
    git_repo fetch --quiet origin "$target" 2>/dev/null || true
  fi
  git_repo cat-file -e "$target^{commit}" 2>/dev/null \
    || die "el commit $target no existe en $REPO_URL; se aborta sin usar otra revisión"
  mode="pinned"
fi

git_repo checkout --quiet --force --detach "$target"
head="$(git_repo rev-parse HEAD)"
[ "$head" = "$target" ] || die "HEAD ($head) no coincide con la revisión pedida ($target)"
log "revisión verificada: $head ($mode)"

cd "$REPO_DIR/playbook"
as_user "$ANSIBLE_PLAYBOOK" -i inventory.ini project-zomboid-server-install.yml \
  -e "pz_server_name=$PZ_SERVER_NAME" \
  -e "pz_java_xmx_mb=$PZ_JAVA_XMX_MB" \
  -e "pz_host_overhead_mb=$PZ_HOST_OVERHEAD_MB" \
  -e "pz_wait_for_config=$PZ_WAIT_FOR_CONFIG" \
  ${extra_args[@]+"${extra_args[@]}"}

if [ -n "$new_commit" ]; then
  sed -i -e "s/^REPO_COMMIT=.*/REPO_COMMIT=$new_commit/" -e "s/^REPO_FOLLOW_BRANCH=.*/REPO_FOLLOW_BRANCH=false/" "$ENV_FILE"
fi
install -d "$(dirname "$STATE_FILE")"
printf 'commit=%s\nmode=%s\napplied_at=%s\n' "$head" "$mode" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_FILE"
log "aprovisionamiento completo en $head"
