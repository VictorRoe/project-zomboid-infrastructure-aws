# Operations

Day-to-day commands. Values are listed in [spec.md](spec.md).

## Deploy and tear down

```bash
cd terraform
terraform init
terraform apply                       # creates the server and bootstraps it via user_data
terraform output -raw public_ip       # players connect to <ip>:16261
../script/destroy-and-backup.sh       # snapshot + S3 metadata + terraform destroy (run from terraform/)
```

## On the server

```bash
sudo -iu pzserver pzsvrtool console
sudo -iu pzserver systemctl --user status pzsvrtool@zomboid.service
sudo -iu pzserver systemctl --user list-timers pz-auto-update.timer
sudo -iu pzserver journalctl --user -u pz-auto-update.service
sudo tail -f /var/log/cloud-init-output.log    # first-boot provisioning log
```

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
terraform -chdir=terraform test -filter=tests/ami.tftest.hcl   # a single suite
```

Requires Terraform >= 1.9 and ansible-core. `terraform init` downloads the provider from the registry but never calls AWS.
