# Tasks

- [x] 1.1 Variables `repo_commit`/`repo_follow_branch` con validación cruzada; `repo_url` admite el host de la VM; verificar con `terraform test` (config.tftest.hcl)
- [x] 1.2 `templates/pz-provision.sh` y `user_data` que lo instala; `tests/provision/run.sh` (commit válido, inexistente, corto, sin commit, modo rama, checkout existente, `--commit` y fallo del playbook)
- [x] 1.3 `ignore_changes = [ami, user_data]`, output `repo_commit`; test de que un commit nuevo no modifica la instancia (sessions.tftest.hcl)
- [x] 1.4 `tests/render-user-data.sh` (sin backend) y `make user-data-check` con límite de 16 KB
- [x] 1.5 `local/vm.sh` con servidor git local y verificación de la revisión en `check`; `make local-test`
- [x] 1.6 Docs (spec, flows, operations, D25, D35), CHANGELOG
