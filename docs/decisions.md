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
