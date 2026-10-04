#!/bin/bash
# Checks are single-quoted on purpose: check() evals them after each run.
# shellcheck disable=SC2016,SC2034
# Offline tests for script/destroy-and-backup.sh: aws, ssh and terraform are
# replaced by stubs in tests/script/bin, so nothing reaches AWS or a server.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SCRIPT="$HERE/../../script/destroy-and-backup.sh"
PASS=0
FAIL=0

# run_case <name> [VAR=value ...]: runs the script in a temp dir with stubs.
run_case() {
  CASE="$1"; shift
  STUB_DIR="$(mktemp -d)"
  export STUB_DIR STUB_LOG="$STUB_DIR/calls.log"
  : > "$STUB_LOG"
  (cd "${CASE_CWD:-$STUB_DIR}" && env PATH="$HERE/bin:$PATH" POLL_INTERVAL=0 "$@" "$SCRIPT") > "$STUB_DIR/out.log" 2>&1
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
check "destroy runs" 'called "terraform -chdir=$REPO/terraform destroy -auto-approve"'
check "no host-key pinning" 'called "UserKnownHostsFile=/dev/null"'

run_case "ssh unreachable" STUB_SSH_FAIL=1
check "exits non-zero" '[ "$RC" -ne 0 ]'
check "no snapshot" '! called "create-snapshot"'
check "no destroy" '! called "destroy"'

run_case "process never stops" STUB_PZ_RUNNING_POLLS=999 STOP_TIMEOUT=0
check "exits non-zero" '[ "$RC" -ne 0 ]'
check "no snapshot" '! called "create-snapshot"'
check "no destroy" '! called "destroy"'

run_case "forced" STUB_SSH_FAIL=1 FORCE_SNAPSHOT=1
check "exits 0" '[ "$RC" -eq 0 ]'
check "warns" 'grep -q WARNING "$STUB_DIR/out.log"'
check "snapshot created" 'called "ec2 create-snapshot"'

run_case "ssh key" SSH_KEY=/keys/pz.pem
check "uses identity file" 'called "-i /keys/pz.pem"'

# --- backup-script-config (#2) ---

run_case "config from terraform outputs"
check "exits 0" '[ "$RC" -eq 0 ]'
check "service from pz_server_name output" 'called "systemctl --user stop pzsvrtool@world1.service"'
check "region from aws_region output" 'called "ec2 create-snapshot --volume-id vol-output" && called "--region sa-east-1"'
check "bucket from backup_bucket_name output" 'called "s3://bucket-from-output/latest/snapshot_meta.txt"'
check "volume from root_volume_id, not a tag query" '! called "describe-volumes"'
check "terraform targets repo terraform/ from any cwd" '! grep -q "^terraform output" "$STUB_LOG" && called "terraform -chdir=$REPO/terraform output -raw public_ip"'
check "no metadata file left in cwd" '[ ! -e "$STUB_DIR/snapshot_meta.txt" ]'

run_case "env overrides" S3_BUCKET=override AWS_REGION=eu-west-1 PZ_SERVER_NAME=other
check "bucket override" 'called "s3://override/latest/snapshot_meta.txt"'
check "region override" 'called "--region eu-west-1" && ! called "--region sa-east-1"'
check "server name override" 'called "pzsvrtool@other.service"'

for missing in backup_bucket_name aws_region pz_server_name public_ip root_volume_id; do
  run_case "missing $missing" STUB_TF_MISSING="$missing"
  check "exits non-zero" '[ "$RC" -ne 0 ]'
  check "no SSH or AWS calls" '! called "ssh " && ! called "aws "'
  check "names the missing value" 'grep -q "no se pudo resolver" "$STUB_DIR/out.log"'
done

CASE_CWD="$REPO" run_case "run from repo root"
check "exits 0" '[ "$RC" -eq 0 ]'
check "terraform targets terraform/" 'called "terraform -chdir=$REPO/terraform destroy -auto-approve"'

echo "script tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
