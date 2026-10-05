# Tasks

## 1. Acceso SSH con Terraform

- [x] 1.1 Agregar las variables `ssh_public_key`, `ssh_key_name`, `ssh_allowed_cidrs`, `aws_key_pair.pz` (protegido con count), `key_name` en la instancia con una validación entre variables que rechace ambas entradas; verificar con `terraform validate`
- [x] 1.2 Agregar `terraform/tests/ssh.tftest.hcl` cubriendo clave pública, nombre existente, ambas (expect_failures) y CIDR restringido; verificar que `make tf-test` pase

## 2. Detención segura en el script de backup

- [x] 2.1 Crear el arnés de stubs `tests/script/` (`bin/ssh`, `bin/aws`, `bin/terraform`, `run.sh`) y `make script-test`; verificar que una prueba de humo del script actual se ejecute íntegramente contra los stubs
- [x] 2.2 Reescribir el paso de detención con el entorno correcto del bus de usuario, sondeo de salida del proceso, `SSH_KEY`, comando remoto entre comillas simples, opciones de clave de host, `FORCE_SNAPSHOT`; verificar que pasen las pruebas del script para detención confirmada, fallo SSH (sin snapshot, sin destroy) y ruta forzada
- [x] 2.3 Documentar las variables SSH y la semántica de fallo del backup en README/CLAUDE.md; verificar con `bash -n script/destroy-and-backup.sh`

## 3. Documentación y changelog

- [x] 3.1 Actualizar `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` donde corresponda, agregar una entrada de decisión con fecha a `docs/decisions.md` y una entrada `[Unreleased]` en `CHANGELOG.md` que referencie el issue; verificar que los enlaces resuelvan y que los valores coincidan con el código
