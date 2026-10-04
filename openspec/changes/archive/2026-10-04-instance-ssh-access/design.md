# Design

## Context

Script runs on the operator's machine using `terraform output`, AWS CLI and SSH. The server runs as a systemd *user* service of `pzserver` (linger enabled); `systemctl --user` needs `XDG_RUNTIME_DIR=/run/user/<uid>`.

## Goals / Non-Goals

**Goals:** working SSH path; no snapshot of a running server by default; testable without AWS or a real host.

**Non-Goals:** SSM Session Manager (would need an IAM instance profile — possible follow-up); changing the backup bucket/region config (handled by `backup-script-config`).

## Decisions

- **Key pair inputs:** `ssh_public_key` → `aws_key_pair.pz[0]` (count-guarded); (static `key_name = "pz-server"`, known at plan time); `local.key_name = length(aws_key_pair.pz) > 0 ? aws_key_pair.pz[0].key_name : (var.ssh_key_name != "" ? var.ssh_key_name : null)` (`coalesce` errors when every argument is null — review finding). Mutual exclusion via a cross-variable `validation` on `ssh_key_name` (Terraform >= 1.9, already required).
- **Remote stop command** (single-quoted so `$(id -u …)` expands on the server, not the operator machine): `sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/$(id -u pzserver) systemctl --user stop pzsvrtool@<name>.service`, then poll `pgrep -u pzserver -f ProjectZomboid` up to `STOP_TIMEOUT` seconds (default 600; the pzsvrtool countdown is 5 min). Server name stays `zomboid` here; parameterized in `backup-script-config`.
- **Failure semantics:** any failure of the stop/verify step → `exit 1` before `create-snapshot`, unless `FORCE_SNAPSHOT=1`.
- **Script testing:** `tests/script/run.sh` puts `tests/script/bin` stubs (`ssh`, `aws`, `terraform`) first on `PATH`; stubs log their argv to a file and behave per env vars (e.g. `STUB_SSH_FAIL=1`). Assertions grep the log (e.g. no `create-snapshot`, no `destroy`). Polling sleep is overridable (`POLL_INTERVAL=0`) to keep tests fast. No bats dependency.

- **SSH options:** `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10`, plus `-i $SSH_KEY` when set. cloud-init regenerates host keys on every new (incl. restored) instance, so a pinned known_hosts entry would break on IP reuse; the target is the IP Terraform just reported.

## Risks / Trade-offs

- [Operators relying on the old "always proceed" behavior] → `FORCE_SNAPSHOT=1` escape hatch, documented.
- [Public key in tfvars] → public keys aren't secret; tfvars are gitignored anyway.
