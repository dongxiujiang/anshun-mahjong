"""Real completed-tape upload with the same Godot rules verifier used by the service."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import hashlib
import hmac
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from room_directory import HttpServer, RoomDirectory
from round_records import RecordError


def request(url, data=None, token=None, signing_key=None, signature=None, raw=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = json.dumps(data, separators=(",", ":")).encode() if data is not None else None
    if signing_key is not None:
        headers["X-Dongxiu-Record-Signature"] = hmac.new(signing_key, body, hashlib.sha256).hexdigest()
    if signature is not None:
        headers["X-Dongxiu-Record-Signature"] = signature
    if raw is not None:
        body = raw
    try:
        with urlopen(Request(url, data=body, headers=headers), timeout=20) as response:
            return response.status, json.load(response)
    except HTTPError as error:
        return error.code, json.load(error)


def run(godot):
    project = Path(__file__).resolve().parents[1] / "game"
    script = Path(__file__).with_name("test_record_fixture.gd").resolve()
    with tempfile.TemporaryDirectory() as runtime:
        built = subprocess.run([godot, "--headless", "--fixed-fps", "60", "--path", str(project), "--script", str(script)],
                               env={**os.environ, "DONGXIU_TEST_RECORD_DIR": runtime},
                               capture_output=True, text=True, timeout=30)
        assert built.returncode == 0 and not built.stderr and "0 failures" in built.stdout, built.stderr
        good, other, forged = [json.loads((Path(runtime) / name).read_text(encoding="utf-8")) for name in ("real0.json", "real1.json", "false-ledger.json")]
        db = RoomDirectory(godot, project, runtime, "127.0.0.1")
        server = HttpServer(("127.0.0.1", 0), db, record_limit=1)
        server.records_key = "local-test-admin"
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}/v1/records"
        payload = {"mode": "solo", "room_instance_id": "1" * 64, "record": good}
        try:
            assert request(url)[0] == 403
            assert request(url, {**payload, "record": forged})[0] == 422
            assert not request(url, token=server.records_key)[1]["records"]
            with ThreadPoolExecutor(2) as pool:
                accepted = list(pool.map(lambda i: request(url, payload), range(2)))
            assert [r[0] for r in accepted] == [200, 200], accepted
            assert sorted(r[1]["duplicate"] for r in accepted) == [False, True]
            expected_id = "1" * 64 + ":1"
            assert all(r[1]["id"] == expected_id and r[1]["status"] == "stored" and r[1]["checksum"] == good["checksum"] for r in accepted)
            # A copied checksum on a different tape cannot borrow the success receipt.
            assert request(url, {**payload, "record": {**forged, "checksum": good["checksum"]}})[0] == 422
            assert request(url, {**payload, "record": other})[0] == 409
            saved_id = "solo:" + expected_id
            assert request(url + "/" + saved_id)[0] == 403
            saved = request(url + "/" + saved_id, token=server.records_key)[1]
            assert saved["record"] == good and saved["authority_verified"] is False
            online = {**payload, "mode": "online", "room_instance_id": "2" * 64, "record": other}
            assert request(url, online)[0] == 403, "an untrusted sender must not impersonate an online authority"
            assert request(url, online, signature="a" * 64)[0] == 403
            assert request(url, online, signing_key=b"wrong" * 7)[0] == 403
            assert request(url, online, signing_key=db.record_key, raw=json.dumps(online, indent=1).encode())[0] == 403
            assert request(url, {**online, "record": forged}, signing_key=db.record_key)[0] == 422
            # A client-origin archive cannot occupy an authority's deduplication key.
            assert request(url, {**online, "mode": "lan"})[0] == 200
            assert request(url, online, signing_key=db.record_key)[0] == 200
            assert request(url, online)[0] == 403, "even a duplicate receipt requires source verification"
            assert request(url, online, signing_key=db.record_key)[1]["duplicate"] is True
            assert len(request(url, token=server.records_key)[1]["records"]) == 1
            assert request(url + "/" + saved_id, token=server.records_key)[0] == 404
            metadata = server.records.list_metadata(1)[0]
            assert metadata["authority_verified"] is True and metadata["id"].startswith("online:")
            # Replace the actual HTTP server at the same address, keeping its private identity.
            old_key, address = db.record_key, server.server_address
            server.shutdown()
            server.server_close()
            restarted = RoomDirectory(godot, project, runtime, "127.0.0.1")
            assert restarted.record_key == old_key
            server = HttpServer(address, restarted, record_limit=1)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            assert request(url, online, signing_key=old_key)[1]["duplicate"] is True
            assert request(url, online)[0] == 403
            oversize = {**payload, "note": "x" * (2 * 1024 * 1024)}
            assert request(url, oversize)[0] == 413
            # A real Godot authority signs the bytes it sends; a new process resumes the saved tape.
            submit = server.records.submit
            def unavailable(*args, **kwargs):
                raise RecordError(503, "测试暂不可用")
            server.records.submit = unavailable
            command = [godot, "--headless", "--path", str(project), "--script", str(Path(__file__).with_name("test_online_record_outbox.gd").resolve())]
            env = {**os.environ, "DONGXIU_TEST_RECORD_DIR": runtime, "DONGXIU_RECORD_URL": url,
                   "DONGXIU_RECORD_SIGNING_KEY": old_key.hex(), "DONGXIU_TEST_RECORD_RETRY": "0"}
            first = subprocess.run(command, env=env, capture_output=True, text=True, timeout=20)
            assert first.returncode == 0 and "tests passed" in first.stdout and "ERROR:" not in first.stderr, first.stdout + first.stderr
            pending = Path(runtime) / "outbox" / ("3" * 64 + "-1.json")
            assert pending.is_file() and old_key.hex() not in pending.read_text(encoding="utf-8")
            server.records.submit = submit
            server.shutdown()
            server.server_close()
            restarted = RoomDirectory(godot, project, runtime, "127.0.0.1")
            assert restarted.record_key == old_key
            server = HttpServer(address, restarted, record_limit=1)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            second = subprocess.run(command, env={**env, "DONGXIU_TEST_RECORD_RETRY": "1"}, capture_output=True, text=True, timeout=20)
            assert second.returncode == 0 and "tests passed" in second.stdout and "ERROR:" not in second.stderr, second.stdout + second.stderr
            assert not pending.exists()
            assert server.records.list_metadata(1)[0]["id"] == "online:" + "3" * 64 + ":1"
            assert server.records.list_metadata(1)[0]["authority_verified"] is True
            print("Record HTTP tests passed: authority signatures, restart identity, source isolation, real replay, forged ledger rejection, race-safe deduplication, private admin access and bounds.")
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    run(parser.parse_args().godot)
