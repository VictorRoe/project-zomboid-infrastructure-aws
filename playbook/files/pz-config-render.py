#!/usr/bin/env python3
"""Valida y renderiza la configuración del servidor que subió el operador.

  render --stage DIR --name NAME --out DIR --ports 16261,16262
      Valida el contrato de archivos y escribe en --out los archivos finales: el .ini
      con Password= (contraseña de ingreso, de la variable PZ_JOIN_PASSWORD) y
      RCONPassword= vacío (RCON desactivado). Los demás archivos se copian tal cual;
      el orden de Mods=, WorkshopItems= y Map= no se toca. Imprime JSON con la
      revisión (sha256 del resultado), el origen (archivo SOURCE) y el sha de cada archivo.
      Si la configuración es inválida, sale con 2 y lista los errores en stderr.

  drift --desired DIR --live DIR --name NAME
      Compara clave por clave el .ini renderizado con el que está en uso (el juego
      reescribe el archivo al arrancar, así que se comparan valores, no bytes).
      Imprime JSON con las claves distintas; nunca imprime valores.

Nunca imprime la contraseña ni otros valores del .ini.
"""
import argparse
import hashlib
import json
import os
import re
import sys

MANAGED_KEYS = ("Password", "RCONPassword")
LIST_KEYS = ("Mods", "WorkshopItems", "Map")
PLACEHOLDER = re.compile(r"<redacted>|CHANGE_?ME", re.IGNORECASE)


def files_for(name):
    return {
        "ini": f"{name}.ini",
        "sandbox": f"{name}_SandboxVars.lua",
        "spawnregions": f"{name}_spawnregions.lua",
        "spawnpoints": f"{name}_spawnpoints.lua",
    }


def ini_items(text):
    """(línea, clave) de cada asignación clave=valor, sin comentarios."""
    for line in text.splitlines():
        if line.startswith("#") or "=" not in line:
            continue
        yield line, line.split("=", 1)[0].strip()


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def render(args):
    names = files_for(args.name)
    errors = []
    allowed = set(names.values()) | {"SOURCE"}
    present = set(os.listdir(args.stage))
    for extra in sorted(present - allowed):
        errors.append(f"archivo no esperado: {extra} (contrato: {', '.join(sorted(allowed))})")
    missing = [names[k] for k in ("ini", "sandbox") if names[k] not in present]
    for f in missing:
        errors.append(f"falta {f} (los archivos tienen que llamarse como pz_server_name)")
    if missing:
        return fail(errors)

    try:
        texts = {k: read(os.path.join(args.stage, f)) for k, f in names.items() if f in present}
    except UnicodeDecodeError as e:
        return fail([f"un archivo no es UTF-8: {e}"])

    ini = texts["ini"]
    counts = {k: 0 for k in LIST_KEYS}
    values = {}
    for line, key in ini_items(ini):
        values.setdefault(key, line.split("=", 1)[1])
        if key in counts:
            counts[key] += 1
    for key, n in counts.items():
        if n != 1:
            errors.append(f"{names['ini']}: {key}= tiene que aparecer exactamente una vez (aparece {n})")
    if counts["Map"] == 1 and not values.get("Map", "").strip():
        errors.append(f"{names['ini']}: Map= no puede estar vacío")
    ports = [p for p in args.ports.split(",") if p]
    for key, want in zip(("DefaultPort", "UDPPort"), ports):
        if key in values and values[key].strip() != want:
            errors.append(f"{names['ini']}: {key}={values[key].strip()} no coincide con el puerto abierto {want} (security group/UFW)")

    for key, text in texts.items():
        for n, line in enumerate(text.splitlines(), 1):
            k = line.split("=", 1)[0].strip()
            if key == "ini" and k in MANAGED_KEYS:
                continue
            if PLACEHOLDER.search(line):
                errors.append(f"{names[key]}:{n}: valor de ejemplo/redactado (vaciarlo o completarlo; {k}= no lo gestiona Ansible)")
    if "SandboxVars" not in texts["sandbox"]:
        errors.append(f"{names['sandbox']}: no define SandboxVars")
    if "spawnregions" in texts and "SpawnRegions" not in texts["spawnregions"]:
        errors.append(f"{names['spawnregions']}: no define SpawnRegions()")
    if "spawnpoints" in texts and "SpawnPoints" not in texts["spawnpoints"]:
        errors.append(f"{names['spawnpoints']}: no define SpawnPoints()")

    password = os.environ.get("PZ_JOIN_PASSWORD", "")
    if not password:
        errors.append("falta PZ_JOIN_PASSWORD (contraseña de ingreso)")
    if errors:
        return fail(errors)

    out_lines, seen = [], set()
    for line in ini.splitlines():
        key = line.split("=", 1)[0].strip() if "=" in line and not line.startswith("#") else None
        if key == "Password":
            line = f"Password={password}"
        elif key == "RCONPassword":
            line = "RCONPassword="
        if key in MANAGED_KEYS:
            seen.add(key)
        out_lines.append(line)
    for key in MANAGED_KEYS:
        if key not in seen:
            out_lines.append(f"{key}={password if key == 'Password' else ''}")
    texts["ini"] = "\n".join(out_lines) + "\n"

    os.makedirs(args.out, mode=0o700, exist_ok=True)
    digest = hashlib.sha256()
    shas = {}
    for key in sorted(texts):
        data = texts[key].encode("utf-8")
        with open(os.path.join(args.out, names[key]), "wb") as f:
            f.write(data)
        shas[names[key]] = hashlib.sha256(data).hexdigest()
        digest.update(names[key].encode() + b"\0" + data + b"\0")

    source = {}
    if "SOURCE" in present:
        for line in read(os.path.join(args.stage, "SOURCE")).splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                source[k.strip()] = v.strip()
    print(json.dumps({"revision": digest.hexdigest(), "source": source, "files": shas}, sort_keys=True))
    return 0


def drift(args):
    name = files_for(args.name)["ini"]
    live_path = os.path.join(args.live, name)
    if not os.path.exists(live_path):
        print(json.dumps({"missing": True, "changed_keys": []}))
        return 0
    desired = {k: line for line, k in ini_items(read(os.path.join(args.desired, name)))}
    live = {k: line for line, k in ini_items(read(live_path))}
    changed = sorted(k for k, line in desired.items() if live.get(k) != line)
    print(json.dumps({"missing": False, "changed_keys": changed}))
    return 0


def fail(errors):
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    return 2


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("--stage", required=True)
    r.add_argument("--name", required=True)
    r.add_argument("--out", required=True)
    r.add_argument("--ports", default="16261,16262")
    d = sub.add_parser("drift")
    d.add_argument("--desired", required=True)
    d.add_argument("--live", required=True)
    d.add_argument("--name", required=True)
    args = p.parse_args()
    sys.exit(render(args) if args.cmd == "render" else drift(args))


if __name__ == "__main__":
    main()
