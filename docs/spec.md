# Spec

Current target state of the stack. Update this file with every change and record the reason in [decisions.md](decisions.md).

## AWS (Terraform)

| Item | Value |
|---|---|
| Region / AZ | `aws_region` = `us-east-1`; `availability_zone` = `null` (AWS picks one in the region; an explicit AZ must belong to `aws_region`) |
| Instance | `instance_type` = `t3.large`, tag `Name=PZ-Server-Instance` |
| Image | Latest Canonical Ubuntu Server 24.04 LTS amd64 (gp3) in `aws_region`, or `ami_id` if set. AMI changes are ignored on an existing instance (`ignore_changes = [ami]`) |
| Disk | Single root gp3 volume, 30 GB (or snapshot size if larger), `delete_on_termination=true`, tag `Name=pz-world-data-root` |
| Security group | `pz-server-sg`: UDP 16261–16262 and 8766 from `0.0.0.0/0`; TCP 22 from `ssh_allowed_cidrs` (default `0.0.0.0/0`); all egress allowed |
| SSH key | Optional: `ssh_public_key` creates key pair `pz-server`, or `ssh_key_name` uses an existing one (mutually exclusive); none by default |
| Backups | EBS snapshots tagged `pz-world-data-snapshot`; S3 bucket `s3_bucket_name` = `zomboid-bucket-backup`. It must already exist and isn't managed by this stack |
| Restore | On instance creation, if `restore_from_snapshot` (default `true`) and a snapshot exists: register `pz-restore-<snap>` image from the latest tagged snapshot (or `restore_snapshot_id`), boot from it; root size `max(30, snapshot size)`; snapshot must be `completed` |
| Server name | `pz_server_name` = `zomboid` (regex `^[A-Za-z0-9._-]+$`), passed to the playbook via `user_data` (`-e pz_server_name=`) |
| Outputs | `public_ip`, `root_volume_id`, `restored_from_snapshot_id`, `backup_bucket_name`, `aws_region`, `pz_server_name` |
| State | Local, no backend |
| Tooling | Terraform `>= 1.9`, AWS provider `~> 6.0`, lock file committed |

## Tests (offline)

`make test` runs `terraform fmt/validate/test` against a mocked AWS provider and the Ansible syntax check. No AWS credentials or API calls are needed. Suites: `terraform/tests/{ami,restore,ssh,config}.tftest.hcl`; `make script-test` runs `tests/script/run.sh` (backup script with stubbed `aws`/`ssh`/`terraform`) plus shellcheck; `make user-data-check` renders the boot script and runs `bash -n` + shellcheck.

## Backup script

| Item | Value |
|---|---|
| Config | Taken from Terraform outputs (`terraform -chdir=<repo>/terraform`); overridden by `S3_BUCKET`, `AWS_REGION`, `PZ_SERVER_NAME`, `TF_DIR`. Fails before any action if a value is missing |
| Disk | `root_volume_id` output |
| Metadata | `s3://<bucket>/latest/snapshot_meta.txt` (previous `latest/` copied to `archive/<date>/`) |
| Stop | `systemctl --user stop pzsvrtool@<pz_server_name>.service` as `pzserver` with `XDG_RUNTIME_DIR`, then poll until no `ProjectZomboid` process remains |
| Stop timeout | `STOP_TIMEOUT` = 600 s; poll every `POLL_INTERVAL` = 5 s |
| On failure | Abort before the snapshot (exit 1). `FORCE_SNAPSHOT=1` continues with a warning |
| SSH | `ubuntu@<public_ip>`, `SSH_KEY` identity file, `BatchMode`, no host-key pinning |

## Host (Ansible)

| Item | Value |
|---|---|
| OS requirement | Debian family, x86_64, ≥ 2 vCPU, ≥ 7500 MB RAM |
| Service account | `pzserver`, home `/home/pzserver`, linger on |
| pzsvrtool | `1.7.3` (pinned `.deb`) |
| Server name | `pz_server_name` (default `zomboid`; Terraform passes its value) |
| Steam branch | public (`pz_branch: ""`) |
| Admin | `pzadmin` / `test` (see [#3](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/3)) |
| Swap | `/swapfile`, 2 GB |
| Backups (pzsvrtool) | enabled, limit 10; shutdown countdown 5 min |
| Auto-update | enabled; window 03:00–06:00 `America/Argentina/Buenos_Aires`; check every 15 min; 5 min warning; 20 min shutdown timeout |
| Firewall | UFW: TCP 22, UDP 16261, 16262, 8766 |
