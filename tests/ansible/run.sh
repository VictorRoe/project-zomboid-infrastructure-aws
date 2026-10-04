#!/bin/bash
# Offline tests for the playbook's admin password handling.
# Checks are single-quoted on purpose: check() evals them after each run.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAY="$HERE/test_admin_password.yml"
PASS=0
FAIL=0

# run_case <name> <home> [extra ansible args...]
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
    echo "FAIL [$CASE] $1"
    printf '%s\n' "$OUT" | sed 's/^/    | /'
  fi
}

mode_of() { stat -c '%a' "$1"; }

for weak in test Test PASSWORD changeme CHANGE_ME_USE_ANSIBLE_VAULT Short1 'abcdefgh=ijklmn' 'abcdefgh ijklmn'; do
  H="$(mktemp -d)"
  run_case "rejects '$weak'" "$H" -e "pz_admin_password='$weak'"
  check "fails" '[ "$RC" -ne 0 ]'
  check "explains the rule" 'grep -q "at least 12 characters" <<<"$OUT"'
  check "writes nothing" '[ ! -e "$PWFILE" ]'
done

H="$(mktemp -d)"
STRONG="Str0ngPassw0rd16"
run_case "accepts strong password" "$H" -e "pz_admin_password=$STRONG"
check "passes" '[ "$RC" -eq 0 ]'
check "stores it" '[ "$(cat "$PWFILE")" = "$STRONG" ]'
check "mode 0600" '[ "$(mode_of "$PWFILE")" = 600 ]'
check "value not in output" '! grep -qF "$STRONG" <<<"$OUT"'

H="$(mktemp -d)"
run_case "generates when empty" "$H"
GEN="$(cat "$PWFILE" 2>/dev/null)"
check "passes" '[ "$RC" -eq 0 ]'
check "random alphanumeric >= 24 chars" '[[ "$GEN" =~ ^[A-Za-z0-9]{24,}$ ]]'
check "mode 0600" '[ "$(mode_of "$PWFILE")" = 600 ]'
check "used as effective password" 'grep -q "EFFECTIVE_LEN=${#GEN}" <<<"$OUT"'
check "value not in output" '! grep -qF "$GEN" <<<"$OUT"'

run_case "reuses generated password" "$H"
check "passes" '[ "$RC" -eq 0 ]'
check "unchanged" '[ "$(cat "$PWFILE")" = "$GEN" ]'

H2="$(mktemp -d)"
run_case "default is not 'test'" "$H2"
check "generated value is not a denylisted default" '[ "$(cat "$PWFILE")" != test ]'

echo "ansible tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
