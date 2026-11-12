"""Storage/HTTP boundaries. Real played games are tested by run_record_submission.py."""
import concurrent.futures
import copy
import http.client
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server"))
from round_records import RoundRecords, TILES, MAX_BODY
from room_directory import Handler


def sample(number=0):
    ring = sorted(TILES) * 4
    return {"mode": "single", "record": {"id": f"test-{number:08d}", "schema": 1,
        "initial": {"phase": "playing", "players": [{"seat": seat, "concealed": ring[seat * 13:seat * 13 + 13]} for seat in range(4)]},
        "wall": {"ring": ring, "drawn": [True] * 52 + [False] * 56, "head": 52, "tail": 107, "remaining": 56},
        "actions": [{"kind": "turn", "seat": 0, "decision": {"discard": "wan1"}, "elapsed_ms": 1}],
        "final": {"fingerprint": "a" * 64, "result": {"deltas": [0, 0, 0, 0]}}}}


class QuietHandler(Handler):
    def log_message(self, *_args):
        pass


class RecordTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "samples.sqlite3"
        self.store = RoundRecords(self.path)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_retention_newest_first_and_duplicate_does_not_reorder(self):
        for index in range(105):
            self.store.submit(sample(index))
        self.assertTrue(self.store.submit(sample(5))["duplicate"])
        newest = self.store.latest(3)
        self.assertEqual((newest["count"], newest["total"], newest["capacity"]), (3, 100, 100))
        self.assertEqual([row["id"] for row in newest["records"]], [f"test-{i:08d}" for i in (104, 103, 102)])
        self.assertEqual(len(self.store.latest(1000)["records"]), 100)

    def test_config_survives_restart_and_smaller_limit_prunes(self):
        for index in range(12):
            self.store.submit(sample(index))
        self.store.close()
        self.store = RoundRecords(self.path, 3)
        self.assertEqual(self.store.latest(10)["total"], 3)
        self.assertEqual(self.store.latest(10)["records"][-1]["id"], "test-00000009")

    def test_concurrent_submissions_are_atomic(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(self.store.submit, [sample(1)] * 20))
        self.assertEqual(sum(not row["duplicate"] for row in results), 1)
        self.assertEqual(self.store.latest(1)["total"], 1)

    def test_conflicting_record_cannot_overwrite(self):
        original = sample()
        self.store.submit(original)
        changed = copy.deepcopy(original)
        changed["record"]["final"]["result"]["deltas"] = [4, -4, 0, 0]
        with self.assertRaises(FileExistsError):
            self.store.submit(changed)
        self.assertEqual(self.store.latest(1)["records"][0]["record"], original["record"])

    def test_reject_incomplete_hidden_and_bad_shapes(self):
        invalid = [None, [], {}, {"mode": "other"}]
        for edit in (
            lambda r: r.update(final={}),
            lambda r: r.update(actions=[]),
            lambda r: r["initial"]["players"][1].update(concealed=["hidden0"] * 13),
            lambda r: r["wall"].update(ring=[{}] * 108),
            lambda r: r["wall"].update(remaining=100),
            lambda r: r["final"]["result"].update(deltas=[float("nan"), 0, 0, 0]),
            lambda r: r["final"]["result"].update(deltas=[10, 0, 0, 0]),
        ):
            item = sample()
            edit(item["record"])
            invalid.append(item)
        for item in invalid:
            with self.subTest(item=item), self.assertRaises(ValueError):
                self.store.submit(item)
        self.assertEqual(self.store.latest(1)["total"], 0)

    def test_bounds_and_rate_limit(self):
        for limit in (0, -1, 10001):
            with self.assertRaises(ValueError):
                self.store.latest(limit)
        self.assertTrue(all(self.store.allow_submit("one") for _ in range(60)))
        self.assertFalse(self.store.allow_submit("one"))
        self.assertTrue(self.store.allow_submit("two"))

    def test_http_upload_and_protected_samples(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), QuietHandler)
        server.records = self.store
        server.records_api_key = "test-analysis-key"
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def request(method, path, body=None, key="", headers=None):
            conn = http.client.HTTPConnection(*server.server_address, timeout=3)
            try:
                conn.request(method, path, json.dumps(body) if body is not None else None, {"Authorization": "Bearer " + key, **(headers or {})})
                response = conn.getresponse()
                return response.status, json.loads(response.read())
            finally:
                conn.close()
        try:
            self.assertEqual(request("POST", "/round-records", sample())[0], 201)
            self.assertEqual(request("POST", "/round-records", sample())[0], 200)
            self.assertEqual(request("GET", "/round-records?limit=1")[0], 401)
            self.assertEqual(request("GET", "/round-records?limit=1", key="wrong")[0], 401)
            code, response = request("GET", "/round-records?limit=1", key="test-analysis-key")
            self.assertEqual(code, 200)
            self.assertEqual(response["records"][0]["record"], sample()["record"])
            self.assertEqual(request("GET", "/round-records?limit=no", key="test-analysis-key")[0], 400)
            self.assertEqual(request("POST", "/round-records", headers={"Content-Length": str(MAX_BODY + 1)})[0], 413)
            self.assertEqual(request("POST", "/round-records", {})[0], 400)
            server.records_api_key = ""
            self.assertEqual(request("GET", "/round-records?limit=1")[0], 503)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(3)


if __name__ == "__main__":
    unittest.main()
