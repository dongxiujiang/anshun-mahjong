"""Deterministic local HTTP tests for proxy failover, Range and APK link probing.

No public proxy or browser is used; only the disposable fixture directory is written.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import subprocess
import threading
import time

PROJECT = Path(__file__).resolve().parents[1]
FIXTURE = PROJECT / "build/update_proxy_fixture"


def run(godot):
    FIXTURE.mkdir(parents=True, exist_ok=True)
    payload = b"MZ" + bytes(range(256)) * 32
    patch = b"GDPC" + bytes(range(256)) * 32
    apk = b"PK\x03\x04" + bytes(range(256)) * 32
    asset = "https://github.com/test/fixture/releases/download/V9.0.10/"

    def info(data, name, platform="windows", kind="full"):
        return dict(version="9.0.10", kind=kind, platform=platform, url=asset + name,
                    sha256=hashlib.sha256(data).hexdigest(), size=len(data), page="", notes="")

    fixtures = dict(full=info(payload, "game.exe"), patch=info(patch, "patch.pck", kind="patch"),
                    android=info(apk, "game.apk", platform="android"))
    (FIXTURE / "fixture.json").write_text(json.dumps(fixtures), encoding="utf-8")
    manifest = json.dumps(dict(schema=2, version="9.0.10", packages={"windows": fixtures["full"]})).encode()
    seen = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_HEAD(self):
            self.handle_route(head=True)

        def do_GET(self):
            self.handle_route()

        def handle_route(self, head=False):
            seen.append((self.command, self.path, self.headers.get("Range", "")))
            code, body, content_type = 200, payload, "application/octet-stream"
            extra = {}
            if self.path == "/release":
                body = json.dumps(dict(tag_name="V9.0.10", assets=[dict(name="update-manifest.json",
                    browser_download_url=asset + "update-manifest.json", digest="sha256:" + hashlib.sha256(manifest).hexdigest())])).encode()
                content_type = "application/json"
            elif self.path == "/manifest":
                body, content_type = manifest, "application/json"
            elif self.path == "/wrong-manifest":
                body, content_type = manifest.replace(b"9.0.10", b"9.0.11"), "application/json"
            elif self.path == "/fail":
                code, body = 503, b"unavailable"
            elif self.path == "/missing":
                code, body = 404, b"not found"
            elif self.path == "/limited":
                code, body = 429, b"rate limited"
            elif self.path == "/html":
                body, content_type = b"<html>proxy landing page</html>", "text/html"
            elif self.path == "/corrupt":
                body = b"MZ" + b"x" * (len(payload) - 2)
            elif self.path == "/patch":
                body = patch
            elif self.path in ("/apk", "/apk-backup", "/head-not-supported"):
                body = apk
                if head and self.path == "/head-not-supported":
                    code, body = 405, b""
                elif self.headers.get("Range") == "bytes=0-3":
                    code, body = 206, apk[:4]
                    extra["Content-Range"] = f"bytes 0-3/{len(apk)}"
            elif self.path in ("/resume", "/bad-range"):
                span = self.headers.get("Range", f"bytes=0-{len(payload)-1}").split("=")[1].split("-")
                offset, end = int(span[0]), int(span[1])
                code, body = 206, payload[offset:end+1]
                extra["Content-Range"] = f"bytes {offset + (1 if self.path == '/bad-range' else 0)}-{end}/{len(payload)}"
            elif self.path == "/partial":
                span = self.headers["Range"].split("=")[1].split("-")
                offset, end = int(span[0]), int(span[1])
                code, body = 206, payload[offset:end+1]
                extra["Content-Range"] = f"bytes {offset}-{end}/{len(payload)}"
            elif self.path == "/stall":
                time.sleep(9)
            elif self.path == "/slow":
                time.sleep(1)
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            for key, value in extra.items():
                self.send_header(key, value)
            self.end_headers()
            if head:
                return
            try:
                interrupted = self.path == "/partial" and not self.headers.get("Range", "").startswith("bytes=0-")
                self.wfile.write(body[:211] if interrupted else body)
                self.wfile.flush()
                if interrupted:
                    self.close_connection = True
                    self.connection.shutdown(socket.SHUT_RDWR)
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with (FIXTURE / "test.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen([godot, "--headless", "--path", str(PROJECT), "--script",
                "res://tests/update_proxy_http.gd", "--", f"--proxy-base=http://127.0.0.1:{server.server_port}"],
                stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 60
            try:
                while process.poll() is None:
                    if "ERROR:" in (FIXTURE / "test.log").read_text(encoding="utf-8", errors="replace") or time.monotonic() > deadline:
                        break
                    time.sleep(0.1)
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait()
        output = (FIXTURE / "test.log").read_text(encoding="utf-8", errors="replace")
        (FIXTURE / "requests.json").write_text(json.dumps(seen, indent=2), encoding="utf-8")
        assert process.returncode == 0 and "[update_proxy_http] passed" in output and "ERROR:" not in output, output
        assert ("GET", "/resume", "bytes=1024-2047") in seen, "Interrupted download did not resume from completed checkpoint"
        assert ("GET", "/ignore-range", "bytes=1024-2047") in seen, "Range-ignore recovery was not exercised"
        assert ("GET", "/bad-range", "bytes=1024-2047") in seen, "Invalid Content-Range was not exercised"
        assert ("GET", "/head-not-supported", "bytes=0-3") in seen, "HEAD fallback did not make bounded Range probe"
        assert not any(path == "/cancel-must-not-run" for _, path, _ in seen), "Cancellation started a fallback route"
        print(output, end="")
        print("[run_update_proxy] all passed: failover, Range resume, ignored/invalid Range, SHA256, stalls, APK probes, cancellation")
    finally:
        (FIXTURE / "requests.json").write_text(json.dumps(seen, indent=2), encoding="utf-8")
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    run(parser.parse_args().godot)
