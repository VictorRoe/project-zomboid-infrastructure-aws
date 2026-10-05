# Tasks

## 1. Outputs de Terraform y nombre del servidor

- [x] 1.1 Agregar la variable `pz_server_name` (validada por regex) y los outputs `backup_bucket_name`, `aws_region`, `pz_server_name`; pasar `-e pz_server_name=` en la plantilla de user_data; verificar con `make tf-test` con una aserción sobre los outputs y el user_data renderizado

## 2. Configuración del script

- [x] 2.1 Resolver `TF_DIR`, leer los outputs con sobrescritura por entorno, fallar rápido ante valores vacíos; verificar con pruebas del script para outputs, sobrescritura y escenarios de bucket faltante
- [x] 2.2 Usar el output `root_volume_id`, archivo de metadatos con mktemp, nombre de servicio parametrizado; verificar que la prueba del script afirme `create-snapshot --volume-id <output>` y `pzsvrtool@<name>.service`
- [x] 2.3 Verificar que el script se ejecute desde la raíz del repo y desde `/tmp` en las pruebas (independencia del cwd)

## 3. Documentación y changelog

- [x] 3.1 Actualizar `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` donde corresponda, agregar una entrada de decisión con fecha a `docs/decisions.md` y una entrada `[Unreleased]` en `CHANGELOG.md` que referencie el issue; verificar que los enlaces resuelvan y que los valores coincidan con el código
