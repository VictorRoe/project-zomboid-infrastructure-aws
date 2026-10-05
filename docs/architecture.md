# Arquitectura

Cómo encajan las piezas de este repo. Los valores actuales están en [spec.md](spec.md); los motivos, en [decisions.md](decisions.md). Las secuencias paso a paso están en [flows.md](flows.md).

## Componentes

| Capa | Dónde | Responsabilidad |
|---|---|---|
| Terraform | `terraform/` | Recursos de AWS: un security group y una instancia EC2 con un único disco raíz gp3 |
| Arranque | `terraform/templates/user_data.sh.tftpl` | Instala Ansible, clona este repo desde GitHub (o lo actualiza, en un disco restaurado) y ejecuta el playbook en la propia instancia |
| Ansible | `playbook/` | Configuración del host: usuario `pzserver`, swap, pzsvrtool, instalación del juego, servicios systemd de usuario, timer de actualización automática, UFW |
| Prueba local | `local/vm.sh` | VM QEMU/KVM con la misma imagen y el mismo `user_data` que la EC2, para probar sin AWS |
| Backup/baja | `script/destroy-and-backup.sh` | Corre en la máquina del operador: detener el servidor → snapshot del disco raíz → registro en S3 → `terraform destroy` |

No hay estado remoto, CI ni pipeline de imágenes. El estado de Terraform es local, en el checkout del operador.

## Diagrama

```
 Máquina del operador                       AWS (aws_region)
┌──────────────────────┐        ┌──────────────────────────────────────────────┐
│ terraform apply      │──────▶ │ Security group pz-server-sg                  │
│                      │        │  UDP 16261-16262, 8766 · TCP 22 (CIDRs ssh)  │
│ destroy-and-backup.sh│        │                                              │
│  ├─ terraform output │        │ EC2 PZ-Server-Instance (Ubuntu, t3.large)    │
│  ├─ ssh ubuntu@ip ───┼──────▶ │  raíz gp3 30 GB, tag pz-world-data-root      │
│  ├─ aws ec2 snapshot─┼──────▶ │   └─ cloud-init user_data                    │
│  ├─ aws s3 cp ───────┼──┐     │       └─ git clone del repo de GitHub        │
│  └─ terraform destroy│  │     │           └─ ansible-playbook (localhost)    │
└──────────────────────┘  │     │                                              │
                          │     │ Snapshots EBS tag pz-world-data-snapshot     │
                          └───▶ │ Bucket S3 (externo, no gestionado acá)       │
                                └──────────────────────────────────────────────┘
```

## Estructura en el host (después del playbook)

```
/home/pzserver/
├── pzsvrtool/
│   ├── pzsvrtool.config          # nombre del servidor, admin, backups (0600)
│   ├── .admin_password           # contraseña del admin root, generada o provista (0600)
│   └── pz-auto-update.sh         # verificador de actualizaciones (lo corre el timer)
├── pzserver/                     # instalación del juego (SteamCMD app 380870)
├── Steam/steamcmd.sh
└── .config/systemd/user/
    ├── pzsvrtool@<nombre>.service.d/keepalive.conf
    ├── pz-auto-update.service
    └── pz-auto-update.timer
/etc/systemd/system/user@<uid>.service.d/pzsvrtool.conf   # TimeoutStopSec=20m
/swapfile                                                 # 2 GB
```

El juego corre como **servicio systemd de usuario** `pzsvrtool@<nombre>.service` de `pzserver`, y **linger** lo mantiene activo desde el arranque. Cualquier llamada a `systemctl --user` desde otra cuenta necesita `XDG_RUNTIME_DIR=/run/user/<uid>` y la dirección del D-Bus del usuario.

## Puntos de acoplamiento

- **Configuración:** fluye en un solo sentido: variables de Terraform → outputs → script de backup, y → `user_data` → playbook (`pz_server_name`). No hardcodear estos valores en otro lado.
- **Puertos:** se declaran dos veces, en el security group (`terraform/main.tf`) y en UFW (`pz_udp_ports` en `playbook/vars/main.yml`). Tienen que coincidir.
- **Entrega del playbook:** es un `git clone` desde GitHub al arrancar, así que los cambios al playbook solo llegan a instancias nuevas después de pushearlos a la rama por defecto.
- **Tag de snapshot:** `pz-world-data-snapshot` conecta el script de backup (que lo escribe) con `main.tf` (que lo lee y registra `aws_ami.restored` a partir de él).

## Problemas conocidos

### Resueltos en el PR #6 (2026-10-04)

| Issue | Resumen |
|---|---|
| ~~[#1](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/1)~~ | Resuelto: al crearse, la instancia se restaura desde el último snapshot (D12) |
| ~~[#2](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/2)~~ | Resuelto: el script lee su configuración de los outputs de Terraform (D16) |
| ~~[#3](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/3)~~ | Resuelto: no hay contraseña por defecto; se genera una y se persiste (D17) |
| ~~[#4](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/4)~~ | Resuelto: la AMI se resuelve por región (D10) |
| ~~[#5](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/5)~~ | Resuelto: key pair opcional; el backup aborta si no se confirma la detención (D14) |

### Abiertos (revisión del plan, 2026-10-04; ver D20)

| Issue | Resumen | Prioridad |
|---|---|---|
| [#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7) | La `t3.large` (8 GiB, CPU burstable) no alcanza para FalopaServer (`-Xmx8g`, 257 mods); revisar también `pz_branch` | 1 |
| [#8](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/8) | La configuración del servidor (ini, SandboxVars, mods) no está gestionada: vive solo en el disco | 2 |
| [#9](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/9) | Reemplazar destroy/snapshot/restore por stop/start con Elastic IP (la IP cambia en cada sesión) | 3 |
| [#10](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/10) | No hay backups mientras el servidor corre; los snapshots no tienen retención (DLM) | 3 |
| [#13](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/13) | Sin contraseña de ingreso ni whitelist: cualquiera con la IP puede entrar | 4 |
| [#11](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/11) | `sa-east-1` daría ~40 ms desde Argentina contra ~130–150 ms en `us-east-1` | — |
| [#12](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/12) | Endurecimiento: backend remoto, bucket S3 redundante, versión fija del repo (ya configurable con `repo_branch`), SSH restringido | — |

### Resueltos con la prueba en VM local (2026-10-05)

| Issue | Resumen |
|---|---|
| ~~[#14](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/14)~~ | Pruebas locales con una VM que imita la EC2 (D23) |
| ~~[#15](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/15)~~ | La instalación del juego fallaba en silencio por el directorio de trabajo de pzsvrtool (D24) |
