"""Tests offline de playbook/files/pz-auto-snapshot.py: IMDS falso en localhost y boto3
reemplazado por un cliente simulado. Nada llega a AWS. Uso: python3 -m unittest (make snapshot-test)."""
import contextlib
import datetime
import http.server
import importlib.util
import io
import os
import sys
import threading
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "playbook", "files", "pz-auto-snapshot.py")
NOW = datetime.datetime.now(datetime.timezone.utc)


class FakeImds(http.server.BaseHTTPRequestHandler):
    def do_PUT(self):
        self._send("token-123")

    def do_GET(self):
        if self.headers.get("X-aws-ec2-metadata-token") != "token-123":
            self.send_response(401); self.end_headers(); return
        body = {"/latest/meta-data/instance-id": "i-self",
                "/latest/meta-data/placement/region": "sa-east-1"}.get(self.path)
        if body is None:
            self.send_response(404); self.end_headers(); return
        self._send(body)

    def _send(self, body):
        self.send_response(200); self.end_headers(); self.wfile.write(body.encode())

    def log_message(self, *args):
        pass


def snap(sid, hours_ago, server="w1", backup="auto", state="completed"):
    return {"SnapshotId": sid, "StartTime": NOW - datetime.timedelta(hours=hours_ago), "State": state,
            "Tags": [{"Key": "pz-backup", "Value": backup}, {"Key": "pz-server", "Value": server}]}


class FakeEc2:
    """Simula los filtros que usa el script; registra las llamadas que modifican."""

    def __init__(self, volumes, snapshots, fail_create=False):
        self.volumes, self.snapshots, self.fail_create = volumes, snapshots, fail_create
        self.created, self.deleted = [], []

    def describe_volumes(self, Filters):
        f = {x["Name"]: x["Values"] for x in Filters}
        assert f["attachment.instance-id"] == ["i-self"]
        return {"Volumes": [v for v in self.volumes if v["server"] in f["tag:pz-world-volume"]]}

    def describe_snapshots(self, OwnerIds, Filters):
        f = {x["Name"]: x["Values"] for x in Filters}
        def ok(s):
            tags = {t["Key"]: t["Value"] for t in s["Tags"]}
            return tags.get("pz-backup") in f["tag:pz-backup"] and tags.get("pz-server") in f["tag:pz-server"]
        return {"Snapshots": [s for s in self.snapshots if ok(s)]}

    def create_snapshot(self, VolumeId, Description, TagSpecifications):
        if self.fail_create:
            raise RuntimeError("UnauthorizedOperation")
        tags = TagSpecifications[0]["Tags"]
        self.created.append((VolumeId, {t["Key"]: t["Value"] for t in tags}))
        new = {"SnapshotId": "snap-new", "StartTime": NOW, "State": "pending", "Tags": tags}
        self.snapshots.append(new)
        return new

    def delete_snapshot(self, SnapshotId):
        self.deleted.append(SnapshotId)
        self.snapshots = [s for s in self.snapshots if s["SnapshotId"] != SnapshotId]


class AutoSnapshotTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeImds)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.imds = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def run_script(self, ec2, imds=None, **env):
        os.environ.update({"PZ_SERVER_NAME": "w1", "PZ_SNAPSHOT_RETAIN": "4", "PZ_SNAPSHOT_MIN_HOURS": "12",
                           "PZ_IMDS_URL": imds or self.imds})
        os.environ.update(env)
        regions = []
        sys.modules["boto3"] = types.SimpleNamespace(
            client=lambda name, region_name: regions.append(region_name) or ec2)
        spec = importlib.util.spec_from_file_location("pz_auto_snapshot", SCRIPT)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = mod.main()
        self.out, self.regions = out.getvalue(), regions
        return rc

    def test_creates_tagged_snapshot_of_own_volume(self):
        ec2 = FakeEc2([{"VolumeId": "vol-w1", "server": "w1"}], [])
        self.assertEqual(self.run_script(ec2), 0)
        self.assertEqual(self.regions, ["sa-east-1"])
        self.assertEqual(len(ec2.created), 1)
        volume, tags = ec2.created[0]
        self.assertEqual(volume, "vol-w1")
        self.assertEqual(tags, {"Name": "pz-world-data-snapshot-auto", "pz-backup": "auto",
                                "pz-consistency": "crash", "pz-server": "w1"})

    def test_rotation_keeps_newest_four(self):
        snaps = [snap(f"snap-{d}", 24 * d) for d in range(1, 7)]
        ec2 = FakeEc2([{"VolumeId": "vol-w1", "server": "w1"}], snaps)
        self.assertEqual(self.run_script(ec2), 0)
        # 6 viejos + 1 nuevo = 7; quedan el nuevo y los 3 más recientes.
        self.assertEqual(sorted(ec2.deleted), ["snap-4", "snap-5", "snap-6"])
        self.assertEqual(len(ec2.snapshots), 4)

    def test_never_touches_manual_or_other_servers(self):
        snaps = [snap(f"snap-{d}", 24 * d) for d in range(1, 5)]
        snaps += [snap("snap-manual", 500, backup="manual"), snap("snap-otro", 600, server="w2")]
        ec2 = FakeEc2([{"VolumeId": "vol-w1", "server": "w1"}], snaps)
        self.run_script(ec2)
        self.assertNotIn("snap-manual", ec2.deleted)
        self.assertNotIn("snap-otro", ec2.deleted)
        self.assertEqual(ec2.deleted, ["snap-4"])

    def test_skips_if_recent_snapshot_exists(self):
        ec2 = FakeEc2([{"VolumeId": "vol-w1", "server": "w1"}], [snap("snap-hoy", 2)])
        self.assertEqual(self.run_script(ec2), 0)
        self.assertEqual(ec2.created, [])
        self.assertIn("no se hace otro", self.out)

    def test_pending_old_snapshots_are_not_deleted(self):
        snaps = [snap(f"snap-{d}", 24 * d) for d in range(1, 5)] + [snap("snap-pend", 200, state="pending")]
        ec2 = FakeEc2([{"VolumeId": "vol-w1", "server": "w1"}], snaps)
        self.run_script(ec2)
        self.assertNotIn("snap-pend", ec2.deleted)

    def test_custom_retention(self):
        snaps = [snap(f"snap-{d}", 24 * d) for d in range(1, 4)]
        ec2 = FakeEc2([{"VolumeId": "vol-w1", "server": "w1"}], snaps)
        self.run_script(ec2, PZ_SNAPSHOT_RETAIN="1")
        self.assertEqual(sorted(ec2.deleted), ["snap-1", "snap-2", "snap-3"])

    def test_outside_ec2_does_nothing(self):
        ec2 = FakeEc2([], [])
        self.assertEqual(self.run_script(ec2, imds="http://127.0.0.1:9"), 0)
        self.assertEqual(self.regions, [])
        self.assertIn("no es una instancia de AWS", self.out)

    def test_missing_volume_fails(self):
        ec2 = FakeEc2([{"VolumeId": "vol-otro", "server": "w2"}], [])
        self.assertEqual(self.run_script(ec2), 1)
        self.assertEqual(ec2.created, [])

    def test_create_error_propagates_without_rotation(self):
        snaps = [snap(f"snap-{d}", 24 * d) for d in range(1, 7)]
        ec2 = FakeEc2([{"VolumeId": "vol-w1", "server": "w1"}], snaps, fail_create=True)
        with self.assertRaises(RuntimeError):
            self.run_script(ec2)
        self.assertEqual(ec2.deleted, [])


if __name__ == "__main__":
    unittest.main()
