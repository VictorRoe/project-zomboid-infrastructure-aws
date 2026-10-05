# Design

## Decisiones

- heap + margen apenas por debajo de la RAM utilizable que informa el kernel; el margen crece con mods y CPU (memoria nativa de Java), no con la RAM total.

## Riesgos / Compromisos

- [OOM si la memoria fuera del heap supera el margen] → swap de 2 GB, `pz-ctl.sh metrics`, ajuste con variables.
