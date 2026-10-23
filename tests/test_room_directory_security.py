import ipaddress
import json
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from room_directory import RoomDirectory, client_identity, rate_limit_key, token_digest


class _Process:
    def poll(self):
        return None

    def terminate(self):
        pass

    def wait(self, timeout=None):
        return 0


class _DeadProcess:
    def poll(self):
        return 1


class _RunningProcess:
    def poll(self):
        return None

    def terminate(self):
        pass

    def wait(self, timeout=None):
        return 0


class RoomDirectorySecurityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = RoomDirectory("godot", self.tmp.name, "127.0.0.1", max_rooms=4)

    def tearDown(self):
        self.directory.close()
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

    def test_ipv6_quota_is_aggregated_by_sixty_four(self):
        self.assertEqual(rate_limit_key("2001:db8:1:2::1"), "2001:db8:1:2::/64")
        self.assertEqual(rate_limit_key("::ffff:1.2.3.4"), "1.2.3.4")
        self.assertTrue(self.directory.allow_create("2001:db8:1:2::1"))
        self.assertTrue(self.directory.allow_create("2001:db8:1:2::2"))
        self.assertTrue(self.directory.allow_create("2001:db8:1:2::3"))
        self.assertFalse(self.directory.allow_create("2001:db8:1:2::4"))
        self.assertTrue(self.directory.allow_create("2001:db8:1:3::1"))

    def test_create_does_not_hold_directory_lock_while_waiting(self):
        ready = threading.Event()
        result = {}
        original_view = self.directory._view

        def slow_view(room):
            ready.wait(2)
            return {"number": "1234", "name": "slow", "players": 0, "started": False,
                    "host": "127.0.0.1", "port": room["port"]}

        def create_in_thread():
            try:
                result["room"] = self.directory.create("1234", "slow", "client")
            except Exception as error:
                result["error"] = error

        self.directory._view = slow_view
        self.directory._port_available = lambda _port: True
        with patch("room_directory.subprocess.Popen", return_value=_RunningProcess()):
            thread = threading.Thread(target=create_in_thread)
            thread.start()
            acquired = self.directory.lock.acquire(timeout=1)
            if acquired:
                self.directory.lock.release()
            ready.set()
            thread.join(3)
        self.assertTrue(acquired, "create must release the directory lock while waiting for Godot")
        self.assertNotIn("error", result)
        self.assertEqual(result["room"]["number"], "1234")
        self.directory._view = original_view

    def test_log_rotation_and_maintenance(self):
        log_path = self.directory.runtime / "1234.log"
        log_path.write_bytes(b"x" * (5 * 1024 * 1024))
        self.directory.max_log_bytes = 1024
        opened = self.directory._open_room_log("1234")
        opened.close()
        self.assertTrue((self.directory.runtime / "1234.log.1").exists())

        status = Path(self.tmp.name) / "dead.json"
        status.write_text("{}", encoding="utf-8")
        dead_log = (Path(self.tmp.name) / "dead.log").open("a")
        self.directory.rooms["999999"] = {"status": status, "process": _DeadProcess(), "log": dead_log}
        self.directory.start_maintenance(interval=0.05)
        deadline = time.monotonic() + 2
        while "999999" in self.directory.rooms and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertNotIn("999999", self.directory.rooms)

    def test_recover_live_room_after_directory_restart(self):
        status = self.directory.runtime / "live.json"
        status.write_text(json.dumps({"number": "777777", "port": 7699, "name": "recovered",
            "players": 1, "started": False, "updated": time.time()}), encoding="utf-8")
        restarted = RoomDirectory("godot", self.tmp.name, "127.0.0.1", max_rooms=4)
        self.assertIn("777777", restarted.rooms)
        self.assertTrue(restarted.has_room("777777"))
        status.write_text(json.dumps({"number": "777777", "port": 7699, "name": "recovered",
            "players": 1, "started": False, "updated": time.time() - 60}), encoding="utf-8")
        with restarted.lock:
            restarted._cleanup()
        self.assertNotIn("777777", restarted.rooms)

    def test_gme_nonce_replay_rejected(self):
        self.assertTrue(self.directory.consume_gme_nonce("0123456789abcdef"))
        self.assertFalse(self.directory.consume_gme_nonce("0123456789abcdef"))
        self.assertTrue(self.directory.consume_gme_nonce("fedcba9876543210"))

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

        hashed = Path(self.tmp.name) / "hashed.json"
        hashed.write_text(json.dumps({"number": "123456", "name": "x", "players": 1,
            "started": False, "updated": time.time(),
            "members": {"2": token_digest("secret")}, "host_token": token_digest("owner")}), encoding="utf-8")
        hashed_log = (Path(self.tmp.name) / "hashed.log").open("a")
        self.directory.rooms["123456"] = {"status": hashed, "process": _Process(), "log": hashed_log}
        self.assertTrue(self.directory.authenticate_member("123456", "1234562", "secret"))
        self.assertFalse(self.directory.authenticate_member("123456", "1234562", "wrong"))
        self.assertTrue(self.directory.authenticate_member("123456", "1234560", "owner"))
        hashed_log.close()


if __name__ == "__main__":
    unittest.main()
