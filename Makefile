# Offline checks: no AWS credentials or API calls (providers are mocked).
TF ?= terraform
TF_DIR := terraform
PLAYBOOK := playbook/project-zomboid-server-install.yml

.PHONY: test tf-test ansible-check

test: tf-test ansible-check

tf-test:
	$(TF) -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	$(TF) -chdir=$(TF_DIR) fmt -check -recursive
	$(TF) -chdir=$(TF_DIR) validate
	$(TF) -chdir=$(TF_DIR) test

ansible-check:
	ansible-playbook --syntax-check -i playbook/inventory.ini $(PLAYBOOK)
