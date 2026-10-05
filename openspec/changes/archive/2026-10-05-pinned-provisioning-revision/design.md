# Design

## Decisiones

- **Solo SHA completo:** sin tags (requerirían verificar a qué commit apuntan); minúsculas para comparar con `rev-parse`.
- **Obtención:** fetch de `repo_branch`; si el commit no está, `git fetch origin <sha>` (GitHub admite commits alcanzables). `checkout --force --detach` descarta cambios locales, como el `reset --hard` anterior.
- **Script aparte en base64:** `pz-provision.sh` es un archivo normal (shellcheck, tests con repos git locales) y entra en `user_data` con `filebase64`; el `user_data` queda en ~6 KB.
- **`ignore_changes` de `user_data`:** un commit nuevo no debe reiniciar el servidor; se aplica con `pz-ctl.sh provision` (`pz-provision --commit`), que solo persiste el commit en `/etc/pz-provision.env` si el playbook termina bien.
- **VM local:** `repo_url` admite `http://10.0.2.2:<puerto>/…` (host de QEMU, inalcanzable desde EC2); espejo servido con `python3 -m http.server` (git "dumb http").

## Riesgos / Compromisos

- [Sin valor por defecto] → el operador tiene que fijar el SHA; documentado en operations.md.
- [Dependencias no fijadas: apt, PPA de Ansible, build del juego, mods] → documentado como límite.
