# Architecture

How the pieces of this repo fit together. Current values live in [spec.md](spec.md); the reasons behind them are in [decisions.md](decisions.md). Step-by-step sequences are in [flows.md](flows.md).

## Components

| Layer | Where | Responsibility |
|---|---|---|
| Terraform | `terraform/` | AWS resources: one security group, one EC2 instance with a single gp3 root disk |
| Bootstrap | `terraform/templates/user_data.sh.tftpl` | Installs Ansible, clones (or updates, on a restored disk) this repo from GitHub, runs the playbook on the instance itself |
| Ansible | `playbook/` | Host configuration: `pzserver` user, swap, pzsvrtool, game install, systemd user services, auto-update timer, UFW |
| Backup/teardown | `script/destroy-and-backup.sh` | Runs on the operator's machine: stop server → snapshot root disk → record in S3 → `terraform destroy` |

There is no remote state, CI, or image pipeline. Terraform state is local to the operator's checkout.

## Diagram

```
 Operator machine                           AWS (aws_region)
┌──────────────────────┐        ┌──────────────────────────────────────────────┐
│ terraform apply      │──────▶ │ Security group pz-server-sg                  │
│                      │        │  UDP 16261-16262, 8766 · TCP 22 (ssh CIDRs)  │
│ destroy-and-backup.sh│        │                                              │
│  ├─ terraform output │        │ EC2 PZ-Server-Instance (Ubuntu, t3.large)    │
│  ├─ ssh ubuntu@ip ───┼──────▶ │  root gp3 30 GB, tag pz-world-data-root      │
│  ├─ aws ec2 snapshot─┼──────▶ │   └─ cloud-init user_data                    │
│  ├─ aws s3 cp ───────┼──┐     │       └─ git clone GitHub repo               │
│  └─ terraform destroy│  │     │           └─ ansible-playbook (localhost)    │
└──────────────────────┘  │     │                                              │
                          │     │ EBS snapshots tag pz-world-data-snapshot     │
                          └───▶ │ S3 bucket (external, not managed here)       │
                                └──────────────────────────────────────────────┘
```

## On-host layout (after the playbook)

```
/home/pzserver/
├── pzsvrtool/
│   ├── pzsvrtool.config          # server name, admin, backup settings (0600)
│   └── pz-auto-update.sh         # update checker (run by the user timer)
├── pzserver/                     # game install (SteamCMD app 380870)
├── Steam/steamcmd.sh
└── .config/systemd/user/
    ├── pzsvrtool@<name>.service.d/keepalive.conf
    ├── pz-auto-update.service
    └── pz-auto-update.timer
/etc/systemd/system/user@<uid>.service.d/pzsvrtool.conf   # TimeoutStopSec=20m
/swapfile                                                 # 2 GB
```

The game runs as the **systemd user service** `pzsvrtool@<name>.service` of `pzserver`, kept alive at boot by **linger**. Any `systemctl --user` call from another account needs `XDG_RUNTIME_DIR=/run/user/<uid>` and the user D-Bus address.

## Coupling points

- **Configuration** flows one way: Terraform variables → outputs → backup script, and → `user_data` → playbook (`pz_server_name`). Don't hardcode these values elsewhere.
- **Ports** are declared twice: in the security group (`terraform/main.tf`) and in UFW (`pz_udp_ports` in the playbook). Keep them identical.
- **Playbook delivery** is a `git clone` from GitHub at boot, so playbook changes only reach new instances after they are pushed to the default branch.
- **Snapshot tag** `pz-world-data-snapshot` links the backup script (writer) and `main.tf` (reader, registers `aws_ami.restored` from it).

## Known issues (as of 2026-10-04)

| Issue | Summary |
|---|---|
| ~~[#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)~~ | Fixed: the instance is restored from the latest snapshot on create (D12) |
| ~~[#2](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/2)~~ | Fixed: the script reads its configuration from Terraform outputs (D16) |
| [#3](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/3) | Default admin password `test` passes validation |
| ~~[#4](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/4)~~ | Fixed: the AMI is resolved per region (D10) |
| ~~[#5](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/5)~~ | Fixed: optional key pair; the backup aborts unless the stop is confirmed (D14) |
