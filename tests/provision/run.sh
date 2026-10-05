#!/bin/bash
# Los chequeos van entre comillas simples a propósito: check() los evalúa tras cada ejecución.
# shellcheck disable=SC2016,SC2034
# Tests offline de terraform/templates/pz-provision.sh (#18): repos git locales reales,
# ansible-playbook reemplazado por un stub. Sin red, sin root.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../terraform/templates/pz-provision.sh"
PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)

# Repo de origen: main con A y B; la rama feat con C (fuera de main).
ORIGIN="$WORK/origin"
"${G[@]}" init -q "$ORIGIN"
mkdir -p "$ORIGIN/playbook"
echo a > "$ORIGIN/playbook/version"; "${G[@]}" -C "$ORIGIN" add -A; "${G[@]}" -C "$ORIGIN" commit -qm A
A="$(git -C "$ORIGIN" rev-parse HEAD)"
echo b > "$ORIGIN/playbook/version"; "${G[@]}" -C "$ORIGIN" commit -qam B
B="$(git -C "$ORIGIN" rev-parse HEAD)"
"${G[@]}" -C "$ORIGIN" checkout -qb feat
echo c > "$ORIGIN/playbook/version"; "${G[@]}" -C "$ORIGIN" commit -qam C
C="$(git -C "$ORIGIN" rev-parse HEAD)"
"${G[@]}" -C "$ORIGIN" checkout -q main

# Stub de ansible-playbook: registra args y la versión del checkout; falla con STUB_ANSIBLE_FAIL=1.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/ansible-playbook" <<'STUB'
#!/bin/bash
printf 'ansible-playbook %s | version=%s\n' "$*" "$(cat version)" >> "$STUB_LOG"
[ "${STUB_ANSIBLE_FAIL:-0}" = "1" ] && exit 2
exit 0
STUB
chmod +x "$WORK/bin/ansible-playbook"

# run_case <nombre> <commit> <follow> [args de pz-provision...]; REPO_DIR persiste entre casos con KEEP=1.
run_case() {
  CASE="$1"; local commit="$2" follow="$3"; shift 3
  [ "${KEEP:-0}" = "1" ] || rm -rf "$WORK/checkout"
  ENV_FILE="$WORK/pz-provision.env"
  cat > "$ENV_FILE" <<ENV
REPO_URL=file://$ORIGIN
REPO_BRANCH=main
REPO_COMMIT=$commit
REPO_FOLLOW_BRANCH=$follow
REPO_DIR=$WORK/checkout
PZ_SERVER_NAME=world1
PZ_JAVA_XMX_MB=4096
PZ_HOST_OVERHEAD_MB=3072
PZ_WAIT_FOR_CONFIG=true
ENV
  STUB_LOG="$WORK/calls.log"; : > "$STUB_LOG"; rm -f "$WORK/state"
  OUT="$(env PATH="$WORK/bin:$PATH" STUB_LOG="$STUB_LOG" RUN_AS="$(id -un)" PZ_PROVISION_ENV="$ENV_FILE" \
    PZ_PROVISION_STATE="$WORK/state" STUB_ANSIBLE_FAIL="${STUB_ANSIBLE_FAIL:-0}" bash "$SCRIPT" "$@" 2>&1)"
  RC=$?
}

check() {
  if eval "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FALLA [$CASE] $1"
    printf '%s\n' "$OUT" | sed 's/^/    | /'
    sed 's/^/    | /' "$STUB_LOG"
  fi
}
head_is() { [ "$(git -C "$WORK/checkout" rev-parse HEAD)" = "$1" ]; }
ran() { [ -s "$STUB_LOG" ]; }

run_case "commit fijo (no la punta de main)" "$A" false
check "sale con 0" '[ "$RC" -eq 0 ]'
check "HEAD es el commit pedido" 'head_is "$A"'
check "el playbook corre sobre esa revisión" 'grep -q "version=a" "$STUB_LOG"'
check "pasa las variables de Terraform" 'grep -q "pz_server_name=world1" "$STUB_LOG" && grep -q "pz_java_xmx_mb=4096" "$STUB_LOG" && grep -q "pz_wait_for_config=true" "$STUB_LOG"'
check "registra la revisión aplicada" 'grep -qx "commit=$A" "$WORK/state" && grep -qx "mode=pinned" "$WORK/state"'

run_case "commit inexistente" 0000000000000000000000000000000000000000 false
check "aborta" '[ "$RC" -ne 0 ] && grep -q "no existe" <<<"$OUT"'
check "sin playbook ni registro" '! ran && [ ! -e "$WORK/state" ]'

run_case "SHA corto" "${A:0:7}" false
check "aborta sin clonar" '[ "$RC" -ne 0 ] && ! ran && [ ! -d "$WORK/checkout" ]'

run_case "sin commit y sin modo rama" "" false
check "no cae a main en silencio" '[ "$RC" -ne 0 ] && grep -q "no se usa ninguna rama por defecto" <<<"$OUT" && ! ran'

run_case "commit y modo rama a la vez" "$A" true
check "aborta" '[ "$RC" -ne 0 ] && ! ran'

run_case "modo de prueba que sigue la rama" "" true
check "usa la punta de main y lo advierte" '[ "$RC" -eq 0 ] && head_is "$B" && grep -q "MUTABLE" <<<"$OUT" && grep -qx "mode=follow:main" "$WORK/state"'

run_case "commit de otra rama, pedido por SHA" "$C" false
check "lo obtiene por SHA y lo usa" '[ "$RC" -eq 0 ] && head_is "$C" && grep -q "version=c" "$STUB_LOG"'

# Disco restaurado: el checkout existe, en otra revisión y con cambios locales.
run_case "preparar checkout existente" "$B" false
echo local > "$WORK/checkout/playbook/version"
KEEP=1 run_case "checkout existente (restauración)" "$A" false
check "vuelve a la revisión fijada descartando cambios locales" '[ "$RC" -eq 0 ] && head_is "$A" && grep -q "version=a" "$STUB_LOG"'

KEEP=1 run_case "actualización deliberada con --commit" "$A" false --commit "$B"
check "aplica la revisión nueva" '[ "$RC" -eq 0 ] && head_is "$B"'
check "la registra en el .env para próximas ejecuciones" 'grep -qx "REPO_COMMIT=$B" "$ENV_FILE"'

STUB_ANSIBLE_FAIL=1 KEEP=1 run_case "--commit con playbook fallido" "$A" false --commit "$B"
check "sale con error" '[ "$RC" -ne 0 ]'
check "no registra la revisión nueva" 'grep -qx "REPO_COMMIT=$A" "$ENV_FILE" && [ ! -e "$WORK/state" ]'

KEEP=1 run_case "--commit inválido" "$A" false --commit main
check "aborta" '[ "$RC" -ne 0 ] && ! ran'

KEEP=1 run_case "args extra para ansible" "$A" false -- -e pz_join_password_rotate=true
check "se pasan al playbook" '[ "$RC" -eq 0 ] && grep -q "pz_join_password_rotate=true" "$STUB_LOG"'

echo "tests de pz-provision: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
