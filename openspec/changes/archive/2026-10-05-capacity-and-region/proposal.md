# Proposal

## Por qué

La `t3.large` (8 GiB, burstable) con el heap del JSON del juego no tenía margen verificable, y una reinstalación restauraba el heap (VictorRoe/project-zomboid-infrastructure-aws#7). La región se elegía sin mediciones (VictorRoe/project-zomboid-infrastructure-aws#11).

## Qué cambia

- Valores por defecto genéricos: `m7i.large` + `pz_java_xmx_mb = 4096` + `pz_host_overhead_mb = 3072`.
- Terraform verifica RAM nominal y arquitectura y avisa CPU burstable; Ansible verifica RAM utilizable sin swap.
- Heap gestionado en `ProjectZomboid64.json`, también tras actualizar el juego.
- `pz-ctl.sh metrics` y procedimiento de prueba de carga; comparación de regiones medida (se mantiene us-east-1).

## Capacidades

### Capacidades nuevas
- `host-capacity`

## Impacto

`terraform/` (data `aws_ec2_instance_type`, precondiciones, check), `playbook/` (heap, assert de RAM, auto-update), `docs/costs.md`.
