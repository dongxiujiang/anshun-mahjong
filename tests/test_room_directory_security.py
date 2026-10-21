import ipaddress
import json
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from room_directory import RoomDirectory, client_identity


class _Process:
    def poll(self):
        return None


class RoomDirectorySecurityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = RoomDirectory("godot", self.tmp.name, "127.0.0.1", max_rooms=4)

    def tearDown(self):
        self.tmp.cleanup()

    def test_forwarded_header_ignored_for_direct_clients(self):
        trusted = [ipaddress.ip_network("127.0.0.1/32")]
        self.assertEqual(client_identity("8.8.8.8", "1.2.3.4", trusted), "8.8.8.8")
        self.assertEqual(client_identity("127.0.0.1", "1.2.3.4", trusted), "1.2.3.4")
        self.assertEqual(client_identity("127.0.0.1", "spoof, 1.2.3.4", trusted), "1.2.3.4")
        self.assertEqual(client_identity("127.0.0.1", "spoof, 127.0.0.1", trusted), "spoof")

    def test_create_rate_limit(self):
        self.assertTrue(self.directory.allow_create("a"))
        self.assertTrue(self.directory.allow_create("a"))
        self.assertTrue(self.directory.allow_create("a"))
        self.assertFalse(self.directory.allow_create("a"))
        self.assertTrue(self.directory.allow_create("b"))

    def test_gme_auth_requires_member_token(self):
        status = Path(self.tmp.name) / "status.json"
        status.write_text(json.dumps({"number": "123456", "name": "x", "players": 1,
            "started": False, "updated": time.time(), "members": {"2": "secret"}, "host_token": "owner"}), encoding="utf-8")
        log = (Path(self.tmp.name) / "room.log").open("a")
        self.directory.rooms["123456"] = {"status": status, "process": _Process(), "log": log}
        self.assertTrue(self.directory.authenticate_member("123456", "1234562", "secret"))
        self.assertFalse(self.directory.authenticate_member("123456", "1234562", "wrong"))
        self.assertFalse(self.directory.authenticate_member("123456", "1234561", "secret"))
        self.assertFalse(self.directory.authenticate_member("123456", "1234562", ""))
        self.assertTrue(self.directory.authenticate_member("123456", "1234560", "owner"))
        self.assertFalse(self.directory.authenticate_member("123456", "1234561", "owner"))
        log.close()


if __name__ == "__main__":
    unittest.main()
