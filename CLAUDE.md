# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Infrastructure-as-code to host a Project Zomboid dedicated server on a single AWS EC2 instance. There is no application code or build step: the repo is Terraform + one Ansible playbook + one Bash script, with an offline (mocked) test suite. Comments and descriptions are mostly in Spanish.

## Commands

Terraform (run from `terraform/`; state is local, no backend configured):

```bash
terraform init
terraform fmt -check && terraform validate
terraform plan
terraform apply
terraform output -raw public_ip
```

Offline test suite (no AWS credentials; the provider is mocked). Needs Terraform >= 1.9 (installed at `~/.local/bin/terraform` on this machine):

```bash
make test                                                     # all checks
make tf-test                                                  # init + fmt -check + validate + terraform test
make user-data-check                                          # render EC2 boot script, bash -n + shellcheck
terraform -chdir=terraform test -filter=tests/ami.tftest.hcl  # single suite
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
2. **EC2 `user_data`** (`terraform/templates/user_data.sh.tftpl`) installs Ansible, then clones (or, on a restored disk, fetches/resets as `ubuntu`) this repo **from GitHub (`VictorRoe/project-zomboid-infrastructure-aws`)** and runs the playbook against `localhost`. Consequence: playbook changes only take effect on new instances after they are pushed to that repo's default branch.
3. **Ansible playbook** (`playbook/project-zomboid-server-install.yml`, `inventory.ini` = local connection) configures the host:
   - Creates the `pzserver` user, swap file, and installs the pinned `pzsvrtool` .deb (Lu5ck/pzsvrtool), which wraps SteamCMD (app 380870) and tmux.
   - Runs the server as a **systemd user service** `pzsvrtool@<pz_server_name>.service` under `pzserver` with linger enabled. All `systemctl --user` calls go through `runuser` with explicit `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS`; preserve that pattern when adding tasks.
   - Writes `~pzserver/pzsvrtool/pzsvrtool.config` (no spaces or `=` allowed in the admin password — enforced by a pre-task assert).
   - Installs an embedded `pz-auto-update.sh` plus a user `.service`/`.timer` that polls Steam and only performs updates inside a configured time window (graceful countdown → wait for shutdown → backup → reinstall → verify buildid → restart, with recovery restart on failure).
   - Configures UFW last (SSH allowed before enabling). UFW ports must stay in sync with the Terraform security group.
4. **Backup/restore**: `destroy-and-backup.sh` stops the service over SSH, snapshots the root volume, tags it `pz-world-data-snapshot`, writes the snapshot ID to S3, then `terraform destroy`. On the next create, `main.tf` registers an image (`aws_ami.restored`) from the latest tagged snapshot (or `restore_snapshot_id`) and boots from it; `restore_from_snapshot = false` opts out.

## Invariants

- `aws_instance.pz_server` ignores `ami` changes on purpose: the root disk is the world, so neither a newer Ubuntu image nor a newer snapshot may replace a running server. Never remove that without a backup strategy.
- Terraform tests mock AWS; a mocked `aws_ebs_snapshot_ids` returns no IDs, so tests needing a snapshot must `override_data` every snapshot data source by full address (see `terraform/tests/restore.tftest.hcl`).

## Known inconsistencies to be aware of

- `var.s3_bucket_name` (`zomboid-bucket-backup`) is unused; the script hardcodes `S3_BUCKET="tu-bucket-zomboid-backups"`.
- The playbook's default `pz_admin_password` is a placeholder (`"test"`); the assert only rejects `CHANGE_ME_USE_ANSIBLE_VAULT`.
- No `key_name` is set on the instance, yet the backup script SSHes as `ubuntu`.
- `pz_server_name` is hardcoded as `zomboid` in the backup script's service name.

## Workflow

The parent directory uses OpenSpec (`../openspec/`, `/opsx:*` commands) for spec-driven changes.

## Documentation rules

`docs/` holds architecture, flows, spec (current state), operations and the decision log; only README, CLAUDE.md and CHANGELOG.md live at the root. Every change must update `docs/spec.md` (and `architecture.md`/`flows.md` if affected), append a numbered, dated `D<n>` entry to `docs/decisions.md` (decision, why, consequences), and add an `[Unreleased]` entry to `CHANGELOG.md`.
