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
from portal_api import ReleaseCatalog


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

            # 5. Verified hot patches are merged, deduplicated and ordered semantically.
            pck_bytes = b"GDPC" + bytes(range(256)) * 4
            pck_name = "dongxiu-2.4.1.pck"
            (Path(downloads) / pck_name).write_bytes(pck_bytes)
            patch = {"filename": pck_name, "version": "2.4.1", "base_version": "2.4.0",
                     "base_id": "android-2.4.0", "engine": "4.7.2", "notes": "First fix\nSecond fix"}
            (Path(downloads) / "bad-magic.pck").write_bytes(b"PK\x03\x04bad pack")
            (Path(downloads) / "tampered.pck").write_bytes(pck_bytes)
            bad = [dict(patch, filename="bad-magic.pck"),
                   dict(patch, filename="tampered.pck", sha256="0" * 64),
                   dict(patch, filename="../evil.pck"), dict(patch, filename=apk_path.name),
                   dict(patch, filename="missing.pck")]
            hotpatch_path = Path(downloads) / "hotpatches.json"
            hotpatch_path.write_text(json.dumps({"hotpatches": [patch, *bad]}), encoding="utf-8")
            older_name, newer_name = "dongxiu-2.4.2.pck", "dongxiu-2.4.10.pck"
            for name in (older_name, newer_name):
                (Path(downloads) / name).write_bytes(pck_bytes)
            manifest["hotpatches"] = [patch, dict(patch, filename=older_name, version="2.4.2", notes=["Older"]),
                                      dict(patch, filename=newer_name, version="2.4.10", mandatory=True)]
            manifest_path = Path(downloads) / "releases.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            code, _, raw = fetch_raw(base + "/v1/updates/manifest")
            updates = json.loads(raw)
            assert code == 200 and updates["schema"] == 1 and updates["game_version"] == "2.4.0"
            assert updates["latest_release"]["filename"] == apk_path.name
            assert updates["packages"]["android"] == updates["latest_release"]
            assert [item["version"] for item in updates["hotpatches"]] == ["2.4.10", "2.4.2", "2.4.1"]
            assert updates["hotpatches"][0]["mandatory"] is True
            actual = updates["hotpatches"][-1]
            assert actual["sha256"] == hashlib.sha256(pck_bytes).hexdigest()
            assert actual["size_bytes"] == len(pck_bytes) and actual["size_mb"] == round(len(pck_bytes) / (1024 * 1024), 2)
            assert actual["download_url"] == actual["direct_url"] == f"/v1/downloads/{pck_name}"
            assert actual["notes"] == ["First fix", "Second fix"] and actual["available"] is True
            assert actual["base_id"] == patch["base_id"] and actual["base_version"] == "2.4.0"
            assert actual["engine"] == "4.7.2" and actual["platform"] == "android" and actual["mandatory"] is False
            assert actual["published_at"]
            code, hdrs, body = fetch_raw(base + "/v1/updates/manifest", method="HEAD")
            assert code == 200 and body == b"" and int(hdrs["Content-Length"]) > 0
            assert json.loads(fetch_raw(base + "/v1/status")[2])["hotpatches_available"] == 3

            # Both manifest encodings and all metadata guards fail closed.
            for overrides in ({"version": "2.4"}, {"version": 241}, {"base_version": "bad"},
                              {"base_id": " "}, {"engine": None}, {"platform": "ios"}):
                hotpatch_path.write_text(json.dumps([dict(patch, **overrides)]), encoding="utf-8")
                manifest.pop("hotpatches", None)
                manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
                assert json.loads(fetch_raw(base + "/v1/updates/manifest")[2])["hotpatches"] == []
            patch["sha256"] = hashlib.sha256(pck_bytes).hexdigest().upper()
            hotpatch_path.write_text(json.dumps([patch]), encoding="utf-8")
            assert len(json.loads(fetch_raw(base + "/v1/updates/manifest")[2])["hotpatches"]) == 1

            # 6. PCK full GET, HEAD and resumed byte ranges share download counting rules.
            total_before = server.portal.total_downloads()
            url = base + f"/v1/downloads/{pck_name}"
            code, hdrs, body = fetch_raw(url, method="HEAD")
            assert code == 200 and body == b"" and int(hdrs["Content-Length"]) == len(pck_bytes)
            assert hdrs["Content-Type"] == "application/octet-stream" and hdrs["Accept-Ranges"] == "bytes"
            assert server.portal.total_downloads() == total_before
            code, hdrs, body = fetch_raw(url)
            assert code == 200 and body == pck_bytes and "attachment" in hdrs["Content-Disposition"]
            assert server.portal.total_downloads() == total_before + 1
            code, hdrs, body = fetch_raw(url, headers={"Range": "bytes=4-15"})
            assert code == 206 and body == pck_bytes[4:16] and hdrs["Content-Range"] == f"bytes 4-15/{len(pck_bytes)}"
            assert hdrs["Content-Type"] == "application/octet-stream" and hdrs["Accept-Ranges"] == "bytes"
            assert server.portal.total_downloads() == total_before + 1
            code, hdrs, body = fetch_raw(url, method="HEAD", headers={"Range": "bytes=0-3"})
            assert code == 206 and body == b"" and hdrs["Content-Length"] == "4"
            assert server.portal.total_downloads() == total_before + 1

            # Latest packages are selected per platform, independent of manifest order.
            (Path(downloads) / "windows.exe").write_bytes(b"windows")
            manifest["releases"] += [dict(manifest["releases"][0], version="2.4.2"),
                                     {"filename": "windows.exe", "version": "2.4.1", "platform": "Windows"}]
            # Use a distinct APK filename so the catalog does not deduplicate the newer build.
            manifest["releases"][1]["filename"] = "android-new.apk"
            (Path(downloads) / "android-new.apk").write_bytes(apk_bytes)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            updates = json.loads(fetch_raw(base + "/v1/updates/manifest")[2])
            assert updates["packages"]["android"]["version"] == updates["game_version"] == "2.4.2"
            assert updates["packages"]["windows"]["version"] == "2.4.1"
            catalog = ReleaseCatalog(runtime, downloads, "https://cdn.example/updates", "2.4.0")
            try:
                assert catalog.list_hotpatches()[0]["direct_url"] == f"https://cdn.example/updates/{pck_name}"
            finally:
                catalog.close()
            portal = server.portal
            server.portal = None
            try:
                updates = json.loads(fetch_raw(base + "/v1/updates/manifest")[2])
                assert updates["schema"] == 1 and updates["game_version"] == "2.4.0"
                assert updates["latest_release"] is None and updates["packages"] == {} and updates["hotpatches"] == []
                assert json.loads(fetch_raw(base + "/v1/status")[2])["hotpatches_available"] == 0
            finally:
                server.portal = portal

            print("Portal API tests passed: static frontend, security/traversal, status, releases, SHA-256, Range & download counter.")
            print("Update manifest tests passed: verified PCKs, integrity filtering, platforms, HEAD, Range and hot-patch counts.")
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
