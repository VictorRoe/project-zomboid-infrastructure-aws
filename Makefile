# Offline checks: no AWS credentials or API calls (providers are mocked).
TF ?= terraform
TF_DIR := terraform
PLAYBOOK := playbook/project-zomboid-server-install.yml

.PHONY: test tf-test user-data-check script-test ansible-check

test: tf-test user-data-check script-test ansible-check

tf-test:
	$(TF) -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	$(TF) -chdir=$(TF_DIR) fmt -check -recursive
	$(TF) -chdir=$(TF_DIR) validate
	$(TF) -chdir=$(TF_DIR) test

# Render the EC2 boot script offline and syntax-check it.
user-data-check:
	@echo 'local.user_data' | $(TF) -chdir=$(TF_DIR) console | sed '1d;$$d' > $(TF_DIR)/.user_data.rendered.sh
	bash -n $(TF_DIR)/.user_data.rendered.sh
	@if command -v shellcheck >/dev/null; then shellcheck $(TF_DIR)/.user_data.rendered.sh; fi
	@rm -f $(TF_DIR)/.user_data.rendered.sh

# Backup script against stubbed aws/ssh/terraform (tests/script/bin).
script-test:
	bash -n script/destroy-and-backup.sh
	@if command -v shellcheck >/dev/null; then shellcheck script/destroy-and-backup.sh tests/script/run.sh tests/script/bin/*; fi
	tests/script/run.sh

ansible-check:
	ansible-playbook --syntax-check -i playbook/inventory.ini $(PLAYBOOK)
