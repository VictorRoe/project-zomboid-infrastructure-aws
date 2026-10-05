# Proposal

## Por qué

Con un margen fijo de 3 GB, las instancias de 16 GiB dejaban ~4,5 GiB sin asignar al heap. El mantenedor pidió más heap y un margen que crezca con el tier.

## Qué cambia

- Margen: 1 / 1,5 / 2 / 2,5 GB; heap: 2560 / 5632 / 13312 / 12800 MB (`minimo`, `estandar`, `robusto`, `grande`).

## Capacidades

### Capacidades modificadas
- `host-capacity`

## Impacto

`terraform/main.tf` (`locals.tiers`), `playbook/vars/main.yml`, tests, README, costs, spec, D40.
