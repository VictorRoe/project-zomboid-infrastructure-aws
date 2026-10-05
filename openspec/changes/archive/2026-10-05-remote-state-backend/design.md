# Design

## Decisiones

- **Bloqueo nativo de S3** (`use_lockfile`, GA en 1.11) en lugar de DynamoDB (deprecado; un recurso menos).
- **Configuración parcial:** el bloque fija key, cifrado y bloqueo; bucket y región por `-backend-config` para no hardcodear la cuenta.
- **SSE-S3** en lugar de KMS: sin costo extra.
- **Stack aparte con estado local** y `prevent_destroy`: la baja del servidor no puede borrarlo.
- Tests con `init -backend=false`; `terraform console` necesita una copia sin `backend.tf`.

## Riesgos / Compromisos

- [Migración y bloqueo sin probar en AWS] → pendiente (D37); copia previa del estado documentada.
