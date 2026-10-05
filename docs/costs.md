# Costos, tamaño y región

Estimación de lo que cuesta el stack según el tier elegido, cómo se dimensiona y por qué la región queda en `us-east-1`. El resumen corto está en el [README](../README.md#costos-estimados). Los valores de configuración, en [spec.md](spec.md).

## Precios usados

Precios on-demand de AWS, Linux, en USD, sin impuestos ni créditos. Se consultaron el **2026-10-05** en los JSON públicos que alimentan las páginas de precios de AWS, sin usar ninguna cuenta. Verificar antes de decidir, porque cambian.

| Ítem | us-east-1 | sa-east-1 | Fuente |
|---|---|---|---|
| `t3.medium` (2 vCPU, 4 GiB, burstable; tier `minimo`) | 0,0416 /h | 0,0672 /h | [EC2 on-demand](https://aws.amazon.com/ec2/pricing/on-demand/) |
| `m7i.large` (2 vCPU, 8 GiB; tier `estandar`, por defecto) | 0,1008 /h | 0,1607 /h | ídem |
| `r7i.large` (2 vCPU, 16 GiB; tier `robusto`) | 0,1323 /h | 0,2111 /h | ídem |
| `m7i.xlarge` (4 vCPU, 16 GiB; tier `grande`) | 0,2016 /h | 0,3213 /h | ídem |
| `t3.large` (2 vCPU, 8 GiB, burstable; el valor anterior) | 0,0832 /h | 0,1344 /h | ídem |
| Disco gp3 | 0,08 /GB-mes | 0,152 /GB-mes | [EBS](https://aws.amazon.com/ebs/pricing/) |
| Snapshots EBS (estándar) | 0,05 /GB-mes | 0,068 /GB-mes | ídem |
| IPv4 pública (también la Elastic IP, en uso u ociosa) | 0,005 /h | 0,005 /h | [VPC](https://aws.amazon.com/vpc/pricing/) |
| Transferencia a Internet | primeros 100 GB/mes sin cargo (sumando regiones), después ~0,09 /GB | ídem, después ~0,15 /GB | [EC2 data transfer](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer) |

IAM, el security group y el bucket del estado (unos KB) no tienen costo relevante.

## Tiers

`tier` elige un perfil coherente de instancia, heap, margen de RAM y disco. Cualquier variable explícita (`instance_type`, `pz_java_xmx_mb`, `pz_host_overhead_mb`, `root_volume_size_gb`) gana sobre el tier, y el plan igual verifica que la RAM alcance. Los snapshots automáticos son iguales en todos: uno por día con la instancia prendida, y se conservan 4 (`backup_retain_count`).

| Tier | Para qué | Instancia | vCPU | RAM | Heap / margen (MB) | Disco | USD/mes, 60 h de juego | USD/mes, 24/7 |
|---|---|---|---|---|---|---|---|---|
| `minimo` | Probar o levantar el server; 1–2 jugadores sin mods | `t3.medium` (burstable) | 2 | 4 GiB | 2560 / 1024 | 30 GB | ~9,05 | ~37 |
| `estandar` (por defecto) | Grupo chico, pocos mods | `m7i.large` | 2 | 8 GiB | 5632 / 1536 | 30 GB | ~12,70 | ~80 |
| `robusto` | Muchos mods (~250), 4–8 jugadores | `r7i.large` | 2 | 16 GiB | 13312 / 2048 | 50 GB | ~16,85 | ~105 |
| `grande` | Muchos mods, más jugadores y CPU | `m7i.xlarge` | 4 | 16 GiB | 12800 / 2560 | 60 GB | ~22,05 | ~157 |

Cómo se calcula, en us-east-1: EC2 (horas × precio), más disco gp3, Elastic IP (3,65) y snapshots, que se cobran todo el mes. Se estiman unos 10, 12, 25 y 30 GB guardados en snapshots: son incrementales, así que los 4 ocupan poco más que uno. Por ejemplo, `estandar` con 60 h: EC2 6,05 + gp3 2,40 + EIP 3,65 + snapshots ~0,60 = ~12,70. La transferencia de un grupo chico entra en los 100 GB/mes sin cargo.

- Con la EC2 detenida siguen cobrándose el disco, la Elastic IP y los snapshots: ~6,55 (`minimo`), ~6,65 (`estandar`), ~8,90 (`robusto`) y ~9,95 USD/mes (`grande`). No se hacen snapshots nuevos mientras está apagada.
- Después de `destroy-and-backup.sh` solo quedan los snapshots.
- `minimo` es burstable: el plan avisa. Sirve para probar y para un uso liviano. Bajo carga sostenida, revisar el balance de créditos de CPU.
- Para elegir: si sobra presupuesto y hay pocos mods, `estandar`. Si el log muestra un heap cerca del máximo o lag con muchos mods, `robusto`. Si la CPU es el cuello de botella (`metrics`: carga sostenida ≥ 2), `grande`.

## Dimensionamiento ([#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7))

- **Regla:** RAM utilizable ≥ heap + margen. El margen cubre SO, memoria nativa de Java (metaspace, hilos, ZGC) y pzsvrtool. Crece con el tier (1 → 2,5 GB), porque más mods y más CPU usan más memoria fuera del heap. Los tiers dejan heap + margen apenas por debajo de la RAM que informa el kernel (D40): si `metrics` muestra uso sostenido de swap o el proceso muere por falta de memoria, subir `pz_host_overhead_mb` o bajar el heap. La swap no cuenta. Terraform lo verifica con la RAM nominal del tipo de instancia, y Ansible con la RAM que informa el kernel.
- **Familia no burstable** desde `estandar`: el juego tiene carga sostenida, y con una `t3` se agotan los créditos de CPU (o se pagan, en modo unlimited). Si se usa una burstable, Terraform avisa en el plan. Hay que registrar el balance de créditos (métrica `CPUCreditBalance`), el modo (`standard`/`unlimited`) y el costo bajo carga.
- El tamaño definitivo de un servidor concreto sale de una prueba de carga, no de esta tabla.

### Prueba de carga (pendiente: requiere AWS y jugadores reales)

1. Definir el escenario: jugadores concurrentes objetivo, mods y mapa, y duración (al menos 2 horas, con exploración y combate).
2. Hacer un backup (`script/pz-ctl.sh backup`) y anotar la build del juego (`appmanifest_380870.acf`), la lista de mods y el heap.
3. Durante la prueba: `script/pz-ctl.sh metrics 120 60 > carga.csv` (RAM total y disponible, swap usada, carga, `steal` de CPU y memoria del juego, una muestra por minuto) y los logs del juego.
4. Aceptación: sin OOM, sin uso sostenido de swap, `MemAvailable` por encima del 10 % y sin lag reportado. Con una `t3`, además, el balance de créditos no tiene que caer de forma sostenida.
5. Registrar el resultado y el tier elegido en [decisions.md](decisions.md). Para cambiar de tier: `pz-ctl.sh stop` → `tier = "…"` y `terraform apply` → `pz-ctl.sh start` → `pz-ctl.sh provision`. Terraform cambia el tipo en el lugar y conserva disco e IP. El disco solo puede crecer.

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

**Costo:** sa-east-1 cuesta alrededor de un 60 % más en EC2 y casi el doble en disco. Con el tier `estandar`, unos 18,70 USD/mes con 60 h de juego (EC2 9,64 + gp3 4,56 + EIP 3,65 + snapshots ~0,82) contra ~12,70 en us-east-1. Encendido 24/7, unos 126 contra ~80 USD/mes.

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
