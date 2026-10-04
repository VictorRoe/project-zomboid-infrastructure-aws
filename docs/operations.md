# Operations

Day-to-day commands. Values are listed in [spec.md](spec.md).

## Deploy and tear down

SSH access, which the backup script needs, is set in `terraform.tfvars` (gitignored):

```hcl
s3_bucket_name    = "my-existing-bucket"            # must exist; not created by this stack
ssh_public_key    = "ssh-ed25519 AAAA... you@host"   # or: ssh_key_name = "existing-pair"
ssh_allowed_cidrs = ["203.0.113.4/32"]
```

```bash
cd terraform
terraform init
terraform apply                       # creates the server and bootstraps it via user_data
terraform output -raw public_ip       # players connect to <ip>:16261
../script/destroy-and-backup.sh       # stop, snapshot, S3 metadata, terraform destroy (any cwd)
SSH_KEY=~/.ssh/pz ../script/destroy-and-backup.sh     # with a specific identity file
S3_BUCKET=other-bucket ../script/destroy-and-backup.sh # override an output (also AWS_REGION, PZ_SERVER_NAME, TF_DIR)
FORCE_SNAPSHOT=1 ../script/destroy-and-backup.sh      # last resort: snapshot even if the stop can't be confirmed
```

## On the server

```bash
sudo -iu pzserver pzsvrtool console
sudo -iu pzserver systemctl --user status pzsvrtool@zomboid.service
sudo -iu pzserver systemctl --user list-timers pz-auto-update.timer
sudo -iu pzserver journalctl --user -u pz-auto-update.service
sudo tail -f /var/log/cloud-init-output.log    # first-boot provisioning log
```

## Restore

```bash
terraform apply                                          # restores from the latest pz-world-data-snapshot, if any
terraform apply -var restore_snapshot_id=snap-0abc...    # restore a specific snapshot
terraform apply -var restore_from_snapshot=false         # fresh world, ignore snapshots
terraform output restored_from_snapshot_id
```

Old snapshots are kept and still cost money. Delete the ones you no longer need with `aws ec2 delete-snapshot`.

## Rebuild on a newer image

Image changes are ignored on a running instance. To rebuild deliberately, take a backup first, because the root disk (the world) is deleted:

```bash
terraform apply -replace=aws_instance.pz_server
```

## Local checks (no AWS)

```bash
make test             # everything below
make tf-test          # terraform init/fmt/validate/test (mocked AWS provider)
make ansible-check    # playbook syntax check
make user-data-check  # render the EC2 boot script, bash -n + shellcheck
make script-test      # backup script against stubbed aws/ssh/terraform
terraform -chdir=terraform test -filter=tests/restore.tftest.hcl   # a single suite
```

Requires Terraform >= 1.9 and ansible-core. `terraform init` downloads the provider from the registry but never calls AWS.
