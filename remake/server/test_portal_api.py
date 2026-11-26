"""End-to-end tests for portal backend APIs (/v1/status, /v1/releases, /v1/downloads, static web frontend)."""
import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from room_directory import HttpServer, RoomDirectory


class NoRedirect(object):
    pass


def fetch_raw(url, method="GET", headers=None):
    req = Request(url, method=method, headers=headers or {})
    try:
        with urlopen(req, timeout=10) as resp:
            return resp.status, dict(resp.headers), resp.read()
    except HTTPError as exc:
        return exc.code, dict(exc.headers), exc.read()


def run(godot):
    project = Path(__file__).resolve().parents[1] / "game"
    web_dir = Path(__file__).resolve().parents[1] / "web"
    with tempfile.TemporaryDirectory() as runtime, tempfile.TemporaryDirectory() as downloads:
        apk_bytes = b"PK\x03\x04dongxiu-mahjong-test-apk-payload" * 2048
        apk_path = Path(downloads) / "dongxiu-mahjong-2.4.0.apk"
        apk_path.write_bytes(apk_bytes)
        expected_sha = hashlib.sha256(apk_bytes).hexdigest()
        manifest = {
            "releases": [
                {
                    "version": "2.4.0",
                    "version_code": 7,
                    "channel": "release",
                    "filename": "dongxiu-mahjong-2.4.0.apk",
                    "published_at": "2026-11-27",
                    "changelog": ["新增 FPS 与局域网/服务器延迟显示", "听牌常驻与结算冲锋鸡横置"],
                }
            ]
        }
        (Path(downloads) / "releases.json").write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")

        directory = RoomDirectory(godot, project, runtime, "127.0.0.1", first_port=0, max_rooms=4)
        server = HttpServer(
            ("127.0.0.1", 0),
            directory,
            web_dir=web_dir,
            downloads_dir=Path(downloads),
            game_version="2.4.0",
        )
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            # 1. Static frontend index, CSS, JS, favicon, screenshot
            code, hdrs, body = fetch_raw(base + "/")
            assert code == 200 and "text/html" in hdrs.get("Content-Type", "") and "东秀麻将".encode("utf-8") in body
            code, hdrs, _ = fetch_raw(base + "/styles.css")
            assert code == 200 and "text/css" in hdrs.get("Content-Type", "")
            code, hdrs, _ = fetch_raw(base + "/app.js")
            assert code == 200 and "javascript" in hdrs.get("Content-Type", "")
            code, hdrs, _ = fetch_raw(base + "/screenshots/gameplay-ting.jpg")
            assert code == 200 and "image/jpeg" in hdrs.get("Content-Type", "")

            # 2. Path traversal and unknown route keep strict JSON 404 without "reason"
            code, _, raw = fetch_raw(base + "/not-a-room")
            parsed = json.loads(raw)
            assert code == 404 and "reason" not in parsed
            code, _, _ = fetch_raw(base + "/web/../server/room_directory.py")
            assert code == 404
            code, _, _ = fetch_raw(base + "/v1/downloads/..%2Freleases.json")
            assert code == 404

            # 3. /v1/status & /v1/releases & /v1/releases/latest
            code, _, raw = fetch_raw(base + "/v1/status")
            st = json.loads(raw)
            assert code == 200 and st["server_status"] == "online" and st["protocol"] == 4
            assert st["rooms_active"] == 0 and st["rooms_max"] == 4 and st["downloads_total"] == 0
            assert st["latest_release"]["version"] == "2.4.0" and st["latest_release"]["sha256"] == expected_sha

            code, _, raw = fetch_raw(base + "/v1/releases")
            rels = json.loads(raw)["releases"]
            assert code == 200 and len(rels) == 1 and rels[0]["filename"] == "dongxiu-mahjong-2.4.0.apk"

            code, _, raw = fetch_raw(base + "/v1/releases/latest")
            latest = json.loads(raw)["release"]
            assert code == 200 and latest["version_code"] == 7 and latest["downloads"] == 0

            # 4. HEAD does not increment download count; full GET and byte Range download work & track count
            code, hdrs, body = fetch_raw(base + "/v1/downloads/dongxiu-mahjong-2.4.0.apk", method="HEAD")
            assert code == 200 and int(hdrs["Content-Length"]) == len(apk_bytes) and body == b""
            assert json.loads(fetch_raw(base + "/v1/releases/latest")[2])["release"]["downloads"] == 0

            code, hdrs, body = fetch_raw(base + "/v1/downloads/dongxiu-mahjong-2.4.0.apk")
            assert code == 200 and body == apk_bytes and "attachment" in hdrs.get("Content-Disposition", "")
            assert json.loads(fetch_raw(base + "/v1/releases/latest")[2])["release"]["downloads"] == 1

            code, hdrs, part = fetch_raw(base + "/v1/downloads/dongxiu-mahjong-2.4.0.apk", headers={"Range": "bytes=10-19"})
            assert code == 206 and part == apk_bytes[10:20] and hdrs["Content-Range"] == f"bytes 10-19/{len(apk_bytes)}"
            # Partial mid-file Range resume should NOT double-count downloads
            assert json.loads(fetch_raw(base + "/v1/releases/latest")[2])["release"]["downloads"] == 1

            print("Portal API tests passed: static frontend, security/traversal, status, releases, SHA-256, Range & download counter.")
        finally:
            directory.stop_owned_rooms()
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    run(args.godot)
