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

## Local checks (no AWS)

```bash
ansible-playbook --syntax-check -i playbook/inventory.ini playbook/project-zomboid-server-install.yml
```
