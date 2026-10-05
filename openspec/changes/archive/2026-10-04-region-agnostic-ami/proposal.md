# Proposal

## Por qué

`aws_instance.pz_server` fija `ami-0b6d9d3d33ba97d99`, una imagen de Ubuntu que solo existe en us-east-1, por lo que `var.aws_region` parece configurable pero cualquier otra región falla en el momento del apply (issue de GitHub VictorRoe/project-zomboid-infrastructure-aws#4). Además, el repositorio no tiene verificaciones automatizadas, y los cambios deben poder verificarse sin tocar AWS.

## Qué cambia

- Resolver la AMI de Ubuntu Server LTS x86_64 para la región configurada en el momento del plan mediante un data source (propietario Canonical).
- Agregar una variable opcional de sobrescritura `ami_id`; cuando se define, tiene prioridad sobre la búsqueda.
- Establecer `availability_zone` en `null` por defecto (AWS elige una en la región) y validar que cualquier AZ explícita pertenezca a `aws_region`.
- Ignorar la deriva (drift) de la AMI en la instancia existente para que una imagen más nueva nunca reemplace implícitamente un servidor en ejecución (ni su disco del mundo).
- Introducir un arnés de pruebas sin conexión: `terraform test` con `mock_provider "aws"` (sin credenciales, sin llamadas a la API), verificación de sintaxis de Ansible y un punto de entrada `make test` que los cambios posteriores extienden.
- Documentar el comando de pruebas en `CLAUDE.md`/README.

## Capacidades

### Capacidades nuevas
- `compute-image-selection`: cómo se elige la imagen de máquina del servidor por región, incluida la sobrescritura.

### Capacidades modificadas

## Impacto

- `terraform/main.tf`, `terraform/variable.tf`; nuevos `terraform/tests/`, `Makefile`.
- Requiere Terraform >= 1.7 de forma local (para `mock_provider`); el proveedor de AWS lo descarga `terraform init` pero nunca se lo invoca.
- Las instancias existentes no se reemplazan (los cambios de AMI se ignoran); las instancias nuevas obtienen la imagen actual. `.terraform.lock.hcl` pasa a estar versionado.
