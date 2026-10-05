# Design

## Decisiones

- **Fuente:** la provee el operador (elección del mantenedor); el repo de configuración de un servidor concreto es otro proyecto y puede ser privado. El commit de origen se registra (`SOURCE`); cambios sin commitear se rechazan salvo `ALLOW_DIRTY`.
- **Revisión = sha256 de los archivos renderizados** (incluye la contraseña): rotarla también aplica; re-ejecutar sin cambios no toca nada.
- **Drift por clave:** PZ reescribe el `.ini` al arrancar, así que se comparan valores por clave, no bytes, y nunca se imprimen valores.
- **Detener antes de escribir:** PZ puede reescribir el `.ini`; se detiene en orden, se aplica y se vuelve a iniciar.
- **Validación en el host antes de reemplazar lo subido:** el `config-staged` siempre es válido, así un reaprovisionamiento o una restauración no fallan por una subida mala.
- **Espera de configuración** con `ConditionPathExists=|` (configuración aplicada o mundo existente): un disco restaurado viejo no queda esperando.
- **Contraseña de ingreso** con el mismo patrón que la de admin (D17); sin configuración subida, se escribe en un `.ini` mínimo antes del primer arranque. Whitelist no adoptada.

## Riesgos / Compromisos

- [Instalación limpia sin jugar hasta subir configuración] → documentado; la VM lo prueba.
- [Rechazo de contraseña incorrecta con cliente real] → pendiente (D37).
