# Design

## Contexto

Después de `instance-ssh-access`, el script ya cuenta con un arnés de pruebas basado en stubs y un paso de detención verificada. Valores aún fijos: bucket, región, nombre del servicio; llamadas a `terraform` dependientes del cwd; búsqueda de volumen por etiqueta.

## Objetivos / No objetivos

**Objetivos:** un solo lugar de configuración; script independiente de su ubicación; pruebas deterministas.

**No objetivos:** crear/administrar el bucket S3 (sería destruido por el propio `terraform destroy` del script; un stack de bootstrap separado es un posible seguimiento); cambiar el esquema de etiquetas del snapshot (la restauración depende de él).

## Decisiones

- **Outputs en lugar de analizar tfvars:** `terraform output -raw` es la interfaz estable; refleja los valores efectivos, incluidos los valores por defecto.
- **Precedencia:** variable de entorno > output de Terraform. Permite a los operadores recuperarse cuando el estado está parcialmente perdido.
- **Valor por defecto de `TF_DIR`:** `$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)`; todas las llamadas usan `terraform -chdir="$TF_DIR"`.
- **El nombre del servidor fluye Terraform → user_data → playbook** mediante `ansible-playbook -e pz_server_name=...`, de modo que el script, el playbook y el nombre del servicio no puedan divergir. El nombre se valida en Terraform con la regex del playbook `^[A-Za-z0-9._-]+$`.
- **Archivo de metadatos** mediante `mktemp` + limpieza con `trap`.

## Riesgos / Compromisos

- [Configuraciones existentes que dependen de `tu-bucket-zomboid-backups`] → definir `s3_bucket_name` en tfvars o `S3_BUCKET`; documentado en la migración.
- [Estado ausente → los outputs fallan] → sobrescrituras por entorno + mensaje de fallo rápido que nombra el valor faltante.

## Plan de migración

Definir `s3_bucket_name` con el bucket realmente en uso antes de la próxima ejecución de backup. Reversión: revertir el cambio.
