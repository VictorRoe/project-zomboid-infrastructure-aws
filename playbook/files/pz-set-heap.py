#!/usr/bin/env python3
"""Fija el heap máximo de Java (-Xmx) en ProjectZomboid64.json.

Uso: pz-set-heap.py [--check] <ProjectZomboid64.json> <MiB>
Imprime "changed" u "ok". Con --check no escribe nada. Si un -Xms existente supera
el nuevo máximo, también lo baja (la JVM no arranca con Xms > Xmx). Escribe en el
mismo archivo (conserva dueño y permisos). Lo usan el playbook y pz-auto-update.sh,
porque reinstalar el juego restaura el JSON original.
"""
import json
import re
import sys

UNITS = {"": 1 / (1024 * 1024), "k": 1 / 1024, "m": 1, "g": 1024, "t": 1024 * 1024}


def size_mb(arg):
    m = re.fullmatch(r"-Xm[sx](\d+)([kmgt]?)", arg, re.IGNORECASE)
    return int(m.group(1)) * UNITS[m.group(2).lower()] if m else None


def main(argv):
    check = argv[:1] == ["--check"]
    if check:
        argv = argv[1:]
    if len(argv) != 2 or not argv[1].isdigit() or int(argv[1]) < 256:
        sys.exit("uso: pz-set-heap.py [--check] <ProjectZomboid64.json> <MiB >= 256>")
    path, mb = argv[0], int(argv[1])

    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    args = data.get("vmArgs")
    if not isinstance(args, list):
        sys.exit(f"{path}: no tiene una lista vmArgs")

    xmx = f"-Xmx{mb}m"
    new, placed = [], False
    for arg in args:
        if isinstance(arg, str) and arg.startswith("-Xmx"):
            if not placed:
                new.append(xmx)
                placed = True
            continue
        if isinstance(arg, str) and arg.startswith("-Xms") and (size_mb(arg) or 0) > mb:
            arg = f"-Xms{mb}m"
        new.append(arg)
    if not placed:
        new.insert(0, xmx)

    if new == args:
        print("ok")
        return
    print("changed")
    if not check:
        data["vmArgs"] = new
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent="\t")
            f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1:])
