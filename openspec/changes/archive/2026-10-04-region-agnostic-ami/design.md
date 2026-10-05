# Design

## Contexto

Configuración de Terraform con una única raíz, estado local, sin pruebas, Terraform sin versión fijada. Las AMI de Ubuntu las publica Canonical (propietario `099720109477`) con nombres `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`.

## Objetivos / No objetivos

**Objetivos:** AMI correcta para la región por defecto; sobrescritura determinista; un arnés de pruebas sin conexión reutilizado por los cambios siguientes (restauración, acceso SSH, script de respaldo, contraseña de administrador).

**No objetivos:** soporte multiarquitectura (Graviton); estado remoto; integración con CI (puede agregarse más adelante, el arnés está listo para CI).

## Decisiones

- **`data "aws_ami" "ubuntu"` con `most_recent = true`, propietario Canonical, filtro de nombre para 24.04 noble amd64 gp3.** Alternativa: el parámetro SSM `/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id` — igualmente válido, pero `aws_ami` es más fácil de simular con `override_data` y no necesita permiso de SSM. El playbook verifica (assert) Debian x86_64, lo cual 24.04 cumple.
- **`locals { base_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id }`.** El local se llama `base_ami_id` para que el cambio de restauración pueda superponer "imagen restaurada > imagen base" sin renombrar.
- **`lifecycle { ignore_changes = [ami] }` en la instancia.** El disco raíz es el mundo (`delete_on_termination=true`), por lo que un cambio de imagen nunca debe reemplazar implícitamente un servidor en ejecución (una imagen más nueva de Canonical o, tras el cambio de restauración, un snapshot más nuevo). Las reconstrucciones deliberadas usan `terraform apply -replace=aws_instance.pz_server` después de un respaldo. (Hallazgo de la revisión: la mitigación anterior de "el plan muestra el reemplazo" era insuficiente.)
- **`availability_zone` tiene por defecto `null`** (AWS elige una AZ en la región); si se define, una validación exige que comience con `var.aws_region` (validación entre variables, Terraform >= 1.9).
- **Arnés de pruebas:** `terraform/tests/*.tftest.hcl` usando `mock_provider "aws"` + `override_data` para `aws_ami` y los data sources de snapshots, con aserciones `command = plan`. Targets del `Makefile`: `tf-test` (`terraform init -backend=false` + `fmt -check` + `validate` + `test`), `ansible-check` (`--syntax-check`), `test` (todos). `required_version = ">= 1.9"` (instalado: 1.16.5) y `.terraform.lock.hcl` versionado (quitado de `.gitignore`) para versiones de proveedor reproducibles; `terraform init` sigue necesitando acceso al registro pero nunca a las APIs de AWS.

## Riesgos / Compromisos

- [Las instancias en ejecución conservan una imagen base antigua para siempre] → aceptable; el actualizador automático se ocupa del juego, `unattended-upgrades` del SO; se reconstruye deliberadamente con `-replace`.
- [Las pruebas simuladas no demuestran que el filtro real coincida con una imagen] → el filtro refleja la nomenclatura documentada de Canonical; una verificación manual con `aws ec2 describe-images` se anota en las tareas como opcional, no obligatoria.

## Plan de migración

Los despliegues existentes en us-east-1 que quieran cero cambios definen `ami_id = "ami-0b6d9d3d33ba97d99"` en su tfvars. Reversión: revertir el commit.
