# Design

## Decisiones

- **Regla dinámica** en el security group (sin recurso nuevo ni reemplazo del SG).
- **Validación:** `cidrnetmask` (solo IPv4) y `cidrhost(c, 0)` igual a la dirección escrita (rechaza bits de host).
- **UFW:** sigue con `22/tcp` abierto; el origen se filtra solo en el SG, que se actualiza en el momento (UFW solo al reaprovisionar: duplicar la lista dejaría afuera al operador cuando cambie su IP).

## Riesgos / Compromisos

- [Bloqueo del operador al migrar] → operations.md: agregar la IP nueva antes de quitar la vieja.
- [Host key no verificada] → identificado para revisión posterior.
