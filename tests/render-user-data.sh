#!/bin/bash
# Renderiza offline el user_data de la EC2 (local.user_data) y lo imprime.
# Uso: tests/render-user-data.sh [-var nombre=valor ...]
# terraform console exige un backend inicializado, así que se usa una copia de
# terraform/ sin backend.tf (con los providers ya descargados). Sin AWS.
set -euo pipefail

TF="${TF:-terraform}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$SRC"/*.tf "$SRC/.terraform.lock.hcl" "$TMP/"
cp -r "$SRC/templates" "$TMP/"
rm -f "$TMP/backend.tf"
"$TF" -chdir="$SRC" init -backend=false -input=false >/dev/null
TF_PLUGIN_CACHE_DIR="" "$TF" -chdir="$TMP" init -backend=false -input=false \
  -plugin-dir="$SRC/.terraform/providers" >/dev/null
# Sin un commit explícito se usa uno de ejemplo (repo_commit es obligatorio).
echo 'local.user_data' | "$TF" -chdir="$TMP" console -var repo_commit=0123456789abcdef0123456789abcdef01234567 "$@" | sed '1d;$d'
