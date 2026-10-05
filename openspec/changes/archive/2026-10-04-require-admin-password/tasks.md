# Tasks

## 1. Validación

- [x] 1.1 Mover la validación de variables a `playbook/tasks/validate.yml`, definir `pz_admin_password: ""`, agregar reglas de robustez (≥12, lista de denegación, sin espacios/`=`) aplicadas solo cuando no está vacía, `quiet: true` en lugar de `no_log`; verificar con `make ansible-check`
- [x] 1.2 Agregar el ejecutor `tests/ansible/` + playbook de prueba que cubra contraseñas débiles, cortas, con `=`/espacios y robustas; verificar que `make ansible-test` pase

## 2. Generación y persistencia

- [x] 2.1 Agregar `playbook/tasks/admin_password.yml` (generar si falta, persistir con 0600, slurp en el fact efectivo, todo con `no_log`) y usar el fact efectivo en `pzsvrtool.config`; verificar pruebas de generación en la primera ejecución (longitud ≥ 24, modo 0600) y de reutilización en la segunda
- [x] 2.2 Actualizar el mensaje de depuración final con el comando de obtención (sin el valor); verificar que la salida de una ejecución de prueba no contenga la contraseña

## 3. Documentación y changelog

- [x] 3.1 Actualizar `docs/spec.md`, `docs/architecture.md`/`docs/flows.md` donde corresponda, agregar una entrada de decisión con fecha a `docs/decisions.md` y una entrada `[Unreleased]` en `CHANGELOG.md` que referencie el issue; verificar que los enlaces resuelvan y que los valores coincidan con el código
