# Design

## Contexto

El playbook se ejecuta en la propia instancia (`ansible_connection=local`) como `ubuntu` con `become: true`. Las variables están en línea en el play. pzsvrtool lee `pzRootAdminPassword` desde su archivo de configuración.

## Objetivos / No objetivos

**Objetivos:** ejecuciones sin supervisión seguras por defecto; credencial persistente; pruebas offline.

**No objetivos:** integración con Secrets Manager/SSM (requiere perfil de instancia IAM; posible seguimiento); rotar la contraseña de una cuenta de administrador ya creada dentro de la base de datos de PZ.

## Decisiones

- **Generar en el host, persistir en disco** en lugar de pasarla por user_data o por `random_password` de Terraform (ambos filtran a los metadatos/estado). El archivo reside en el disco raíz, por lo que la restauración de snapshot lo conserva.
- **Generación:** `stat` del archivo → si falta, `copy` con contenido `lookup('ansible.builtin.password', '/dev/null', chars=['ascii_letters','digits'], length=32)` con `no_log`; luego `slurp` + `set_fact pz_admin_password_effective` (`no_log`). Una contraseña proporcionada también se escribe en el archivo, de modo que el archivo sea siempre la fuente de verdad para los operadores.
- **Valores por defecto:** `pz_admin_password: ""` (vacío = generar). La validación (en `tasks/validate.yml`) solo aplica las reglas de robustez cuando no está vacía. La aserción usa `quiet: true` en lugar de `no_log: true` para que se muestre `fail_msg` (la salida de assert lista expresiones, no valores) — hallazgo de revisión.
- **Orden:** `admin_password.yml` se incluye justo después de "Create pzsvrtool configuration directory" (necesita el usuario y el directorio) y antes de "Configure pzsvrtool non-interactively".
- **Capacidad de prueba:** ambos archivos de tareas se parametrizan con `pz_user`/`pz_home`; `tests/ansible/test_admin_password.yml` los ejecuta en localhost sin become, con `pz_user` = usuario actual y `pz_home` = directorio temporal. Un script ejecutor verifica los códigos de salida esperados de éxito/fallo y el modo/persistencia del archivo.

## Riesgos / Compromisos

- [PZ conserva la contraseña de administrador en su base de datos tras el primer inicio, por lo que cambiarla después en la configuración puede no surtir efecto] → documentado en operaciones; fuera de alcance.
- [El operador no puede ver la contraseña generada sin SSH] → acceso SSH agregado por `instance-ssh-access`; el comando de obtención se imprime en el mensaje de depuración final del playbook (solo la ruta, no el valor).

## Plan de migración

Los servidores existentes conservan su administrador actual en la base de datos; en la siguiente ejecución del playbook se crea un archivo de contraseña. Reversión: revertir el cambio.
