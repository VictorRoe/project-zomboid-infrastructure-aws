# Proposal

## Por qué

La instalación no gestionaba el `.ini`, SandboxVars, spawns ni las listas de mods y mapas: una instalación limpia no reproducía el servidor (VictorRoe/project-zomboid-infrastructure-aws#8). Tampoco había contraseña de ingreso: conocer la IP alcanzaba para entrar (VictorRoe/project-zomboid-infrastructure-aws#13).

## Qué cambia

- `pz-ctl.sh push-config <dir>`: el operador sube la configuración desde un directorio en git (contrato de archivos, commit de origen).
- Ansible valida, renderiza (contraseña gestionada, RCON desactivado) y aplica solo si cambió: apagado ordenado, copia, registro. Los cambios manuales se avisan y no se pisan.
- `pz_wait_for_config`: el juego no crea el mundo sin configuración.
- Contraseña de ingreso generada o provista, persistida, distinta de la de admin, rotable.

## Capacidades

### Capacidades nuevas
- `server-config`, `player-access`

### Capacidades modificadas
- `local-integration-testing`

## Impacto

`playbook/` (`tasks/game_settings.yml`, `join_password.yml`, `server_config_*.yml`, `stop_game.yml`, `files/pz-config-render.py`), `script/pz-ctl.sh`, `tests/ansible/`, `local/vm.sh`.
