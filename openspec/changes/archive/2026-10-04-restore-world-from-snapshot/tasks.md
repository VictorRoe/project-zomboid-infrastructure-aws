# Tasks

## 1. Cableado de la restauración

- [x] 1.1 Agregar las variables `restore_from_snapshot` (bool, por defecto true) y `restore_snapshot_id` (string, por defecto ""); verificar con `terraform validate`
- [x] 1.2 Calcular `local.restore_snapshot_id`, agregar `data.aws_ebs_snapshot.restore` y `aws_ami.restored` (con guarda count; nombre, ENA, uefi-preferred, tamaño, precondición de estado completado) a partir de ese snapshot y la precedencia de `local.instance_ami_id`; usarlo en `aws_instance.pz_server`; verificar con `terraform validate`
- [x] 1.3 Agregar el output `restored_from_snapshot_id`; verificar mediante la aserción de prueba en 2.1

## 2. Pruebas e idempotencia del arranque

- [x] 2.1 Agregar `terraform/tests/restore.tftest.hcl` que cubra los escenarios de snapshot presente, ausente, deshabilitado, ID explícito y estado pendiente (`expect_failures`) con proveedor simulado; verificar que `make tf-test` pase sin credenciales de AWS
- [x] 2.2 Hacer que `user_data` actualice un checkout existente (git mediante `runuser -u ubuntu`) en lugar de clonar; extraerlo a `terraform/templates/user_data.sh.tftpl` y verificar con `bash -n` sobre la salida renderizada, más una aserción de tftest de que contiene la rama de actualización
- [x] 2.3 Documentar el comportamiento de restauración y las variables de exclusión en README y CLAUDE.md; verificar que la documentación coincida con los nombres de variables en `variable.tf`

## 3. Documentación y changelog

- [x] 3.1 Actualizar `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` donde corresponda, agregar una entrada de decisión fechada a `docs/decisions.md` y agregar una entrada `[Unreleased]` a `CHANGELOG.md` que referencie el issue; verificar que los enlaces se resuelvan y que los valores coincidan con el código
