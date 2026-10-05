# Design

## Decisiones

- **Tier como mapa en `locals`** más variables nullable con `coalesce`: un solo lugar para los perfiles y reemplazos uno por uno; las precondiciones de RAM validan la combinación final.
- **Snapshots desde la instancia:** un timer solo corre con la EC2 prendida; `Persistent=true` cubre el día en que se prende después de la hora. Un mínimo de 12 h entre automáticos evita duplicados al prender.
- **Permisos del rol:** crear solo sobre el volumen etiquetado del servidor, etiquetar solo al crear, borrar solo `pz-backup=auto` del mismo servidor. Sin comodines de acción.
- **boto3 + IMDSv2** (Ubuntu 24.04 no trae AWS CLI en apt); fuera de EC2 el script no hace nada (VM local).

## Riesgos / Compromisos

- [Credenciales en el host] → temporales y limitadas a sus snapshots automáticos.
- [Ejecución real y permisos sin probar en AWS] → pendiente (D37).
