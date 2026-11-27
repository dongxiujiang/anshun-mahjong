"""Portal backend helpers: release catalog, download counter, and static web frontend assets."""
from datetime import datetime, timezone
import hashlib
import json
import mimetypes
from pathlib import Path
import re
import sqlite3
import threading

SAFE_DOWNLOAD = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.(?:apk|exe|zip|pck)")
MIME_MAP = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".ico": "image/x-icon",
    ".apk": "application/vnd.android.package-archive",
    ".pck": "application/octet-stream",
    ".zip": "application/zip",
    ".exe": "application/octet-stream",
}


class ReleaseCatalog:
    """Manages downloadable game builds, SHA-256 verification cache, and persistent download counts."""

    def __init__(self, runtime_dir, downloads_dir=None, redirect_prefix="", game_version="2.4.0"):
        self.runtime_dir = Path(runtime_dir).resolve()
        self.downloads_dir = Path(downloads_dir).resolve() if downloads_dir else None
        self.redirect_prefix = (redirect_prefix or "").strip()
        if self.redirect_prefix and not self.redirect_prefix.endswith("/"):
            self.redirect_prefix += "/"
        self.game_version = game_version or "2.4.0"
        self.lock = threading.Lock()
        self._hash_cache = {}
        self.db = sqlite3.connect(self.runtime_dir / "portal.sqlite3", check_same_thread=False)
        with self.db:
            self.db.execute(
                "CREATE TABLE IF NOT EXISTS download_counts ("
                "filename TEXT PRIMARY KEY, "
                "count INTEGER NOT NULL DEFAULT 0, "
                "updated_at TEXT NOT NULL)"
            )

    def close(self):
        with self.lock:
            self.db.close()

    def _file_sha256(self, path: Path) -> str:
        stat = path.stat()
        key = (str(path), stat.st_size, stat.st_mtime_ns)
        cached = self._hash_cache.get(key)
        if cached:
            return cached
        digest = hashlib.sha256()
        with path.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                digest.update(chunk)
        hex_val = digest.hexdigest()
        self._hash_cache = {k: v for k, v in self._hash_cache.items() if k[0] != str(path)}
        self._hash_cache[key] = hex_val
        return hex_val

    def _counts_map(self) -> dict:
        with self.lock:
            rows = self.db.execute("SELECT filename, count FROM download_counts").fetchall()
        return {row[0]: int(row[1]) for row in rows}

    def total_downloads(self) -> int:
        with self.lock:
            row = self.db.execute("SELECT COALESCE(SUM(count), 0) FROM download_counts").fetchone()
        return int(row[0]) if row else 0

    def record_download(self, filename: str) -> int:
        now = datetime.now(timezone.utc).isoformat()
        with self.lock, self.db:
            self.db.execute(
                "INSERT INTO download_counts(filename, count, updated_at) VALUES(?, 1, ?) "
                "ON CONFLICT(filename) DO UPDATE SET count = count + 1, updated_at = excluded.updated_at",
                (filename, now),
            )
            row = self.db.execute("SELECT count FROM download_counts WHERE filename = ?", (filename,)).fetchone()
        return int(row[0]) if row else 1

    def _load_manifest(self) -> list[dict]:
        if not self.downloads_dir or not self.downloads_dir.is_dir():
            return []
        manifest_path = self.downloads_dir / "releases.json"
        if not manifest_path.is_file():
            return []
        try:
            raw = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []
        items = raw.get("releases", raw) if isinstance(raw, dict) else raw
        return [item for item in items if isinstance(item, dict)] if isinstance(items, list) else []

    def _enrich_item(self, item: dict, counts: dict) -> dict | None:
        filename = str(item.get("filename", "")).strip()
        if not SAFE_DOWNLOAD.fullmatch(filename):
            return None
        file_path = (self.downloads_dir / filename).resolve() if self.downloads_dir else None
        exists = bool(file_path and file_path.is_relative_to(self.downloads_dir) and file_path.is_file())
        size_bytes = int(item.get("size_bytes", 0))
        sha256 = str(item.get("sha256", ""))
        published_at = str(item.get("published_at", ""))
        if exists:
            stat = file_path.stat()
            size_bytes = stat.st_size
            if not sha256 or len(sha256) != 64:
                sha256 = self._file_sha256(file_path)
            if not published_at:
                published_at = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        elif size_bytes <= 0:
            return None
        direct_url = (self.redirect_prefix + filename) if self.redirect_prefix else f"/v1/downloads/{filename}"
        return {
            "version": str(item.get("version", self.game_version)),
            "version_code": int(item.get("version_code", 0)),
            "channel": str(item.get("channel", "release")),
            "platform": str(item.get("platform", "Android")),
            "architecture": str(item.get("architecture", "arm64-v8a / x86_64")),
            "min_os": str(item.get("min_os", "Android 7.0+")),
            "protocol": int(item.get("protocol", 4)),
            "filename": filename,
            "size_bytes": size_bytes,
            "size_mb": round(size_bytes / (1024 * 1024), 2),
            "sha256": sha256,
            "published_at": published_at,
            "downloads": counts.get(filename, 0),
            "download_url": f"/v1/downloads/{filename}",
            "direct_url": direct_url,
            "changelog": [str(line) for line in item.get("changelog", []) if isinstance(line, str)],
            "available": exists,
        }

    def list_releases(self) -> list[dict]:
        counts = self._counts_map()
        manifest = self._load_manifest()
        seen = set()
        releases = []
        for item in manifest:
            enriched = self._enrich_item(item, counts)
            if enriched and enriched["filename"] not in seen:
                seen.add(enriched["filename"])
                releases.append(enriched)
        # Auto-discover additional dongxiu-*.apk files if no manifest or extra builds exist.
        if self.downloads_dir and self.downloads_dir.is_dir():
            discovered = sorted(
                (p for p in self.downloads_dir.glob("dongxiu-*.apk") if p.is_file() and p.name not in seen),
                key=lambda p: p.stat().st_mtime,
                reverse=True,
            )
            for apk in discovered:
                enriched = self._enrich_item({"filename": apk.name, "version": self.game_version}, counts)
                if enriched:
                    seen.add(apk.name)
                    releases.append(enriched)
        return releases

    def latest(self) -> dict | None:
        items = self.list_releases()
        return items[0] if items else None

    def list_hotpatches(self) -> list[dict]:
        if not self.downloads_dir:
            return []
        items = []
        for name in ("hotpatches.json", "releases.json"):
            try:
                raw = json.loads((self.downloads_dir / name).read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            entries = raw.get("hotpatches", []) if isinstance(raw, dict) else raw if name == "hotpatches.json" else []
            if isinstance(entries, list):
                items.extend(item for item in entries if isinstance(item, dict))
        patches = {}
        for item in items:
            filename = item.get("filename", "")
            if not isinstance(filename, str) or not SAFE_DOWNLOAD.fullmatch(filename) or not filename.lower().endswith(".pck"):
                continue
            if any(not isinstance(item.get(key), str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", item[key])
                   for key in ("version", "base_version")):
                continue
            if any(not isinstance(item.get(key), str) or not item[key].strip() for key in ("base_id", "engine")):
                continue
            platform = item.get("platform", "android")
            if not isinstance(platform, str) or platform.lower() not in {"android", "windows", "linux", "all"}:
                continue
            try:
                file_path = (self.downloads_dir / filename).resolve()
                if not file_path.is_relative_to(self.downloads_dir) or not file_path.is_file():
                    continue
                with file_path.open("rb") as fh:
                    if fh.read(4) != b"GDPC":
                        continue
                stat = file_path.stat()
                sha256 = self._file_sha256(file_path)
            except (OSError, RuntimeError):
                continue
            expected = item.get("sha256", "")
            if expected not in ("", None):
                if not isinstance(expected, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", expected) or expected.lower() != sha256:
                    continue
            notes = item.get("notes", [])
            if isinstance(notes, str):
                notes = notes.splitlines()
            notes = [line for line in notes if isinstance(line, str)] if isinstance(notes, list) else []
            patches.setdefault(filename, {
                "version": item["version"], "base_version": item["base_version"],
                "base_id": item["base_id"].strip(), "engine": item["engine"].strip(),
                "platform": platform.lower(), "filename": filename,
                "size_bytes": stat.st_size, "size_mb": round(stat.st_size / (1024 * 1024), 2),
                "sha256": sha256,
                "published_at": str(item.get("published_at") or datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat()),
                "download_url": f"/v1/downloads/{filename}",
                "direct_url": self.redirect_prefix + filename if self.redirect_prefix else f"/v1/downloads/{filename}",
                "notes": notes, "mandatory": item.get("mandatory") is True, "available": True,
            })
        return sorted(patches.values(), key=lambda patch: tuple(map(int, patch["version"].split("."))), reverse=True)

    def update_manifest(self) -> dict:
        def version_key(release):
            version = release["version"]
            return tuple(map(int, version.split("."))) if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) else (0, 0, 0)

        releases = sorted(self.list_releases(), key=version_key, reverse=True)
        latest = releases[0] if releases else None
        packages = {}
        for release in releases:
            packages.setdefault(release["platform"].lower(), release)
        return {"schema": 1, "game_version": latest["version"] if latest else self.game_version,
                "latest_release": latest, "packages": packages, "hotpatches": self.list_hotpatches()}

    def resolve_download(self, filename: str) -> tuple[Path | None, str | None]:
        if not self.downloads_dir or not SAFE_DOWNLOAD.fullmatch(filename):
            return None, None
        candidate = (self.downloads_dir / filename).resolve()
        if not candidate.is_relative_to(self.downloads_dir) or not candidate.is_file():
            return None, None
        redirect = (self.redirect_prefix + filename) if self.redirect_prefix else None
        return candidate, redirect


class WebAssets:
    """Safely resolves static official website assets inside remake/web/."""

    def __init__(self, web_dir):
        self.root = Path(web_dir).resolve() if web_dir else None

    def resolve(self, request_path: str) -> tuple[Path, str, str] | None:
        if not self.root or not self.root.is_dir():
            return None
        if request_path in ("/", "/index.html"):
            rel = "index.html"
        elif request_path.startswith("/web/"):
            rel = request_path.removeprefix("/web/")
        elif request_path in ("/styles.css", "/app.js", "/favicon.svg") or request_path.startswith("/screenshots/"):
            rel = request_path.lstrip("/")
        else:
            return None
        if not rel or ".." in rel or "\\" in rel:
            return None
        target = (self.root / rel).resolve()
        if not target.is_relative_to(self.root) or not target.is_file():
            return None
        ext = target.suffix.lower()
        content_type = MIME_MAP.get(ext) or mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        cache_control = "no-cache" if ext == ".html" else "public, max-age=300"
        return target, content_type, cache_control
