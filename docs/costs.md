# Costos, tamaño y región

Estimación de lo que cuesta el stack con los valores por defecto, cómo se dimensiona y por qué la región queda en `us-east-1`. El resumen corto está en el [README](../README.md#costos-estimados). Los valores de configuración, en [spec.md](spec.md).

## Precios usados

Precios on-demand de AWS, Linux, en USD, sin impuestos ni créditos. Se consultaron el **2026-10-05** en los JSON públicos que alimentan las páginas de precios de AWS, sin usar ninguna cuenta. Verificar antes de decidir, porque cambian.

| Ítem | us-east-1 | sa-east-1 | Fuente |
|---|---|---|---|
| `m7i.large` (2 vCPU, 8 GiB, por defecto) | 0,1008 /h | 0,1607 /h | [EC2 on-demand](https://aws.amazon.com/ec2/pricing/on-demand/) |
| `r7i.large` (2 vCPU, 16 GiB) | 0,1323 /h | 0,2111 /h | ídem |
| `m7i.xlarge` (4 vCPU, 16 GiB) | 0,2016 /h | 0,3213 /h | ídem |
| `t3.large` (2 vCPU, 8 GiB, burstable; el valor anterior) | 0,0832 /h | 0,1344 /h | ídem |
| Disco gp3 | 0,08 /GB-mes | 0,152 /GB-mes | [EBS](https://aws.amazon.com/ebs/pricing/) |
| Snapshots EBS (estándar) | 0,05 /GB-mes | 0,068 /GB-mes | ídem |
| IPv4 pública (también la Elastic IP, en uso u ociosa) | 0,005 /h | 0,005 /h | [VPC](https://aws.amazon.com/vpc/pricing/) |
| Transferencia a Internet | primeros 100 GB/mes sin cargo (sumando regiones), después ~0,09 /GB | ídem, después ~0,15 /GB | [EC2 data transfer](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer) |

DLM, IAM, el security group y el bucket del estado (unos KB) no tienen costo relevante.

## Estimación mensual con los valores por defecto

Valores por defecto: `us-east-1`, `m7i.large`, disco de 30 GB, Elastic IP y 7 snapshots diarios. El snapshot es incremental: se estiman unos 12 GB guardados (SO, juego y mundo), aunque depende de cuánto cambie el mundo.

| Concepto | 60 h de juego/mes (stop/start) | Encendido 24/7 (730 h) |
|---|---|---|
| EC2 `m7i.large` | 6,05 | 73,58 |
| Disco gp3 30 GB (se cobra también con la EC2 detenida) | 2,40 | 2,40 |
| Elastic IP (se cobra también con la EC2 detenida) | 3,65 | 3,65 |
| Snapshots (~12 GB) | ~0,60 | ~0,60 |
| Transferencia (un grupo chico entra en los 100 GB sin cargo) | 0 | 0 |
| **Total aproximado** | **~12,70 USD** | **~80,20 USD** |

Con la EC2 detenida siguen cobrándose el disco, la Elastic IP y los snapshots, unos 6,65 USD/mes. Después de `destroy-and-backup.sh` solo quedan los snapshots.

Un perfil con muchos mods (`r7i.large`, `pz_java_xmx_mb = 8192`) cuesta unos 14,60 USD/mes con 60 h de juego, o unos 103 USD/mes encendido 24/7.

## Dimensionamiento ([#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7))

- **Regla:** RAM utilizable ≥ `pz_java_xmx_mb` + `pz_host_overhead_mb`. El margen cubre SO, memoria nativa de Java (metaspace, hilos, ZGC) y pzsvrtool. La swap no cuenta. Terraform lo verifica con la RAM nominal del tipo de instancia, y Ansible con la RAM que informa el kernel.
- **Por defecto (servidor genérico, pocos mods):** heap de 4096 MB + margen de 3072 MB = 7168 MB, que entra en una `m7i.large` (8 GiB, informa ~7,6 GiB utilizables). Se eligió una familia no burstable: el juego tiene carga sostenida, y con una `t3` se agotan los créditos de CPU (o se pagan, en modo unlimited).
- **Con muchos mods:** subir juntos el heap y la instancia. Por ejemplo, unos 250 mods con `-Xmx8g` necesitan 11264 MB, así que `r7i.large` (16 GiB, 2 vCPU) o `m7i.xlarge` (16 GiB, 4 vCPU) si falta CPU. El tamaño definitivo sale de una prueba de carga, no de esta tabla.
- **CPU burstable:** si se usa una `t3`/`t3a`, Terraform avisa en el plan. Hay que registrar el balance de créditos (métrica `CPUCreditBalance`), el modo (`standard`/`unlimited`) y el costo bajo carga.

### Prueba de carga (pendiente: requiere AWS y jugadores reales)

1. Definir el escenario: jugadores concurrentes objetivo, mods y mapa, y duración (al menos 2 horas, con exploración y combate).
2. Hacer un backup (`script/pz-ctl.sh backup`) y anotar la build del juego (`appmanifest_380870.acf`), la lista de mods y el heap.
3. Durante la prueba: `script/pz-ctl.sh metrics 120 60 > carga.csv` (RAM total y disponible, swap usada, carga, `steal` de CPU y memoria del juego, una muestra por minuto) y los logs del juego.
4. Aceptación: sin OOM, sin uso sostenido de swap, `MemAvailable` por encima del 10 % y sin lag reportado. Con una `t3`, además, el balance de créditos no tiene que caer de forma sostenida.
5. Registrar el resultado y el tipo elegido en [decisions.md](decisions.md). El cambio de tipo se hace con stop → `terraform apply -var instance_type=…` → start (Terraform cambia el tipo en el lugar y conserva disco e IP).

## Región ([#11](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/11))

**Latencia medida** desde la máquina del operador (Argentina), el 2026-10-05 a las 11:50 UTC: tiempo de conexión TCP (≈ 1 RTT) a `https://ec2.<región>.amazonaws.com`, 15 muestras.

| Región | Mínimo | Mediana | Máximo |
|---|---|---|---|
| us-east-1 | 160 ms | 166 ms | 182 ms |
| sa-east-1 | 33 ms | 34 ms | 244 ms |

Para repetirla:

```bash
for r in us-east-1 sa-east-1; do printf '%s ' $r; for i in $(seq 15); do curl -s -o /dev/null -m 10 -w '%{time_connect}\n' https://ec2.$r.amazonaws.com/ping; done | sort -n | awk '{a[NR]=$1*1000} END {printf "min=%.0f mediana=%.0f max=%.0f ms\n", a[1], a[int((NR+1)/2)], a[NR]}'; done
```

Es una sola conexión, desde un solo proveedor y a una sola hora. Hay que repetirla desde la conexión de cada jugador y, si es posible, medir el ping dentro del juego.

**Costo:** sa-east-1 cuesta alrededor de un 60 % más en EC2 y casi el doble en disco. Con los valores por defecto, unos 18,70 USD/mes con 60 h de juego (EC2 9,64 + gp3 4,56 + EIP 3,65 + snapshots ~0,82) contra ~12,70 en us-east-1. Encendido 24/7, unos 126 contra ~80 USD/mes.

**Decisión: se mantiene `us-east-1` por defecto** ([D34](decisions.md)). La diferencia de latencia es real (~130 ms menos desde Argentina), pero no se cambia el valor por defecto solo por una medición desde una conexión. Quien juegue desde Sudamérica puede usar `aws_region = "sa-east-1"`, porque el stack ya es agnóstico de región (AMI por región, AZ validada). La disponibilidad de `m7i.large` y de la AMI de Ubuntu en sa-east-1 se verifica en el primer `terraform plan` real: el tipo de instancia y la AMI se leen de la API y el plan falla si no existen.

### Mover un servidor existente a otra región

Cambiar `aws_region` no mueve el mundo: crearía un stack nuevo y vacío. Procedimiento:

1. `script/pz-ctl.sh backup` (snapshot consistente) en la región de origen.
2. Copiar el snapshot conservando los tags: `aws ec2 copy-snapshot --source-region us-east-1 --source-snapshot-id snap-… --region sa-east-1 --copy-tags`.
3. En la región de destino hace falta un key pair (o `ssh_public_key`) y otro estado: otra `key` del backend o un directorio de trabajo aparte. El estado de origen no se toca.
4. `terraform apply -var aws_region=sa-east-1 -var restore_snapshot_id=<snap copiado>`. La instancia arranca desde la imagen restaurada, con mundo, contraseñas y configuración, y tiene una Elastic IP nueva: hay que avisar la dirección nueva a los jugadores.
5. Validar el destino: `pz-ctl.sh status`, conectarse al juego y verificar la partida.
6. **Rollback:** mientras no se dé de baja el origen, basta con volver a usarlo (`pz-ctl.sh start` en el origen).
7. Limpieza, una vez validado: `destroy-and-backup.sh` en el origen y, después, borrar los snapshots viejos de origen que ya no hagan falta.
