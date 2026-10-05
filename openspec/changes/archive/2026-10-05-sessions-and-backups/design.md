# Design

## Decisiones

- **Estados con timeout propio** (`describe-instances` cada `POLL_INTERVAL` hasta `INSTANCE_TIMEOUT`) en lugar de `aws ec2 wait` (timeout fijo, más difícil de simular).
- **Sin force implícito:** sin confirmación del apagado del juego, la EC2 no se detiene (`FORCE_STOP=1` explícito).
- **Consistencia honesta:** DLM no puede pausar el juego justo al disparar (arranca dentro de la hora; los pre-scripts requieren SSM + IAM en el host), así que sus snapshots se marcan `crash` y no los elige la restauración automática; los consistentes se toman con el juego detenido.
- **Permisos mínimos de DLM:** snapshot solo de volúmenes con `pz-world-volume=<nombre>`, borrado solo de `pz-backup=auto`.
- **Bucket de metadatos:** inventario sin lectores; se retira la dependencia sin borrar el bucket ni su historia.
- **`inherit_errexit`** en `common.sh`: un fallo de `aws` dentro de `$(...)` no puede devolver un ID vacío (encontrado por los tests).

## Riesgos / Compromisos

- [Costos con la EC2 detenida: disco, EIP, snapshots] → costs.md.
- [DLM y permisos no probados en AWS] → pendiente; alternativa: política administrada.
