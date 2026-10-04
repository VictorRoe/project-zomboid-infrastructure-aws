#!/bin/bash
# Checks are single-quoted on purpose: check() evals them after each run.
# shellcheck disable=SC2016,SC2034
# Offline tests for script/destroy-and-backup.sh: aws, ssh and terraform are
# replaced by stubs in tests/script/bin, so nothing reaches AWS or a server.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../script/destroy-and-backup.sh"
PASS=0
FAIL=0

# run_case <name> [VAR=value ...]: runs the script in a temp dir with stubs.
run_case() {
  CASE="$1"; shift
  STUB_DIR="$(mktemp -d)"
  export STUB_DIR STUB_LOG="$STUB_DIR/calls.log"
  : > "$STUB_LOG"
  (cd "$STUB_DIR" && env PATH="$HERE/bin:$PATH" POLL_INTERVAL=0 "$@" "$SCRIPT") > "$STUB_DIR/out.log" 2>&1
  RC=$?
}

check() {
  if eval "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [$CASE] $1"
    sed 's/^/    | /' "$STUB_LOG" "$STUB_DIR/out.log"
  fi
}

called() { grep -qF -- "$1" "$STUB_LOG"; }

# --- instance-ssh-access (#5) ---

run_case "stop confirmed" STUB_PZ_RUNNING_POLLS=2
check "exits 0" '[ "$RC" -eq 0 ]'
check "stops service with user-bus env, expanded remotely" 'called "sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/\$(id -u pzserver) systemctl --user stop pzsvrtool@"'
check "polls until process gone" '[ "$(grep -c pgrep "$STUB_LOG")" -eq 3 ]'
check "snapshot created" 'called "ec2 create-snapshot"'
check "destroy runs" 'called "terraform destroy -auto-approve"'
check "no host-key pinning" 'called "UserKnownHostsFile=/dev/null"'

run_case "ssh unreachable" STUB_SSH_FAIL=1
check "exits non-zero" '[ "$RC" -ne 0 ]'
check "no snapshot" '! called "create-snapshot"'
check "no destroy" '! called "terraform destroy"'

run_case "process never stops" STUB_PZ_RUNNING_POLLS=999 STOP_TIMEOUT=0
check "exits non-zero" '[ "$RC" -ne 0 ]'
check "no snapshot" '! called "create-snapshot"'
check "no destroy" '! called "terraform destroy"'

run_case "forced" STUB_SSH_FAIL=1 FORCE_SNAPSHOT=1
check "exits 0" '[ "$RC" -eq 0 ]'
check "warns" 'grep -q WARNING "$STUB_DIR/out.log"'
check "snapshot created" 'called "ec2 create-snapshot"'

run_case "ssh key" SSH_KEY=/keys/pz.pem
check "uses identity file" 'called "-i /keys/pz.pem"'

echo "script tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
