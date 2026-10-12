"""Check automatic startup requests/popups against local HTTP, without packaging."""
from pathlib import Path
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import subprocess
import threading

PROJECT = Path(__file__).resolve().parents[1]


def run(godot):
    counts = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            counts[self.path] = counts.get(self.path, 0) + 1
            data = {"version": "1.0.0" if self.path == "/current" else "9.0.10",
                    "notes": "联机结算全员准备后开启下一局", "release_url": "https://example.com/release",
                    "platforms": {"windows": {"url": "https://example.com/game.exe",
                                              "sha256": "b" * 64, "size": 1234}}}
            body = json.dumps(data, ensure_ascii=False).encode()
            self.send_response(503 if self.path == "/offline" or self.path == "/retry" and counts[self.path] == 1 else 200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        def ps_quote(value):
            return "'" + str(value).replace("'", "''") + "'"

        for endpoint in ["new", "current", "offline", "retry"]:
            log = PROJECT / "build" / f"startup_{endpoint}.log"
            errors = PROJECT / "build" / f"startup_{endpoint}.err"
            args = ["--path", str(PROJECT), "--script", "res://tests/startup_update.gd",
                    "--quit-after", "5000", "--", f"--startup-url=http://127.0.0.1:{server.server_port}/{endpoint}"]
            command = (f"$startupTest = Start-Process -FilePath {ps_quote(godot)} -ArgumentList "
                       + ",".join(ps_quote(arg) for arg in args)
                       + f" -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput {ps_quote(log)}"
                       + f" -RedirectStandardError {ps_quote(errors)}; exit $startupTest.ExitCode")
            result = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", command],
                                    capture_output=True, timeout=25)
            output = log.read_text(encoding="utf-8-sig")
            err = errors.read_text(encoding="utf-8-sig")
            assert result.returncode == 0 and "passed" in output and "ERROR:" not in err, output + "\n" + err
            expected_requests = 2 if endpoint in ["offline", "retry"] else 1
            assert counts.get("/" + endpoint) == expected_requests, "Unexpected startup HTTP request count"
            print(f"[ok] startup {endpoint}: {expected_requests} automatic HTTP request(s)", flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    run(parser.parse_args().godot)
