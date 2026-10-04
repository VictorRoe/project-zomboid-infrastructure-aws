# Proposal

## Why

The playbook defaults `pz_admin_password: "test"` and its assert only rejects `CHANGE_ME_USE_ANSIBLE_VAULT`. Because EC2 `user_data` runs the playbook unattended with no extra vars, every provisioned server gets root-admin password `test` on a public IP (VictorRoe/project-zomboid-infrastructure-aws#3).

## What Changes

- **BREAKING:** remove the `"test"` default. If no password is supplied, the playbook generates a strong random one on the host, stores it in `~pzserver/pzsvrtool/.admin_password` (0600, owner `pzserver`) and reuses it on every later run (including after snapshot restore).
- An explicitly supplied password must be ≥ 12 characters, not a known weak value (`test`, `password`, `admin`, `changeme`, the old placeholder), and still contain no whitespace or `=` (pzsvrtool config format).
- Password never passes through Terraform/`user_data` (instance metadata is readable by anyone with `ec2:DescribeInstanceAttribute`).
- Validation and generation moved to included task files so they can be tested offline with `ansible-playbook` against localhost, no root, no AWS.

## Capabilities

### New Capabilities
- `admin-credentials`: how the game server's root admin password is supplied, generated, validated and persisted.

### Modified Capabilities

## Impact

- `playbook/project-zomboid-server-install.yml`, new `playbook/tasks/validate.yml`, `playbook/tasks/admin_password.yml`, `tests/ansible/`, `make ansible-test`.
- Operators retrieve the generated password with `sudo cat /home/pzserver/pzsvrtool/.admin_password` over SSH (enabled by `instance-ssh-access`).
- Stacked on `backup-script-config`.
