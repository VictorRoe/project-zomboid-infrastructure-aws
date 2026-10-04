# Decision Log

Newest entries go at the bottom. Each entry records what was decided, why, and the consequences. The current state lives in [spec.md](spec.md).

## Before 2026-10-04: Existing design (taken from the code)

**D1. One EC2 instance with a single root disk holds everything.** This is simple and cheap for a small group. Consequence: a backup means snapshotting the whole root disk, and world data can't be separated from the OS.

**D2. The instance configures itself (cloud-init clones the repo, then Ansible runs locally).** No SSH access or Ansible controller is needed. Consequence: the playbook comes from GitHub `main`, so unpushed changes never deploy.

**D3. The game is managed by pzsvrtool (pinned 1.7.3) as a systemd user service with linger.** pzsvrtool provides tmux sessions, countdowns, backups and the install workflow. Consequences: every `systemctl --user` call needs the user bus environment, and the host-level `TimeoutStopSec=20m` gives the game time to save on shutdown.

**D4. Game updates happen only inside a time window, with a backup first and a recovery restart.** Players aren't kicked at peak hours, and a failed update doesn't leave the server down. Consequence: updates can be delayed by up to a day.

**D5. Destroy when idle and keep a snapshot.** This saves EC2 cost between play sessions. Consequence: restore is required for continuity, but it isn't wired yet ([#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)).

**D6. The Java heap stays at the game default; extra headroom comes from swap and VM RAM.** Keeps the setup close to upstream. Consequence: the instance needs at least about 7.5 GB RAM (asserted).

## 2026-10-04: Documentation and fix plan

**D7. Documentation lives in `docs/`; only README, CLAUDE.md and CHANGELOG.md stay at the root.** Every change updates [spec.md](spec.md), adds an entry here, and adds a [CHANGELOG](../CHANGELOG.md) entry.

**D8. Issues #1–#5 are fixed as OpenSpec changes on stacked branches**, in this order: AMI (#4) → restore (#1) → SSH (#5) → backup config (#2) → admin password (#3). The fixes touch the same files, so stacking avoids merge conflicts. Consequence: merge the branches in order.

**D9. All tests run offline against mocks.** Terraform uses `terraform test` with `mock_provider`, Ansible runs on localhost, and the script runs with stubbed `aws`/`ssh`/`terraform`. Reason: no AWS spend or credentials during development. Consequence: real-AWS behavior (AMI filters, booting a restored image) still needs a manual check on the first real deploy.

**D10. The AMI is resolved per region, and image drift is ignored ([#4](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/4)).** A `data "aws_ami"` lookup finds the latest Canonical Ubuntu 24.04 amd64 gp3 image (`ami_id` overrides it). `availability_zone` defaults to `null`, and an explicit AZ must belong to `aws_region`. Why: the hardcoded AMI and AZ only worked in us-east-1. Consequences:
- `lifecycle { ignore_changes = [ami] }` keeps a newer image from replacing the instance and deleting the world disk. Rebuilds are deliberate (`-replace`).
- An existing instance keeps its original image.
- `.terraform.lock.hcl` is now committed.

**D11. Offline test harness.** `make test` runs `terraform test` with `mock_provider "aws"`, `override_data` and the Ansible syntax check. Why: no AWS spend or credentials (D9). Consequence: the real AMI filter is only exercised on the first real apply.

**D12. Restore by registering an image from the root snapshot ([#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)).** On create, `aws_ami.restored` is registered from the latest tagged snapshot (or `restore_snapshot_id`), and the instance boots from it. `restore_from_snapshot = false` opts out. Why: the backup is a full root-disk snapshot, and a root volume can only come from an image. A separate data volume would need a migration. Consequences:
- Restore applies only on create (D10's `ignore_changes`), so a live server is never rolled back.
- If a newer snapshot appears while the server runs, the next apply re-registers the image but leaves the instance alone.
- Snapshots that aren't `completed` are rejected.
- Destroy deregisters the image but keeps the snapshots.
- The boot mode is set to `uefi-preferred` without testing on real AWS. Check it on the first real restore.

**D13. The boot script is idempotent and lives in a template.** `user_data` moved to `terraform/templates/user_data.sh.tftpl`. When the checkout exists, it runs `git fetch`/`reset` as `ubuntu`. Why: cloud-init re-runs `user_data` on a restored disk, and root-run git rejects a repo owned by `ubuntu`. Consequence: local changes on the server's checkout are discarded at boot. `make user-data-check` validates the rendered script.

**D14. Optional SSH key pair, and no snapshot of a running server ([#5](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/5)).** Either `ssh_public_key` (creates key pair `pz-server`) or `ssh_key_name` can be set, never both. `ssh_allowed_cidrs` limits port 22. The backup script stops the service with the user bus environment, waits for the process to exit, and otherwise aborts before snapshotting. `FORCE_SNAPSHOT=1` is the escape hatch. Why: the instance had no key, the masked SSH failure snapshotted a live server, and `sudo -iu … systemctl --user` can't reach the user bus anyway. Consequences:
- **Behavior change:** backups now fail loudly instead of continuing.
- Host keys aren't pinned, because cloud-init regenerates them on every instance.
- SSM Session Manager is a possible follow-up; it needs an IAM role.

**D15. Script tests use PATH stubs rather than bats.** `tests/script/bin/{aws,ssh,terraform}` record their calls and follow `STUB_*` variables. Why: no extra dependency, and nothing touches AWS. Consequence: the stubs must follow any new CLI calls the script makes.

**D16. Terraform outputs are the single source of configuration for the backup ([#2](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/2)).** The script reads `backup_bucket_name`, `aws_region`, `pz_server_name`, `public_ip` and `root_volume_id` via `terraform -chdir`, with env overrides, and fails fast on missing values. `pz_server_name` also reaches the playbook through `user_data`. Why: the bucket, region and service name differed between Terraform and the script, the script only worked from `terraform/`, and a tag lookup could pick a stale volume. Consequences:
- Existing users must set `s3_bucket_name` to the bucket they actually use.
- A globally exported `AWS_REGION` overrides the stack's region in the script.
- The bucket stays unmanaged, because the script's own `terraform destroy` would delete it.

**D17. No default admin password; generate one on the host and keep it ([#3](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/3)).** If `pz_admin_password` is empty, which is the new default, a random 32-character alphanumeric password is generated and stored in `~pzserver/pzsvrtool/.admin_password` (0600). It is reused on later runs and survives a restore. A supplied password must be at least 12 characters, not denylisted, and free of whitespace and `=`. Why: unattended runs gave every public server the password `test`. Passing a password through Terraform or `user_data` would leak it into state and instance metadata. Consequences:
- Operators read the password over SSH.
- Changing the password after PZ has created the admin account may not take effect (the account is stored in PZ's database).
- The validation assert uses `quiet` instead of `no_log`, so its error message is visible.

**D18. Playbook defaults moved to `playbook/vars/main.yml`, and validation and password logic to `playbook/tasks/`.** Why: the test playbook (`tests/ansible/`) loads the same defaults and tasks without root or a real host. Consequence: `vars_files` has the same precedence as the old inline `vars`, and `--extra-vars` still wins.

**D19. OpenSpec lives in the repo, and the fixes ship as one PR.** `openspec/` moved from the parent working directory into the repo: main specs in `openspec/specs/`, the six archived changes in `openspec/changes/archive/2026-10-04-*`. The stacked branches (D8) are delivered as a single PR, `release/fix-issues-1-5`. Why: the maintainer asked for decisions, changes, specs and the changelog to be merged together, and specs should be version-controlled next to the code they describe. Consequence: every future change adds its OpenSpec artifacts to the PR.
