# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Infrastructure-as-code to host a Project Zomboid dedicated server on a single AWS EC2 instance. There is no application code, build step, or test suite: the repo is Terraform + one Ansible playbook + one Bash script. Comments and descriptions are mostly in Spanish.

## Commands

Terraform (run from `terraform/`; state is local, no backend configured):

```bash
terraform init
terraform fmt -check && terraform validate
terraform plan
terraform apply
terraform output -raw public_ip
```

Ansible (validate locally without a target host):

```bash
ansible-playbook --syntax-check -i playbook/inventory.ini playbook/project-zomboid-server-install.yml
ansible-lint playbook/project-zomboid-server-install.yml   # if installed
# Override vars instead of editing defaults, e.g. the admin password:
ansible-playbook -i playbook/inventory.ini playbook/project-zomboid-server-install.yml -e pz_admin_password=...
```

Teardown with backup: `script/destroy-and-backup.sh`. It calls `terraform output`/`terraform destroy` against the current directory, so it must be run from `terraform/` (e.g. `../script/destroy-and-backup.sh`).

## Architecture / how the pieces connect

1. **Terraform** (`terraform/main.tf`) creates a security group (UDP 16261-16262, 8766; TCP 22) and one Ubuntu EC2 instance with a 30 GB gp3 root volume tagged `pz-world-data-root`.
2. **EC2 `user_data`** installs Ansible, then `git clone`s this repo **from GitHub (`VictorRoe/project-zomboid-infrastructure-aws`)** and runs the playbook against `localhost`. Consequence: playbook changes only take effect on new instances after they are pushed to that repo's default branch.
3. **Ansible playbook** (`playbook/project-zomboid-server-install.yml`, `inventory.ini` = local connection) configures the host:
   - Creates the `pzserver` user, swap file, and installs the pinned `pzsvrtool` .deb (Lu5ck/pzsvrtool), which wraps SteamCMD (app 380870) and tmux.
   - Runs the server as a **systemd user service** `pzsvrtool@<pz_server_name>.service` under `pzserver` with linger enabled. All `systemctl --user` calls go through `runuser` with explicit `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS`; preserve that pattern when adding tasks.
   - Writes `~pzserver/pzsvrtool/pzsvrtool.config` (no spaces or `=` allowed in the admin password — enforced by a pre-task assert).
   - Installs an embedded `pz-auto-update.sh` plus a user `.service`/`.timer` that polls Steam and only performs updates inside a configured time window (graceful countdown → wait for shutdown → backup → reinstall → verify buildid → restart, with recovery restart on failure).
   - Configures UFW last (SSH allowed before enabling). UFW ports must stay in sync with the Terraform security group.
4. **Backup/restore**: `destroy-and-backup.sh` stops the service over SSH, snapshots the root volume, tags it `pz-world-data-snapshot`, writes the snapshot ID to S3, then `terraform destroy`. `main.tf` looks up the latest snapshot with that tag (`data.aws_ebs_snapshot.latest_zomboid_snapshot`), but **it is not currently wired into the instance**, so a fresh apply does not restore world data.

## Known inconsistencies to be aware of

- `var.s3_bucket_name` (`zomboid-bucket-backup`) is unused; the script hardcodes `S3_BUCKET="tu-bucket-zomboid-backups"`.
- The playbook's default `pz_admin_password` is a placeholder (`"test"`); the assert only rejects `CHANGE_ME_USE_ANSIBLE_VAULT`.
- The AMI ID is hardcoded for `us-east-1`; changing `aws_region` requires changing the AMI.
- No `key_name` is set on the instance, yet the backup script SSHes as `ubuntu`.
- `pz_server_name` is hardcoded as `zomboid` in the backup script's service name.

## Workflow

The parent directory uses OpenSpec (`../openspec/`, `/opsx:*` commands) for spec-driven changes.

## Documentation rules

`docs/` holds architecture, flows, spec (current state), operations and the decision log; only README, CLAUDE.md and CHANGELOG.md live at the root. Every change must update `docs/spec.md` (and `architecture.md`/`flows.md` if affected), append a numbered, dated `D<n>` entry to `docs/decisions.md` (decision, why, consequences), and add an `[Unreleased]` entry to `CHANGELOG.md`.
