# Arquitectura

Cómo encajan las piezas de este repo. Los valores actuales están en [spec.md](spec.md); los motivos, en [decisions.md](decisions.md); las secuencias paso a paso, en [flows.md](flows.md); los costos, en [costs.md](costs.md).

## Componentes

| Capa | Dónde | Responsabilidad |
|---|---|---|
| Estado remoto | `bootstrap/state-backend/` | Bucket S3 del estado de Terraform (versionado, cifrado, privado), con su propio estado local |
| Terraform | `terraform/` | Security group, EC2 (tamaño por `tier`) con un único disco raíz gp3, Elastic IP y el rol de IAM de la instancia para sus snapshots. Backend S3 con bloqueo |
| Arranque | `terraform/templates/user_data.sh.tftpl` + `pz-provision.sh` | Instala Ansible, obtiene **el commit fijado** de este repo (verifica `HEAD`) y ejecuta el playbook en la instancia |
| Ansible | `playbook/` | Usuario `pzserver`, swap, pzsvrtool, juego, heap, contraseñas, configuración subida, servicios systemd de usuario, actualización automática, UFW |
| Operación | `script/pz-ctl.sh`, `script/destroy-and-backup.sh` | Corren en la máquina del operador: sesiones, backups, configuración, contraseñas, reaprovisionar, baja |
| Prueba local | `local/vm.sh` | VM QEMU/KVM con la misma imagen y el mismo `user_data` que la EC2, que clona desde un servidor git en el host |

No hay CI ni pipeline de imágenes.

## Diagrama

```
 Máquina del operador                        AWS (aws_region)
┌───────────────────────────┐      ┌──────────────────────────────────────────────────┐
│ terraform apply ──────────┼────▶ │ S3 pz-tfstate-* (estado + .tflock)               │
│                           │      │ SG pz-server-sg: UDP 16261-16262, 8766           │
│ pz-ctl.sh                 │      │                  TCP 22 solo ssh_allowed_cidrs   │
│  start/stop ── aws ec2 ───┼────▶ │ Elastic IP ──▶ EC2 PZ-Server-Instance (tier)     │
│  backup ─── ssh + snapshot┼────▶ │   disco gp3 30 GB (pz-world-volume=<nombre>)     │
│  push-config ── ssh+tar ──┼────▶ │   └ cloud-init → pz-provision <commit fijo>      │
│  provision ─── ssh ───────┼────▶ │       └ git (este repo, público) → Ansible local │
│ destroy-and-backup.sh     │      │   └ timer: snapshot diario si está prendida (4)  │
└───────────────────────────┘      │ Snapshots pz-world-data-snapshot[-auto]          │
                                   └──────────────────────────────────────────────────┘
```

## Estructura en el host (después del playbook)

```
/etc/pz-provision.env                    # repo, rama, commit, nombre, heap, snapshots (de Terraform; sin secretos)
/usr/local/sbin/pz-auto-snapshot         # + /etc/pz-auto-snapshot.env y pz-auto-snapshot.{service,timer}
/usr/local/sbin/pz-provision             # obtiene el commit fijado y corre el playbook
/var/lib/pz-provision/revision           # commit aplicado, modo y fecha
/home/ubuntu/repo/                       # checkout (detached) de este repo
/home/pzserver/
├── pzsvrtool/
│   ├── pzsvrtool.config                 # nombre, admin, backups (0600)
│   ├── .admin_password / .join_password # admin root e ingreso de jugadores (0600)
│   ├── pz-auto-update.sh                # verificador de actualizaciones (timer)
│   ├── pz-set-heap.py, pz-config-render.py
│   ├── config-staged/                   # lo último que subió el operador (+ SOURCE)
│   ├── config-applied.json              # revisión y origen de la configuración en uso
│   └── config-backups/<fecha>/          # copias antes de cada aplicación (10)
├── Zomboid/Server/<nombre>.ini, _SandboxVars.lua, _spawn*.lua   # configuración en uso
├── Zomboid/Saves/Multiplayer/<nombre>/  # el mundo
├── pzserver/                            # juego (SteamCMD app 380870); ProjectZomboid64.json con -Xmx
└── .config/systemd/user/pzsvrtool@<nombre>.service.d/{keepalive,wait-config}.conf
/etc/systemd/system/user@<uid>.service.d/pzsvrtool.conf   # TimeoutStopSec=20m
/swapfile                                                 # 2 GB
```

El juego corre como **servicio systemd de usuario** `pzsvrtool@<nombre>.service` de `pzserver`, y **linger** lo mantiene activo desde el arranque. Cualquier llamada a `systemctl --user` desde otra cuenta necesita `XDG_RUNTIME_DIR=/run/user/<uid>`.

## Puntos de acoplamiento

- **Configuración del stack:** variables de Terraform → outputs → scripts del operador, y → `/etc/pz-provision.env` → playbook (`pz_server_name`, heap, espera de configuración). No hardcodear estos valores en otro lado.
- **Revisión del código:** `repo_commit` → `user_data` (solo al crear la instancia) y output → `pz-ctl.sh provision` (hosts en marcha). Los cambios de `user_data` se ignoran en una instancia existente.
- **Puertos:** se declaran en el security group (`terraform/main.tf`), en UFW (`pz_udp_ports`) y en el `.ini` (`DefaultPort`/`UDPPort`, validados al subir). Tienen que coincidir. El origen de SSH se filtra solo en el security group.
- **Tags de snapshot:** `Name=pz-world-data-snapshot` (consistente: lo escriben los scripts y lo elige la restauración automática) y `pz-world-data-snapshot-auto` (el timer de la instancia; solo se restaura a mano). `pz-world-volume=<nombre>` limita al disco de este servidor los permisos del rol de la instancia.
- **Configuración del juego:** el directorio del operador (git) → `config-staged` → renderizado (contraseña gestionada) → `Zomboid/Server`. Los nombres de archivo son `pz_server_name`.
- **Entrega del código:** `git` desde GitHub al arrancar, así que el repo tiene que ser público y el commit tiene que existir en `repo_branch` (o ser alcanzable por SHA).

## Problemas conocidos

### Resueltos en el PR #6 (2026-10-04)

#1 (restauración), #2 (configuración del backup), #3 (contraseña de admin), #4 (AMI por región), #5 (SSH y detención antes del snapshot), #14 (VM local) y #15 (instalación del juego). Ver D10–D24.

### Resueltos en este cambio (2026-10-05)

| Issue | Resumen | Decisión |
|---|---|---|
| ~~[#7](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/7)~~ | Tiers de tamaño (`estandar` = `m7i.large`), heap gestionado y RAM verificada (falta la prueba de carga real) | D33, D39 |
| ~~[#8](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/8)~~ | Configuración del juego provista por el operador, validada, versionada y aplicada con backup | D31 |
| ~~[#9](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/9)~~ | Sesiones con stop/start y Elastic IP | D29 |
| ~~[#10](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/10)~~ | Snapshot diario solo con la instancia prendida (se conservan 4) más backups consistentes a pedido | D30, D38 |
| ~~[#11](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/11)~~ | Comparación de regiones medida; se mantiene us-east-1 | D34 |
| ~~[#12](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/12)~~ | Seguimiento de #16–#19 | — |
| ~~[#13](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/13)~~ | Contraseña de ingreso gestionada | D32 |
| ~~[#16](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/16)~~ | Estado remoto en S3 con bloqueo | D27 |
| ~~[#17](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/17)~~ | Bucket de metadatos retirado | D28 |
| ~~[#18](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/18)~~ | Commit fijo y verificado | D25 |
| ~~[#19](https://github.com/VictorRoe/project-zomboid-infrastructure-aws/issues/19)~~ | SSH solo desde redes administrativas | D26 |

### Pendiente de verificar en AWS (D37)

La búsqueda real de la AMI, el arranque de una imagen restaurada, la Elastic IP, el timer de snapshots con los permisos mínimos del rol, la migración del estado al backend S3 y su bloqueo, stop/start real, la prueba de carga y el ingreso con un cliente real (contraseña correcta e incorrecta).
