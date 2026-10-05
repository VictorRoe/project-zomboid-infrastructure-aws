# Design

## Contexto

El script se ejecuta en la máquina del operador usando `terraform output`, AWS CLI y SSH. El servidor corre como servicio *de usuario* de systemd de `pzserver` (linger habilitado); `systemctl --user` necesita `XDG_RUNTIME_DIR=/run/user/<uid>`.

## Objetivos / No objetivos

**Objetivos:** una ruta SSH funcional; no tomar snapshot de un servidor en ejecución por defecto; que sea probable sin AWS ni un host real.

**No objetivos:** SSM Session Manager (requeriría un perfil de instancia IAM; posible seguimiento); cambiar la configuración del bucket/región de backup (se maneja en `backup-script-config`).

## Decisiones

- **Entradas del par de claves:** `ssh_public_key` → `aws_key_pair.pz[0]` (protegido con count); (`key_name = "pz-server"` estático, conocido en tiempo de plan); `local.key_name = length(aws_key_pair.pz) > 0 ? aws_key_pair.pz[0].key_name : (var.ssh_key_name != "" ? var.ssh_key_name : null)` (`coalesce` falla cuando todos los argumentos son null — hallazgo de revisión). Exclusión mutua mediante una `validation` entre variables en `ssh_key_name` (Terraform >= 1.9, ya requerido).
- **Comando remoto de detención** (entre comillas simples para que `$(id -u …)` se expanda en el servidor, no en la máquina del operador): `sudo -u pzserver env XDG_RUNTIME_DIR=/run/user/$(id -u pzserver) systemctl --user stop pzsvrtool@<name>.service`, y luego sondear `pgrep -u pzserver -f ProjectZomboid` hasta `STOP_TIMEOUT` segundos (por defecto 600; la cuenta regresiva de pzsvrtool es de 5 min). El nombre del servidor sigue siendo `zomboid` aquí; se parametriza en `backup-script-config`.
- **Semántica de fallo:** cualquier fallo del paso de detención/verificación → `exit 1` antes de `create-snapshot`, salvo que `FORCE_SNAPSHOT=1`.
- **Pruebas del script:** `tests/script/run.sh` coloca primero en el `PATH` los stubs de `tests/script/bin` (`ssh`, `aws`, `terraform`); los stubs registran su argv en un archivo y se comportan según variables de entorno (p. ej. `STUB_SSH_FAIL=1`). Las aserciones hacen grep sobre el registro (p. ej. sin `create-snapshot`, sin `destroy`). La espera del sondeo es sobrescribible (`POLL_INTERVAL=0`) para mantener las pruebas rápidas. Sin dependencia de bats.

- **Opciones SSH:** `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10`, más `-i $SSH_KEY` cuando está definido. cloud-init regenera las claves de host en cada instancia nueva (incluidas las restauradas), por lo que una entrada fija en known_hosts fallaría al reutilizar la IP; el destino es la IP que Terraform acaba de reportar.

## Riesgos / Compromisos

- [Operadores que dependían del antiguo comportamiento de "continuar siempre"] → vía de escape `FORCE_SNAPSHOT=1`, documentada.
- [Clave pública en tfvars] → las claves públicas no son secretas; los tfvars están en gitignore de todos modos.
