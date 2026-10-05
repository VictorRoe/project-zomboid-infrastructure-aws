# Proposal

## Por qué

El playbook define por defecto `pz_admin_password: "test"` y su aserción solo rechaza `CHANGE_ME_USE_ANSIBLE_VAULT`. Como el `user_data` de EC2 ejecuta el playbook sin supervisión y sin variables extra, cada servidor aprovisionado obtiene la contraseña de administrador root `test` en una IP pública (VictorRoe/project-zomboid-infrastructure-aws#3).

## Qué cambia

- **BREAKING (incompatible):** se elimina el valor por defecto `"test"`. Si no se proporciona contraseña, el playbook genera una contraseña aleatoria robusta en el host, la guarda en `~pzserver/pzsvrtool/.admin_password` (0600, propietario `pzserver`) y la reutiliza en cada ejecución posterior (incluso tras restaurar un snapshot).
- Una contraseña proporcionada explícitamente debe tener ≥ 12 caracteres, no ser un valor débil conocido (`test`, `password`, `admin`, `changeme`, el antiguo placeholder) y seguir sin contener espacios en blanco ni `=` (formato de configuración de pzsvrtool).
- La contraseña nunca pasa por Terraform/`user_data` (los metadatos de la instancia son legibles por cualquiera con `ec2:DescribeInstanceAttribute`).
- La validación y la generación se movieron a archivos de tareas incluidos para poder probarlos offline con `ansible-playbook` contra localhost, sin root y sin AWS.

## Capacidades

### Capacidades nuevas
- `admin-credentials`: cómo se proporciona, genera, valida y persiste la contraseña de administrador root del servidor de juego.

### Capacidades modificadas

## Impacto

- `playbook/project-zomboid-server-install.yml`, nuevos `playbook/tasks/validate.yml`, `playbook/tasks/admin_password.yml`, `tests/ansible/`, `make ansible-test`.
- Los operadores obtienen la contraseña generada con `sudo cat /home/pzserver/pzsvrtool/.admin_password` por SSH (habilitado por `instance-ssh-access`).
- Apilado sobre `backup-script-config`.
