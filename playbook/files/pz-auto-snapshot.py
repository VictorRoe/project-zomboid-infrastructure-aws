#!/usr/bin/env python3
"""Snapshot automático del disco del mundo, hecho por la propia instancia.

Lo corre pz-auto-snapshot.timer (systemd) una vez por día: si la EC2 está apagada el
timer no corre, así que solo hay snapshots de los días en que estuvo prendida (y si a la
hora programada estaba apagada, Persistent=true lo corre al volver a prenderla).

  1. Identifica la instancia y la región por IMDSv2. Fuera de EC2 (la VM local) no hace nada.
  2. Busca el volumen de esta instancia con el tag pz-world-volume=<servidor>.
  3. Si el último automático tiene menos de PZ_SNAPSHOT_MIN_HOURS, no hace otro.
  4. Crea el snapshot con los tags pz-backup=auto, pz-consistency=crash (el juego puede
     estar escribiendo; la restauración automática no los elige) y pz-server.
  5. Rotación: conserva los PZ_SNAPSHOT_RETAIN automáticos más nuevos de este servidor y
     borra los demás, solo si están completados. Nunca toca los manuales.

Configuración por entorno (/etc/pz-auto-snapshot.env): PZ_SERVER_NAME, PZ_SNAPSHOT_RETAIN,
PZ_SNAPSHOT_MIN_HOURS. Credenciales: el rol de la instancia (permisos mínimos, ver Terraform).
"""
import datetime
import os
import sys
import urllib.error
import urllib.request

IMDS = os.environ.get("PZ_IMDS_URL", "http://169.254.169.254")


def log(msg):
    print(f"pz-auto-snapshot: {msg}", flush=True)


def imds(path, token):
    req = urllib.request.Request(f"{IMDS}/latest/{path}", headers={"X-aws-ec2-metadata-token": token})
    with urllib.request.urlopen(req, timeout=3) as r:
        return r.read().decode()


def instance_identity():
    """(instance_id, region) o None fuera de EC2."""
    try:
        req = urllib.request.Request(f"{IMDS}/latest/api/token", method="PUT",
                                     headers={"X-aws-ec2-metadata-token-ttl-seconds": "300"})
        with urllib.request.urlopen(req, timeout=3) as r:
            token = r.read().decode()
        return imds("meta-data/instance-id", token), imds("meta-data/placement/region", token)
    except (urllib.error.URLError, OSError):
        return None


def tag(resource, key):
    return next((t["Value"] for t in resource.get("Tags", []) if t["Key"] == key), None)


def main():
    server = os.environ["PZ_SERVER_NAME"]
    retain = int(os.environ.get("PZ_SNAPSHOT_RETAIN", "4"))
    min_hours = float(os.environ.get("PZ_SNAPSHOT_MIN_HOURS", "12"))
    if retain < 1:
        sys.exit("PZ_SNAPSHOT_RETAIN tiene que ser >= 1")

    identity = instance_identity()
    if identity is None:
        log("no hay metadatos de EC2 (no es una instancia de AWS); no se hace nada")
        return 0
    instance_id, region = identity

    import boto3  # Solo en EC2: la VM local no necesita boto3 para el chequeo anterior.
    ec2 = boto3.client("ec2", region_name=region)

    volumes = ec2.describe_volumes(Filters=[
        {"Name": "attachment.instance-id", "Values": [instance_id]},
        {"Name": "tag:pz-world-volume", "Values": [server]},
    ])["Volumes"]
    if len(volumes) != 1:
        log(f"ERROR: se esperaba un volumen con pz-world-volume={server} en {instance_id}, hay {len(volumes)}")
        return 1
    volume_id = volumes[0]["VolumeId"]

    def autos():
        snaps = ec2.describe_snapshots(OwnerIds=["self"], Filters=[
            {"Name": "tag:pz-backup", "Values": ["auto"]},
            {"Name": "tag:pz-server", "Values": [server]},
        ])["Snapshots"]
        return sorted(snaps, key=lambda s: s["StartTime"], reverse=True)

    now = datetime.datetime.now(datetime.timezone.utc)
    existing = autos()
    if existing and now - existing[0]["StartTime"] < datetime.timedelta(hours=min_hours):
        log(f"el último automático ({existing[0]['SnapshotId']}) tiene menos de {min_hours:g} h; no se hace otro")
    else:
        os.sync()
        snap = ec2.create_snapshot(
            VolumeId=volume_id,
            Description=f"Snapshot automático diario de {server} ({instance_id})",
            TagSpecifications=[{"ResourceType": "snapshot", "Tags": [
                {"Key": "Name", "Value": "pz-world-data-snapshot-auto"},
                {"Key": "pz-backup", "Value": "auto"},
                {"Key": "pz-consistency", "Value": "crash"},
                {"Key": "pz-server", "Value": server},
            ]}],
        )
        log(f"snapshot creado: {snap['SnapshotId']} de {volume_id}")

    deleted = 0
    for s in autos()[retain:]:
        # Solo snapshots automáticos de este servidor (el filtro y el rol lo garantizan) y completados.
        if tag(s, "pz-backup") != "auto" or tag(s, "pz-server") != server or s["State"] != "completed":
            continue
        ec2.delete_snapshot(SnapshotId=s["SnapshotId"])
        log(f"rotación: borrado {s['SnapshotId']} ({s['StartTime']:%Y-%m-%d %H:%M})")
        deleted += 1
    log(f"listo; se conservan los {retain} automáticos más nuevos ({deleted} borrados)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
