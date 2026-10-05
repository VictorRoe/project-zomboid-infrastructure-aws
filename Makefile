# Chequeos offline: sin credenciales de AWS ni llamadas a la API (providers simulados).
TF ?= terraform
TF_DIR := terraform
PLAYBOOK := playbook/project-zomboid-server-install.yml

BOOTSTRAP_DIR := bootstrap/state-backend

.PHONY: test tf-test bootstrap-test user-data-check provision-test script-test ansible-check ansible-test

test: tf-test bootstrap-test user-data-check provision-test script-test ansible-check ansible-test

tf-test:
	$(TF) -chdir=$(TF_DIR) init -backend=false -input=false >/dev/null
	$(TF) -chdir=$(TF_DIR) fmt -check -recursive
	$(TF) -chdir=$(TF_DIR) validate
	$(TF) -chdir=$(TF_DIR) test

# Stack del bucket de estado remoto (#16).
bootstrap-test:
	$(TF) -chdir=$(BOOTSTRAP_DIR) init -backend=false -input=false >/dev/null
	$(TF) -chdir=$(BOOTSTRAP_DIR) fmt -check -recursive
	$(TF) -chdir=$(BOOTSTRAP_DIR) validate
	$(TF) -chdir=$(BOOTSTRAP_DIR) test

# Renderiza offline el script de arranque de la EC2 y chequea su sintaxis y tamaño (16 KB de AWS).
user-data-check:
	@TF=$(TF) tests/render-user-data.sh > $(TF_DIR)/.user_data.rendered.sh
	bash -n $(TF_DIR)/.user_data.rendered.sh
	@if command -v shellcheck >/dev/null; then shellcheck $(TF_DIR)/.user_data.rendered.sh tests/render-user-data.sh; fi
	@test "$$(wc -c < $(TF_DIR)/.user_data.rendered.sh)" -lt 16384 || { echo "user_data supera 16 KB"; exit 1; }
	@rm -f $(TF_DIR)/.user_data.rendered.sh

# pz-provision (revisión fija, #18) con repos git locales y ansible simulado.
provision-test:
	@if command -v shellcheck >/dev/null; then shellcheck $(TF_DIR)/templates/pz-provision.sh tests/provision/run.sh; fi
	tests/provision/run.sh

# Scripts del operador contra stubs de aws/ssh/terraform (tests/script/bin).
script-test:
	bash -n script/destroy-and-backup.sh script/pz-ctl.sh script/lib/common.sh
	@if command -v shellcheck >/dev/null; then shellcheck -x script/destroy-and-backup.sh script/pz-ctl.sh script/lib/common.sh tests/script/run.sh tests/script/bin/*; fi
	tests/script/run.sh

ansible-check:
	ansible-playbook --syntax-check -i playbook/inventory.ini $(PLAYBOOK)

# Contraseñas, heap y configuración del servidor en localhost (sin root, sin AWS).
ansible-test:
	@if command -v shellcheck >/dev/null; then shellcheck tests/ansible/run.sh; fi
	tests/ansible/run.sh

# VM local que imita la EC2 (QEMU/KVM, sin AWS). Ver docs/operations.md.
.PHONY: local-up local-ssh local-check local-config-test local-reboot-test local-restore-test local-backup-test local-test local-down local-clean

local-up:
	local/vm.sh up

local-ssh:
	local/vm.sh ssh

local-check:
	local/vm.sh check

local-config-test:
	local/vm.sh config-test

local-reboot-test:
	local/vm.sh reboot-test

local-restore-test:
	local/vm.sh restore-test

local-backup-test:
	local/vm.sh backup-test

# Ciclo completo: aprovisionar, subir la configuración, reiniciar, backup y restaurar.
local-test: local-up local-config-test local-reboot-test local-backup-test local-restore-test

local-down:
	local/vm.sh down

local-clean:
	local/vm.sh clean
