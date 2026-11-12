"""Real Godot games -> local production HTTP handler -> persistent sample retrieval."""
import argparse
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))
from room_directory import Handler
from round_records import RoundRecords


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    logs = ROOT / "build" / "record-submission"
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        server.records = RoundRecords(Path(temp) / "records.sqlite3")
        server.records_api_key = "isolated-test-key"
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        env = os.environ.copy()
        env.update(MAHJONG_RECORD_TEST_URL=f"http://127.0.0.1:{server.server_port}", MAHJONG_RECORD_TEST_KEY=server.records_api_key)
        env["MAHJONG_RECORDS_URL"] = env["MAHJONG_RECORD_TEST_URL"]
        children = []
        def launch(name, script, flags=()):
            log = (logs / f"{name}.log").open("w", encoding="utf-8")
            process = subprocess.Popen([args.godot, "--headless", "--path", str(ROOT), "--script", f"res://tests/{script}.gd", "--", *flags], env=env, stdout=log, stderr=subprocess.STDOUT)
            children.append((name, process, log))
            return name, process, log
        def finish(item):
            name, process, log = item
            deadline = time.monotonic() + 100
            while process.poll() is None:
                output = (logs / f"{name}.log").read_text(encoding="utf-8-sig")
                if "ERROR:" in output or time.monotonic() >= deadline:
                    process.kill()
                    break
                time.sleep(0.1)
            process.wait()
            log.close()
            text = (logs / f"{name}.log").read_text(encoding="utf-8-sig")
            assert process.returncode == 0 and "passed" in text and "SCRIPT ERROR:" not in text and "ERROR:" not in text, text
            print(f"[ok] {name}", flush=True)
        try:
            finish(launch("single", "record_submission_http"))
            for mode in ("lan", "online"):
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                    probe.bind(("127.0.0.1", 0))
                    env["MAHJONG_RECORD_TEST_PORT"] = str(probe.getsockname()[1])
                host = launch(f"{mode}-host", "record_submission_network", ["--host"] + (["--dedicated"] if mode == "online" else []))
                time.sleep(1)
                client = launch(f"{mode}-client", "record_submission_network")
                finish(client)
                finish(host)
            samples = server.records.latest(100)
            assert samples["total"] == 3, samples["total"]
            assert [row["mode"] for row in samples["records"]] == ["online", "lan", "single"]
            assert all(row["record"]["events"][-1]["type"] == "settlement" for row in samples["records"])
            (logs / "samples.json").write_text(json.dumps(samples, ensure_ascii=False, indent=2), encoding="utf-8")
            print("[record_submission] passed single/LAN/online full games and newest-first samples", flush=True)
        finally:
            for _, process, log in children:
                if process.poll() is None:
                    process.kill()
                process.wait()
                log.close()
            server.shutdown()
            server.server_close()
            thread.join(3)
            server.records.close()


if __name__ == "__main__":
    main()
