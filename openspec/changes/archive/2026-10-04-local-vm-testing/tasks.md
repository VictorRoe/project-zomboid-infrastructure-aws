# Tasks

## 1. Origen del arranque y puerto SSH

- [x] 1.1 Agregar variables `repo_url` y `repo_branch` (con validación) y usarlas en `local.user_data`; verificar con un test en `config.tftest.hcl` (rama personalizada, valores por defecto y rama inválida con `expect_failures`) y `make tf-test`
- [x] 1.2 Agregar `SSH_PORT` (por defecto 22) al script de backup; verificar con un caso nuevo en `tests/script/run.sh` (`-p 2222`) y `make script-test`

## 2. Entorno de VM local

- [x] 2.1 Crear `local/vm.sh` (`up`, `ssh`, `wait`, `check`, `down`, `clean`): descarga y verificación de la imagen, overlay, clave SSH, seed NoCloud MIME, QEMU con reenvío de puertos; agregar targets `local-*` al `Makefile` y `.local-vm/` a `.gitignore`; verificar con `bash -n` + shellcheck y con `make local-up` hasta que `check` pase
- [x] 2.2 Agregar `reboot-test`, `restore-test` y `backup-test` a `local/vm.sh`; verificar ejecutando cada uno contra la VM y que todos sus chequeos pasen

## 3. Docs y changelog

- [x] 3.1 Documentar en `docs/operations.md` (pruebas locales), `docs/spec.md` y `docs/flows.md`; agregar decisión en `docs/decisions.md` con los resultados reales, y entrada en `CHANGELOG.md`; verificar links y que los comandos documentados coincidan con el `Makefile`
