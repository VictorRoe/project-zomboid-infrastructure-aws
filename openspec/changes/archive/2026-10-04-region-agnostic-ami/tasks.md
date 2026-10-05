# Tasks

## 1. Arnés de pruebas

- [x] 1.1 Agregar el bloque `terraform { required_version = ">= 1.9" ... required_providers aws }` y confirmar `.terraform.lock.hcl` (quitarlo de `.gitignore`); verificar que `terraform init -backend=false` tenga éxito (solo registro, sin AWS)
- [x] 1.2 Agregar `Makefile` con los targets `tf-test`, `ansible-check`, `test` y verificar que `make ansible-check` pase con el playbook actual

## 2. Selección de imagen

- [x] 2.1 Agregar la variable `ami_id` (por defecto `""`) y la búsqueda `data "aws_ami" "ubuntu"`; definir `locals.base_ami_id` y usarlo en `aws_instance.pz_server` con `lifecycle { ignore_changes = [ami] }`; establecer `availability_zone` en null por defecto con validación de región; verificar que `terraform validate` pase
- [x] 2.2 Agregar `terraform/tests/ami.tftest.hcl` con proveedor simulado que cubra los escenarios de búsqueda por defecto, sobrescritura y AZ que no coincide (`expect_failures`); verificar que `make tf-test` pase sin credenciales de AWS (`env -u AWS_ACCESS_KEY_ID -u AWS_PROFILE`)

## 3. Documentación y changelog

- [x] 3.1 Actualizar `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` donde corresponda, agregar una entrada de decisión fechada a `docs/decisions.md` y agregar una entrada `[Unreleased]` a `CHANGELOG.md` que referencie el issue; verificar que los enlaces se resuelvan y que los valores coincidan con el código
