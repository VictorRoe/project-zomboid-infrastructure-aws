# Flows

Sequences that span several files. Components are described in [architecture.md](architecture.md).

## 1. Provisioning (`terraform apply`)

1. Terraform resolves the Ubuntu 24.04 AMI for `aws_region` (or uses `ami_id`), then creates `pz-server-sg` and `PZ-Server-Instance` (30 GB gp3 root). On later applies, image changes are ignored, so the instance is never replaced implicitly.
2. cloud-init runs `user_data` as root: installs Ansible from its PPA, clones the GitHub repo into `/home/ubuntu/repo`, and runs the playbook as `ubuntu` against `localhost` with `-e pz_server_name=<var>`.
3. The playbook:
   1. Pre-tasks assert Debian x86_64, at least 2 vCPU and about 7.5 GB RAM, then validate the variables (`tasks/validate.yml`). A supplied admin password must pass the strength rules.
   2. It installs packages, creates `pzserver`, and creates and enables the swap file.
   3. It enables linger, gives the user manager `TimeoutStopSec=20m`, and installs pzsvrtool (pinned `.deb`).
   4. It resolves the admin password (`tasks/admin_password.yml`): a supplied one is stored; otherwise the stored one is reused, or a random one is generated and stored in `.admin_password` (0600). Then it writes `pzsvrtool.config` and installs the game with `pzsvrtool install`. If `start-server.sh` is still missing, it falls back to SteamCMD directly.
   5. It enables and starts `pzsvrtool@<name>.service`, then waits for the `ProjectZomboid` process.
   6. It installs the auto-update script, service and timer.
   7. It sets up UFW: SSH first, then the game UDP ports, then enables the firewall.
   8. It checks that the service is enabled and linger is on.
4. `terraform output public_ip` gives the address players use (UDP 16261).

## 2. Automatic game update (`pz-auto-update.timer`)

The timer fires 10 minutes after boot, then every `pz_update_check_minutes`. The script:

1. Takes a `flock`. It exits quietly if the time is outside the update window (crossing midnight is supported).
2. Compares the installed Steam `buildid` (app manifest) with the remote build for the branch (`app_info_print`).
3. If they differ, and no countdown or boot is in progress:
   1. Messages players and runs `pzsvrtool quit --time N`.
   2. Waits for the process and service to stop.
   3. Runs `pzsvrtool backupnow`, then reinstalls.
   4. Verifies the new build and starts the server again.
4. An ERR trap restarts the server if the update fails after shutdown.

## 3. Backup and destroy (`script/destroy-and-backup.sh`)

Can be run from any directory.

1. Reads `backup_bucket_name`, `aws_region`, `pz_server_name`, `public_ip` and `root_volume_id` with `terraform -chdir=<repo>/terraform output`. `S3_BUCKET`, `AWS_REGION` and `PZ_SERVER_NAME` override the first three. If any value is empty, it exits before touching anything.
2. Stops the server over SSH (`SSH_KEY` optional):
   1. Runs `systemctl --user stop pzsvrtool@<pz_server_name>.service` as `pzserver`, with the user bus environment set on the server side.
   2. Polls `pgrep ProjectZomboid` until the process is gone (`STOP_TIMEOUT`, default 600 s).
   3. If SSH fails, the stop fails or the timeout passes, the script **aborts with exit 1**, before any snapshot or destroy. `FORCE_SNAPSHOT=1` continues anyway with a warning.
3. Creates an EBS snapshot tagged `pz-world-data-snapshot` and waits for it to complete.
4. Archives `s3://<bucket>/latest/` to `archive/<date>/` and uploads the snapshot ID (from a temp file) to `latest/snapshot_meta.txt`.
5. Runs `terraform destroy -auto-approve`, which deletes the instance and its disk. The snapshot remains.

## 4. Restore (`terraform apply` after a destroy)

1. Terraform picks the restore source: `restore_snapshot_id` if set, otherwise the latest owned snapshot tagged `pz-world-data-snapshot`. If `restore_from_snapshot = false`, there is no restore.
2. It reads that snapshot. A precondition fails the run if the snapshot isn't `completed`.
3. It registers the image `pz-restore-<snap>` (`/dev/sda1`, hvm, ENA, `uefi-preferred`, gp3, size `max(30, snapshot)`).
4. The instance boots from that image, so world saves, the pzsvrtool config and the game install come back as they were.
5. cloud-init runs `user_data` again (new instance ID). The repo already exists, so it runs `git fetch` and `reset --hard origin/main` as `ubuntu` instead of cloning. The playbook then re-runs idempotently: the game isn't reinstalled because `start-server.sh` exists.
6. The `restored_from_snapshot_id` output shows the snapshot used (empty means a fresh install).

Restore only happens when the instance is **created**. On a running server, a newer snapshot doesn't trigger a replacement because `ami` changes are ignored. `terraform destroy` deregisters the restore image; the snapshots stay.
