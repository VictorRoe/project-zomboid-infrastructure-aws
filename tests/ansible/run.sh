#!/bin/bash
# Tests offline del manejo de la contraseña de admin del playbook.
# Los chequeos van entre comillas simples a propósito: check() los evalúa tras cada ejecución.
# shellcheck disable=SC2016,SC2034
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAY="$HERE/test_admin_password.yml"
PASS=0
FAIL=0

# run_case <nombre> <home> [args extra de ansible...]
run_case() {
  CASE="$1"; HOME_DIR="$2"; shift 2
  PWFILE="$HOME_DIR/pzsvrtool/.admin_password"
  OUT="$(ANSIBLE_NOCOLOR=1 ansible-playbook -i localhost, "$PLAY" \
    -e "pz_user=$(id -un)" -e "pz_home=$HOME_DIR" "$@" 2>&1)"
  RC=$?
}

check() {
  if eval "$2"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FALLA [$CASE] $1"
    printf '%s\n' "$OUT" | sed 's/^/    | /'
  fi
}

mode_of() { stat -c '%a' "$1"; }

for weak in test Test PASSWORD changeme CHANGE_ME_USE_ANSIBLE_VAULT Short1 'abcdefgh=ijklmn' 'abcdefgh ijklmn'; do
  H="$(mktemp -d)"
  run_case "rechaza '$weak'" "$H" -e "pz_admin_password='$weak'"
  check "falla" '[ "$RC" -ne 0 ]'
  check "explica la regla" 'grep -q "al menos 12 caracteres" <<<"$OUT"'
  check "no escribe nada" '[ ! -e "$PWFILE" ]'
done

H="$(mktemp -d)"
STRONG="Str0ngPassw0rd16"
run_case "acepta contraseña fuerte" "$H" -e "pz_admin_password=$STRONG"
check "pasa" '[ "$RC" -eq 0 ]'
check "la guarda" '[ "$(cat "$PWFILE")" = "$STRONG" ]'
check "modo 0600" '[ "$(mode_of "$PWFILE")" = 600 ]'
check "el valor no aparece en la salida" '! grep -qF "$STRONG" <<<"$OUT"'

H="$(mktemp -d)"
run_case "genera si está vacía" "$H"
GEN="$(cat "$PWFILE" 2>/dev/null)"
check "pasa" '[ "$RC" -eq 0 ]'
check "aleatoria alfanumérica >= 24 caracteres" '[[ "$GEN" =~ ^[A-Za-z0-9]{24,}$ ]]'
check "modo 0600" '[ "$(mode_of "$PWFILE")" = 600 ]'
check "se usa como contraseña efectiva" 'grep -q "EFFECTIVE_LEN=${#GEN}" <<<"$OUT"'
check "el valor no aparece en la salida" '! grep -qF "$GEN" <<<"$OUT"'

run_case "reutiliza la contraseña generada" "$H"
check "pasa" '[ "$RC" -eq 0 ]'
check "sin cambios" '[ "$(cat "$PWFILE")" = "$GEN" ]'

H2="$(mktemp -d)"
run_case "el valor por defecto no es 'test'" "$H2"
check "el valor generado no es un débil conocido" '[ "$(cat "$PWFILE")" != test ]'

# =============================================================================
# Heap (#7), contraseña de ingreso (#13) y configuración del servidor (#8)
# =============================================================================
GS_PLAY="$HERE/test_game_settings.yml"
FIXTURE="$HERE/fixtures/world1"

# gs_case <nombre> <home> [args extra de ansible...]
gs_case() {
  CASE="$1"; HOME_DIR="$2"; shift 2
  OUT="$(ANSIBLE_NOCOLOR=1 ansible-playbook -i localhost, "$GS_PLAY" \
    -e "pz_user=$(id -un)" -e "pz_home=$HOME_DIR" -e pz_server_name=world1 \
    -e "{\"pz_files_dir\": \"$HERE/../../playbook/files\", \"pz_as_user\": [], \"pz_manage_service\": false}" \
    "$@" 2>&1 </dev/null)"
  RC=$?
}
changed_count() { sed -n 's/.*changed=\([0-9]*\).*/\1/p' <<<"$OUT" | tail -1; }
new_home() {
  local h
  h="$(mktemp -d)"
  mkdir -p "$h/pzserver"
  printf '{\n\t"mainClass": "x",\n\t"vmArgs": [\n\t\t"-Djava.awt.headless=true",\n\t\t"-Xmx4g",\n\t\t"-Xms6g"\n\t]\n}\n' > "$h/pzserver/ProjectZomboid64.json"
  printf '%s' "$h"
}
stage() { rm -rf "$1/pzsvrtool/config-staged"; mkdir -p "$1/pzsvrtool"; cp -r "$2" "$1/pzsvrtool/config-staged"; }

H="$(new_home)"
INI="$H/Zomboid/Server/world1.ini"
JSON="$H/pzserver/ProjectZomboid64.json"
gs_case "sin configuración subida" "$H"
JOIN="$(cat "$H/pzsvrtool/.join_password" 2>/dev/null)"
check "pasa" '[ "$RC" -eq 0 ]'
check "heap fijado en ProjectZomboid64.json" 'grep -q "\"-Xmx4096m\"" "$JSON" && ! grep -q "Xmx4g" "$JSON"'
check "un -Xms mayor que el heap se baja (la JVM no arrancaría)" 'grep -q "\"-Xms4096m\"" "$JSON" && ! grep -q Xms6g "$JSON"'
check "el resto de vmArgs no cambia" 'grep -q "java.awt.headless" "$JSON"'
check "contraseña de ingreso aleatoria de 24 caracteres" '[[ "$JOIN" =~ ^[A-Za-z0-9]{24}$ ]]'
check "archivo 0600" '[ "$(mode_of "$H/pzsvrtool/.join_password")" = 600 ]'
check "distinta de la de admin" '[ "$JOIN" != "$(cat "$H/pzsvrtool/.admin_password")" ]'
check "el .ini lleva la contraseña antes del primer arranque" 'grep -qxF "Password=$JOIN" "$INI" && [ "$(mode_of "$INI")" = 600 ]'
check "la contraseña no aparece en la salida" '! grep -qF "$JOIN" <<<"$OUT"'
check "pediría detener el juego" 'grep -q "needs_stop=True" <<<"$OUT"'

gs_case "segunda ejecución sin cambios" "$H"
check "pasa sin cambios" '[ "$RC" -eq 0 ] && [ "$(changed_count)" = 0 ]'
check "no detendría el juego" 'grep -q "needs_stop=False" <<<"$OUT"'
check "conserva la contraseña" '[ "$(cat "$H/pzsvrtool/.join_password")" = "$JOIN" ]'

gs_case "heap distinto" "$H" -e pz_java_xmx_mb=8192
check "lo cambia y pide detener el juego" '[ "$RC" -eq 0 ] && grep -q "\"-Xmx8192m\"" "$JSON" && grep -q "needs_stop=True" <<<"$OUT"'
check "un -Xms menor que el heap no cambia" 'grep -q "\"-Xms4096m\"" "$JSON"'
gs_case "heap de vuelta" "$H"

stage "$H" "$FIXTURE"
printf 'source=git:test@abc123\n' > "$H/pzsvrtool/config-staged/SOURCE"
gs_case "configuración subida" "$H"
STATE="$H/pzsvrtool/config-applied.json"
check "pasa" '[ "$RC" -eq 0 ]'
check "aplica y pide detener el juego" 'grep -q "applied_now=True" <<<"$OUT" && grep -q "needs_stop=True" <<<"$OUT"'
check "Password= gestionada (no el placeholder)" 'grep -qxF "Password=$JOIN" "$INI" && ! grep -q redacted "$INI"'
check "RCON desactivado" 'grep -qx "RCONPassword=" "$INI"'
check "el resto del .ini queda igual, en orden" 'diff <(grep -v "^Password=\|^RCONPassword=" "$FIXTURE/world1.ini") <(grep -v "^Password=\|^RCONPassword=" "$INI")'
check "SandboxVars y spawnregions copiados" 'cmp -s "$FIXTURE/world1_SandboxVars.lua" "$H/Zomboid/Server/world1_SandboxVars.lua" && cmp -s "$FIXTURE/world1_spawnregions.lua" "$H/Zomboid/Server/world1_spawnregions.lua"'
check "registro con revisión y origen" 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert len(d[\"revision\"]) == 64 and d[\"source\"][\"source\"] == \"git:test@abc123\"" "$STATE"'
check "copia de la configuración anterior" '[ "$(ls "$H/pzsvrtool/config-backups" | wc -l)" = 1 ] && grep -qxF "Password=$JOIN" "$H"/pzsvrtool/config-backups/*/world1.ini'
check "la contraseña no aparece en la salida" '! grep -qF "$JOIN" <<<"$OUT"'

gs_case "re-ejecución sin configuración nueva" "$H"
check "pasa sin cambios ni copias nuevas" '[ "$RC" -eq 0 ] && [ "$(changed_count)" = 0 ] && [ "$(ls "$H/pzsvrtool/config-backups" | wc -l)" = 1 ]'
check "no detendría el juego" 'grep -q "needs_stop=False" <<<"$OUT"'

sed -i 's/^MaxPlayers=4$/MaxPlayers=16/' "$INI"
gs_case "edición manual en el host" "$H"
check "pasa" '[ "$RC" -eq 0 ]'
check "avisa la clave modificada" 'grep -q "difiere de la última configuración subida en MaxPlayers" <<<"$OUT"'
check "no pisa la edición" 'grep -qx "MaxPlayers=16" "$INI"'

sleep 1
sed -i 's/StartMonth = 12/StartMonth = 11/' "$H/pzsvrtool/config-staged/world1_SandboxVars.lua"
gs_case "configuración nueva tras una edición manual" "$H"
check "aplica la nueva" '[ "$RC" -eq 0 ] && grep -q "StartMonth = 11" "$H/Zomboid/Server/world1_SandboxVars.lua"'
check "la edición manual queda en la copia" '[ "$(ls "$H/pzsvrtool/config-backups" | wc -l)" = 2 ] && grep -qx "MaxPlayers=16" "$(ls -d "$H"/pzsvrtool/config-backups/*/ | sort | tail -1)world1.ini"'
check "y el .ini vuelve a la versión subida" 'grep -qx "MaxPlayers=4" "$INI"'

cp "$INI" "$H/before.ini"
BAD="$(mktemp -d)"
cp "$FIXTURE"/* "$BAD/"
sed -i 's/^Map=.*/Map=/; s/^DefaultPort=.*/DefaultPort=27000/' "$BAD/world1.ini"
printf 'DiscordToken=<redacted>\nMods=x\n' >> "$BAD/world1.ini"
printf 'x\n' > "$BAD/notas.txt"
stage "$H" "$BAD"
gs_case "configuración inválida" "$H"
check "falla" '[ "$RC" -ne 0 ]'
check "explica cada error" 'grep -q "Map= no puede estar vacío\|Mods= tiene que aparecer exactamente una vez" <<<"$OUT" && grep -q "DefaultPort=27000" <<<"$OUT" && grep -q "redactado" <<<"$OUT" && grep -q "notas.txt" <<<"$OUT"'
check "no toca la configuración en uso" 'cmp -s "$H/before.ini" "$INI"'
check "no imprime la contraseña" '! grep -qF "$JOIN" <<<"$OUT"'

stage "$H" "$FIXTURE"
gs_case "volver a la configuración válida" "$H"
gs_case "rotar la contraseña de ingreso" "$H" -e pz_join_password_rotate=true
NEWJOIN="$(cat "$H/pzsvrtool/.join_password")"
check "genera otra" '[ "$RC" -eq 0 ] && [ "$NEWJOIN" != "$JOIN" ] && [[ "$NEWJOIN" =~ ^[A-Za-z0-9]{24}$ ]]'
check "la aplica al .ini (reinicio)" 'grep -qxF "Password=$NEWJOIN" "$INI" && grep -q "needs_stop=True" <<<"$OUT"'

gs_case "contraseña provista" "$H" -e pz_join_password=JoinPassw0rdOk
check "la usa" '[ "$RC" -eq 0 ] && grep -qx "Password=JoinPassw0rdOk" "$INI"'

gs_case "límite de copias" "$H" -e pz_config_backup_keep=1 -e pz_join_password=OtraPassw0rd99
check "conserva solo la más nueva" '[ "$RC" -eq 0 ] && [ "$(ls "$H/pzsvrtool/config-backups" | wc -l)" = 1 ]'

H3="$(new_home)"
gs_case "contraseña de ingreso igual a la de admin" "$H3" -e pz_admin_password=MismaPassw0rd1 -e pz_join_password=MismaPassw0rd1
check "falla" '[ "$RC" -ne 0 ] && grep -q "distinta de pz_admin_password" <<<"$OUT"'
check "sin archivo de ingreso" '[ ! -e "$H3/pzsvrtool/.join_password" ]'

for weak in test changeme 'corta123' 'con espacios 123'; do
  H4="$(new_home)"
  gs_case "rechaza contraseña de ingreso '$weak'" "$H4" -e "pz_join_password='$weak'"
  check "falla" '[ "$RC" -ne 0 ] && grep -q "pz_join_password tiene que" <<<"$OUT"'
done

H5="$(new_home)"
gs_case "nombre de archivos distinto de pz_server_name" "$H5"
stage "$H5" "$FIXTURE"
gs_case "nombre de archivos distinto de pz_server_name" "$H5" -e pz_server_name=otro
check "falla explicando el contrato" '[ "$RC" -ne 0 ] && grep -q "falta otro.ini" <<<"$OUT"'

echo "tests de ansible: $PASS pasaron, $FAIL fallaron"
[ "$FAIL" -eq 0 ]
