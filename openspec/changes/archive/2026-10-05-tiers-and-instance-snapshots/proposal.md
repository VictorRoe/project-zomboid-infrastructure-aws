# Proposal

## Por qué

El mantenedor pidió elegir el tamaño de la infraestructura por perfil (desde lo mínimo para levantar el servidor hasta algo robusto), con una tabla de recomendaciones y sin editar archivos. También pidió snapshots automáticos *sí y solo sí* el servidor está prendido, conservando 4. DLM no puede condicionar por el estado de la instancia.

## Qué cambia

- `tier` (`minimo`, `estandar` por defecto, `robusto`, `grande`) fija instancia, heap, margen y disco; las variables individuales (null por defecto) lo reemplazan. Output `tier`.
- Los snapshots automáticos los hace la instancia con un timer de systemd (`Persistent=true`) y un rol de IAM mínimo; retención 4. Se elimina la política DLM.

## Capacidades

### Capacidades modificadas
- `host-capacity`, `world-backup`

## Impacto

`terraform/` (`locals.tiers`, variables, rol y perfil de IAM), `playbook/` (`tasks/auto_snapshot.yml`, `files/pz-auto-snapshot.py`), `tests/snapshot/`, docs (README, costs).
