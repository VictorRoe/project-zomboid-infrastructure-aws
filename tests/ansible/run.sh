#!/bin/bash
# Tests offline del manejo de la contraseña de admin del playbook.
# Los chequeos van entre comillas simples a propósito: check() los evalúa tras cada ejecución.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAY="$HERE/test_admin_password.yml"
PASS=0
FAIL=0

# run_case <nombre> <home> [args extra de ansible...]
run_case() {
  CASE="$1"; HOME_DIR="$2"; shift 2
  PWFILE="$HOME_DIR/pzsvrtool/.admin_password"
  OUT="$(ANSIBLE_NOCOLOR=1 ansible-playbook -i localhost, "$PLAY" \
    -e "pz_user=$(id -un)" -e "pz_home=$HOME_DIR" "$@" 2>&1)"
  RC=$?
}

check() {
  if eval "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FALLA [$CASE] $1"
    printf '%s\n' "$OUT" | sed 's/^/    | /'
  fi
}

mode_of() { stat -c '%a' "$1"; }

for weak in test Test PASSWORD changeme CHANGE_ME_USE_ANSIBLE_VAULT Short1 'abcdefgh=ijklmn' 'abcdefgh ijklmn'; do
  H="$(mktemp -d)"
  run_case "rechaza '$weak'" "$H" -e "pz_admin_password='$weak'"
  check "falla" '[ "$RC" -ne 0 ]'
  check "explica la regla" 'grep -q "al menos 12 caracteres" <<<"$OUT"'
  check "no escribe nada" '[ ! -e "$PWFILE" ]'
done

H="$(mktemp -d)"
STRONG="Str0ngPassw0rd16"
run_case "acepta contraseña fuerte" "$H" -e "pz_admin_password=$STRONG"
check "pasa" '[ "$RC" -eq 0 ]'
check "la guarda" '[ "$(cat "$PWFILE")" = "$STRONG" ]'
check "modo 0600" '[ "$(mode_of "$PWFILE")" = 600 ]'
check "el valor no aparece en la salida" '! grep -qF "$STRONG" <<<"$OUT"'

H="$(mktemp -d)"
run_case "genera si está vacía" "$H"
GEN="$(cat "$PWFILE" 2>/dev/null)"
check "pasa" '[ "$RC" -eq 0 ]'
check "aleatoria alfanumérica >= 24 caracteres" '[[ "$GEN" =~ ^[A-Za-z0-9]{24,}$ ]]'
check "modo 0600" '[ "$(mode_of "$PWFILE")" = 600 ]'
check "se usa como contraseña efectiva" 'grep -q "EFFECTIVE_LEN=${#GEN}" <<<"$OUT"'
check "el valor no aparece en la salida" '! grep -qF "$GEN" <<<"$OUT"'

run_case "reutiliza la contraseña generada" "$H"
check "pasa" '[ "$RC" -eq 0 ]'
check "sin cambios" '[ "$(cat "$PWFILE")" = "$GEN" ]'

H2="$(mktemp -d)"
run_case "el valor por defecto no es 'test'" "$H2"
check "el valor generado no es un débil conocido" '[ "$(cat "$PWFILE")" != test ]'

echo "tests de ansible: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
