# Design

## Contexto

El host de desarrollo tiene KVM, QEMU 10, `qemu-img`, `cloud-localds` y 62 GB de RAM. El `user_data` es un script de shell renderizado desde `terraform/templates/user_data.sh.tftpl`; en la EC2 la clave SSH la inyecta AWS por metadatos, no el `user_data`.

## Objetivos / No objetivos

**Objetivos:** ejecutar el `user_data` real, sin cambios, en una VM lo más parecida posible a la EC2; automatizar las comprobaciones; poder jugar contra la VM.

**No objetivos:** simular APIs de AWS (LocalStack); CI (la VM necesita KVM y descarga varios GB); ejercitar la actualización automática con una build nueva real.

## Decisiones

- **QEMU directo en lugar de libvirt/virt-install.** Corre como usuario, sin daemon ni red de libvirt; la red en modo usuario permite `hostfwd` para SSH (2222→22) y UDP 16261, 16262 y 8766. Alternativa: `virt-install` con `qemu:///session` y passt; más piezas para el mismo resultado.
- **Imagen:** `noble-server-cloudimg-amd64.img` de `cloud-images.ubuntu.com`, verificada contra `SHA256SUMS`; se guarda en `.local-vm/` y cada VM usa un overlay qcow2 de 40 GB sobre ella.
- **cloud-init NoCloud con user-data MIME multiparte:** una parte `text/cloud-config` con la clave SSH del usuario `ubuntu` (lo que en AWS hacen los metadatos) y una parte `text/x-shellscript` con el `user_data` renderizado tal cual. El MIME se arma con la librería estándar de Python; `meta-data` lleva `instance-id`.
- **Renderizado:** `terraform -chdir=terraform console -var repo_branch=<rama actual>` sobre `local.user_data`, igual que `make user-data-check`. La rama tiene que estar pusheada, porque la VM clona desde GitHub; el script lo verifica y aborta si no lo está.
- **Recursos:** 4 vCPU, 10 GB de RAM (el playbook exige ≥ 7500 MB y 2 vCPU), `-cpu host`, KVM.
- **Restauración:** se apaga la VM, se aplana el overlay a un qcow2 independiente (`qemu-img convert`) y se arranca una VM nueva con `instance-id` distinto. cloud-init lo trata como instancia nueva y vuelve a ejecutar `user_data`, que es exactamente lo que pasa con una AMI registrada desde un snapshot.
- **Backup contra la VM:** se corre `script/destroy-and-backup.sh` con los stubs de `tests/script/bin` para `aws` y `terraform`, pero con `ssh` real: el stub de terraform devuelve `public_ip=127.0.0.1` y se pasa `SSH_PORT=2222` y `SSH_KEY`. El script necesita `SSH_PORT` (cambio mínimo).
- **Comprobaciones:** por SSH (`cloud-init status --wait`, `systemctl --user is-active` con `XDG_RUNTIME_DIR`, `pgrep`, modo del archivo de contraseña, `ufw status`, `loginctl show-user`). Cada prueba imprime PASA/FALLA por chequeo y sale con error si alguno falla.
- **Estado:** todo en `.local-vm/` (ignorado por git); `make local-down` apaga y `make local-clean` borra discos y claves (la imagen base se conserva).

## Riesgos / Compromisos

- [La VM no es Nitro: el modo de arranque y el driver ENA no se prueban] → queda para la prueba en AWS.
- [UFW dentro de la VM con red en modo usuario] → el reenvío entra como tráfico al puerto destino, así que UFW se ejercita igual.
- [Descarga del juego lenta o falla de Steam] → tiempo límite amplio en la espera de aprovisionamiento (60 min) y el log de cloud-init se muestra al fallar.
- [La rama clonada no coincide con el checkout local] → el script exige que no haya commits sin pushear.
