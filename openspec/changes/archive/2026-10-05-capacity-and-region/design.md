# Design

## Decisiones

- **No apuntar a un servidor concreto** (pedido del mantenedor): valores genéricos; perfiles grandes por variables.
- **Familia no burstable:** carga sostenida del juego; `t3` solo con aviso.
- **Dos verificaciones:** Terraform con la RAM nominal (antes de crear), Ansible con la utilizable (la real).
- **`pz-set-heap.py`** escribe en el mismo archivo (conserva dueño), reemplaza `-Xmx` y baja un `-Xms` mayor.
- **Región:** la diferencia de latencia es real pero el costo es ~60 % mayor; no se cambia el valor por defecto por una medición; procedimiento de migración documentado.

## Riesgos / Compromisos

- [Tamaño definitivo] → requiere prueba de carga real (pendiente).
