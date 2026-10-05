# Proposal

## Por qué

El `user_data` clona y actualiza una rama mutable (`main` por defecto) y ejecuta Ansible con privilegios; reconstruir o restaurar puede ejecutar código distinto del revisado (VictorRoe/project-zomboid-infrastructure-aws#18). Además, cambiar `user_data` hace que el provider detenga y reinicie la instancia sin volver a ejecutarlo.

## Qué cambia

- `repo_commit` (SHA de 40 caracteres) obligatorio; `repo_follow_branch` como modo de prueba explícito y excluyente.
- `pz-provision` (instalado por `user_data`) obtiene el commit, verifica `HEAD` y aborta sin caer a otra revisión; `--commit` para actualizaciones deliberadas.
- `ignore_changes = [ami, user_data]`; output `repo_commit`.
- La VM local clona desde un servidor git en el host con `repo_commit = HEAD`.
- **BREAKING (incompatible):** sin `repo_commit` el plan falla.

## Capacidades

### Capacidades modificadas
- `server-bootstrap`, `local-integration-testing`

## Impacto

`terraform/variable.tf`, `main.tf`, `output.tf`, `templates/`; `tests/provision/`; `local/vm.sh`; `tests/render-user-data.sh`.
