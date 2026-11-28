"""Room discovery for the remake. A Godot child owns every live game and its member credentials."""
import argparse
import base64
from collections import deque
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import hashlib
import hmac
import os
from pathlib import Path
import re
import secrets
import socket
import sqlite3
import ssl
import subprocess
import tempfile
import threading
import time
from urllib.parse import parse_qs, urlsplit

from gme_auth import make_auth_buffer
from portal_api import ReleaseCatalog, WebAssets
from round_records import MAX_RECORD, RecordError, RecordStore

PROTOCOL = {"protocol": 4, "variant": "anshun_zhuoji"}
NUMBER = re.compile(r"[0-9]{4,8}")
MAX_BODY = 4096
START_TIMEOUT = 8
HEARTBEAT_TTL = 15


def _default_game_version():
    try:
        version = json.loads((Path(__file__).resolve().parents[1] / "version.json").read_text(encoding="utf-8"))["version"]
        return version if isinstance(version, str) and version else "2.4.3"
    except (OSError, ValueError, KeyError, TypeError):
        return "2.4.3"


class DirectoryError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


@dataclass
class Room:
    port: int
    status: Path
    process: subprocess.Popen | None = None


class RoomDirectory:
    def __init__(self, godot, project, runtime, public_host, first_port=7600, max_rooms=32):
        if not public_host or not 1 <= max_rooms <= 256 or not 0 <= first_port <= 65536 - max_rooms:
            raise ValueError("invalid host or room port range")
        self.godot = str(godot)
        self.project = Path(project).resolve()
        self.runtime = Path(runtime).resolve()
        self.runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.host = public_host
        self.first_port = first_port
        self.max_rooms = max_rooms
        self.rooms = {}
        self.attempts = {}
        self.nonces = {}
        self.gme_id = os.getenv("GME_APP_ID", "")
        self.gme_key = os.getenv("GME_APP_KEY", "")
        self.record_url = os.getenv("DONGXIU_RECORD_URL", "")
        key_path = self.runtime / "record-authority.key"
        if not key_path.exists():
            descriptor, candidate = tempfile.mkstemp(dir=self.runtime, prefix=".record-key-")
            try:
                with os.fdopen(descriptor, "wb") as key_file:
                    key_file.write(secrets.token_bytes(32))
                    key_file.flush()
                    os.fsync(key_file.fileno())
                try:
                    os.link(candidate, key_path)
                except FileExistsError:
                    pass
            finally:
                os.unlink(candidate)
        self.record_key = key_path.read_bytes()
        if len(self.record_key) != 32:
            raise ValueError("invalid private record authority key")
        self.lock = threading.RLock()
        for path in self.runtime.glob("*.room.json"):
            state = self._state(path)
            if state and NUMBER.fullmatch(state["number"]):
                self.rooms[state["number"]] = Room(state["port"], path)

    @staticmethod
    def _snapshot(path):
        try:
            if time.time() - path.stat().st_mtime > HEARTBEAT_TTL:
                return None
            state = json.loads(path.read_text(encoding="utf-8"))
            return state if isinstance(state, dict) else None
        except (OSError, ValueError):
            return None

    def _state(self, path):
        try:
            state = self._snapshot(path)
            if state is None:
                return None
            number, name, port = (state.get(k) for k in ("number", "name", "port"))
            players, started = state.get("players"), state.get("started")
            auth = state.get("auth")
            instance = auth.get("room_instance_id") if isinstance(auth, dict) else None
            if not isinstance(number, str) or not NUMBER.fullmatch(number) or not isinstance(name, str):
                return None
            if not isinstance(instance, str) or not re.fullmatch(r"[a-f0-9]{64}", instance):
                return None
            if type(port) not in (int, float) or int(port) != port or not 1 <= port <= 65535:
                return None
            if type(players) not in (int, float) or int(players) != players or not 0 <= players <= 4 or type(started) is not bool:
                return None
            return {"number": number, "name": name[:24], "host": self.host, "port": int(port),
                    "players": int(players), "started": started, "room_instance_id": instance,
                    "seats": [{key: seat[key] for key in ("player_id", "nickname", "score", "voice_pack", "avatar", "connected", "away") if key in seat}
                              for seat in state.get("seats", []) if isinstance(seat, dict)],
                    "owner_player_id": state.get("owner_player_id", "")}
        except (OSError, ValueError, OverflowError):
            return None

    def _live(self):
        public = {}
        for number, room in list(self.rooms.items()):
            if room.process is not None and room.process.poll() is not None:
                self.rooms.pop(number)
                room.status.unlink(missing_ok=True)
                continue
            state = self._state(room.status)
            if state and state["number"] == number:
                public[number] = state
            elif room.process is None:
                self.rooms.pop(number)
        return public

    def list_rooms(self):
        with self.lock:
            return sorted(self._live().values(), key=lambda row: row["number"])

    def find(self, number):
        with self.lock:
            room = self._live().get(number)
            if room is None and number in self.rooms:
                raise DirectoryError(503, "房间状态暂时不可用")
        if not room:
            raise DirectoryError(404, "房间不存在或已关闭")
        return room

    def voice_auth(self, query, token):
        if not re.fullmatch(r"[0-9]{1,10}", self.gme_id) or not 0 < int(self.gme_id) < 2**32 or len(self.gme_key.encode()) < 16:
            raise DirectoryError(503, "当前房间服务尚未配置在线语音")
        if set(query) != {"room", "instance", "openid", "nonce"} or any(len(values) != 1 for values in query.values()):
            raise DirectoryError(400, "语音请求无效")
        number, instance, openid, nonce = (query[k][0] for k in ("room", "instance", "openid", "nonce"))
        if not NUMBER.fullmatch(number) or not re.fullmatch(r"[a-f0-9]{64}", instance) or not re.fullmatch(r"[a-zA-Z0-9_-]{16,80}", nonce):
            raise DirectoryError(400, "语音请求无效")
        if not openid.startswith(number) or openid[len(number):] not in {"0", "1", "2", "3"} or not re.fullmatch(r"[a-f0-9]{64}", token):
            raise DirectoryError(403, "语音成员验证失败")
        seat = int(openid[len(number):])
        with self.lock:
            room = self.rooms.get(number)
            state = self._snapshot(room.status) if room else None
            auth = (state or {}).get("auth", {})
            digest = hashlib.sha256(token.encode("ascii")).hexdigest()
            if auth.get("room_instance_id") != instance or not any(
                item.get("seat") == seat and item.get("connected") is True and hmac.compare_digest(item.get("token_sha256", ""), digest)
                for item in auth.get("members", [])
            ):
                raise DirectoryError(403, "语音成员验证失败")
            now = time.monotonic()
            self.nonces = {k: t for k, t in self.nonces.items() if now - t < 300}
            key = (instance, seat, nonce)
            if key in self.nonces:
                raise DirectoryError(409, "该语音请求已处理")
            if sum(1 for k, t in self.nonces.items() if k[:2] == key[:2] and now - t < 60) >= 12 or len(self.nonces) >= 16384:
                raise DirectoryError(429, "语音请求过于频繁")
            self.nonces[key] = now
        voice_room = "dx-" + instance
        auth_buffer = make_auth_buffer(int(self.gme_id), voice_room, openid, self.gme_key)
        return {"auth": base64.b64encode(auth_buffer).decode("ascii"), "app_id": self.gme_id, "voice_room": voice_room}

    def _rate_limit(self, address):
        now = time.monotonic()
        self.attempts = {key: times for key, times in self.attempts.items() if times and times[-1] > now - 60}
        if address not in self.attempts and len(self.attempts) >= 4096:
            raise DirectoryError(429, "创建请求过多，请稍后再试")
        attempts = self.attempts.setdefault(address, deque())
        while attempts and attempts[0] <= now - 60:
            attempts.popleft()
        if len(attempts) >= 3:
            raise DirectoryError(429, "创建房间过于频繁，请稍后再试")
        attempts.append(now)

    @staticmethod
    def _settings(data):
        name = data.get("name")
        number = data.get("number", "")
        options = data.get("settings", {})
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 24 or not name.strip().isprintable():
            raise DirectoryError(400, "房间名应为1至24个可显示字符")
        if not isinstance(number, str) or (number and not NUMBER.fullmatch(number)):
            raise DirectoryError(400, "房间号应为4至8位数字")
        if not isinstance(options, dict) or set(options) - {"difficulty", "discard_ms", "response_ms"}:
            raise DirectoryError(400, "房间设置无效")
        if options.get("difficulty", "medium") not in ("low", "medium", "high"):
            raise DirectoryError(400, "人机难度无效")
        options = dict(options)
        for key in ("discard_ms", "response_ms"):
            if key in options:
                value = options[key]
                if type(value) not in (int, float) or not 1000 <= value <= 120000 or value != int(value):
                    raise DirectoryError(400, "操作时限无效")
                options[key] = int(value)
        options["room_name"] = name.strip()
        return number, options

    def create(self, data, address):
        number, settings = self._settings(data)
        with self.lock:
            self._rate_limit(address)
            self._live()
            if number and number in self.rooms:
                raise DirectoryError(409, "该房间号已使用")
            if len(self.rooms) >= self.max_rooms:
                raise DirectoryError(503, "当前房间已满")
            if not number:
                start = secrets.randbelow(10000)
                number = next(n for i in range(10000) if (n := f"{(start + i) % 10000:04}") not in self.rooms)
            used_ports = {room.port for room in self.rooms.values()}
            port = 0
            if self.first_port:
                for candidate in range(self.first_port, self.first_port + self.max_rooms):
                    if candidate in used_ports:
                        continue
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                        try:
                            probe.bind(("", candidate))
                        except OSError:
                            continue
                    port = candidate
                    break
                if not port:
                    raise DirectoryError(503, "可用房间端口已满")
            status = self.runtime / f"{number}-{secrets.token_hex(12)}.room.json"
            owner_token = secrets.token_hex(32)
            settings["owner_token_hash"] = hashlib.sha256(owner_token.encode()).hexdigest()
            env = {k: v for k, v in os.environ.items() if k not in {"GME_APP_KEY", "RECORDS_API_KEY"}}
            env.update({"DONGXIU_ROOM_STATUS": str(status), "DONGXIU_ROOM_NUMBER": number,
                        "DONGXIU_ROOM_PORT": str(port), "DONGXIU_ROOM_SETTINGS": json.dumps(settings, ensure_ascii=False),
                        "DONGXIU_RECORD_URL": self.record_url,
                        "DONGXIU_RECORD_SIGNING_KEY": self.record_key.hex()})
            command = [self.godot, "--headless", "--path", str(self.project),
                       "--script", "res://src/network/RoomServer.gd"]
            try:
                child = subprocess.Popen(command, env=env, stdin=subprocess.DEVNULL,
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                         creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            except OSError as exc:
                raise DirectoryError(503, "房间服务启动失败") from exc
            room = Room(port, status, child)
            self.rooms[number] = room

        deadline = time.monotonic() + START_TIMEOUT
        while time.monotonic() < deadline and child.poll() is None:
            state = self._state(status)
            if state and state["number"] == number:
                with self.lock:
                    room.port = state["port"]
                return {**state, "owner_token": owner_token}
            time.sleep(0.04)
        self._stop(child)
        with self.lock:
            if self.rooms.get(number) is room:
                self.rooms.pop(number)
        status.unlink(missing_ok=True)
        raise DirectoryError(503, "房间启动失败，请稍后再试")

    @staticmethod
    def _stop(child):
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=3)

    def stop_owned_rooms(self):
        """Explicit service shutdown for a supervised stack; a directory-only restart preserves games."""
        with self.lock:
            children = list(self.rooms.values())
        for room in children:
            if room.process and room.process.poll() is None:
                Path(str(room.status) + ".stop").touch()
        for room in children:
            if room.process:
                try:
                    room.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self._stop(room.process)
                room.status.unlink(missing_ok=True)
                Path(str(room.status) + ".stop").unlink(missing_ok=True)


class HttpServer(ThreadingHTTPServer):
    daemon_threads = False

    def __init__(self, address, directory, trusted_proxies=(), record_limit=100,
                 web_dir=None, downloads_dir=None, download_redirect_prefix="", game_version=None):
        self.directory = directory
        self.records = None
        self.portal = None
        self.started_monotonic = time.monotonic()
        self.started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        self.game_version = game_version or os.getenv("DONGXIU_GAME_VERSION") or _default_game_version()
        self.web_assets = WebAssets(web_dir if web_dir is not None else (Path(__file__).resolve().parents[1] / "web"))
        resolved_dl = downloads_dir if downloads_dir is not None else os.getenv("DONGXIU_DOWNLOADS_DIR", "")
        resolved_prefix = download_redirect_prefix if download_redirect_prefix else os.getenv("DONGXIU_DOWNLOAD_REDIRECT_PREFIX", "")
        self.records_key = os.getenv("RECORDS_API_KEY", "")
        self.slots = threading.BoundedSemaphore(32)
        self.trusted_proxies = tuple(ipaddress.ip_network(value, strict=False) for value in trusted_proxies)
        if ":" in address[0]:
            self.address_family = socket.AF_INET6
        super().__init__(address, Handler)
        try:
            self.records = RecordStore(directory.godot, directory.project, directory.runtime, record_limit)
            self.portal = ReleaseCatalog(directory.runtime, resolved_dl or None, resolved_prefix, self.game_version)
        except (ValueError, OSError, sqlite3.Error):
            self.server_close()
            raise
        if not directory.record_url:
            loopback = "[::1]" if self.address_family == socket.AF_INET6 else "127.0.0.1"
            directory.record_url = f"http://{loopback}:{self.server_port}/v1/records"

    def server_close(self):
        super().server_close()
        if self.portal is not None:
            self.portal.close()
            self.portal = None
        if self.records is not None:
            self.records.close()
            self.records = None

    def rate_key(self, socket_peer, forwarded):
        address = ipaddress.ip_address(socket_peer)
        # Only an explicitly configured, directly connected proxy can supply client identity.
        for item in reversed((forwarded or "").split(",")):
            if not any(address in network for network in self.trusted_proxies):
                break
            try:
                address = ipaddress.ip_address(item.strip())
            except ValueError:
                break
        if address.version == 6:
            if address.ipv4_mapped:
                return str(address.ipv4_mapped)
            return str(ipaddress.ip_network(f"{address}/64", strict=False))
        return str(address)

    def process_request(self, request, address):
        request.settimeout(8)
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

    def service_actions(self):
        with self.directory.lock:
            self.directory._live()


class Handler(BaseHTTPRequestHandler):
    server_version = "DongxiuRooms/1"

    def log_request(self, code="-", size="-"):
        self.log_message("%s %s %s", self.command, self.path.partition("?")[0], code)

    def _reply(self, status, payload):
        body = json.dumps({**PROTOCOL, **payload}, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        if status == 413:
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)
            self.wfile.flush()
        if status == 413:
            try:
                self.connection.shutdown(socket.SHUT_WR)
                self.connection.settimeout(0.5)
                drained = 0
                while drained < 3 * 1024 * 1024:
                    chunk = self.connection.recv(65536)
                    if not chunk:
                        break
                    drained += len(chunk)
            except OSError:
                pass

    def _serve_file(self, path: Path, content_type: str, cache_control: str, head_only: bool = False,
                    attachment_name: str = ""):
        stat = path.stat()
        total = stat.st_size
        start, end = 0, total - 1
        status_code = HTTPStatus.OK
        range_header = self.headers.get("Range", "")
        if range_header.startswith("bytes=") and total > 0:
            spec = range_header.removeprefix("bytes=").split(",", 1)[0].strip()
            parts = spec.split("-", 1)
            if len(parts) == 2:
                try:
                    if parts[0]:
                        start = int(parts[0])
                        end = int(parts[1]) if parts[1] else total - 1
                    else:
                        suffix = int(parts[1])
                        start = max(0, total - suffix)
                        end = total - 1
                    if 0 <= start <= end < total:
                        status_code = HTTPStatus.PARTIAL_CONTENT
                    else:
                        self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                        self.send_header("Content-Range", f"bytes */{total}")
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                except ValueError:
                    start, end = 0, total - 1
        length = max(0, end - start + 1) if total > 0 else 0
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", cache_control)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        if status_code == HTTPStatus.PARTIAL_CONTENT:
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
        if attachment_name:
            self.send_header("Content-Disposition", f'attachment; filename="{attachment_name}"')
        self.end_headers()
        if head_only or length == 0:
            return
        if length > 512 * 1024:
            self.connection.settimeout(120)
        with path.open("rb") as fh:
            if start:
                fh.seek(start)
            remaining = length
            while remaining > 0:
                chunk = fh.read(min(262144, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    def _status_payload(self):
        directory = self.server.directory
        rooms = directory.list_rooms()
        players_online = sum(int(r.get("players", 0)) for r in rooms)
        records_summary = self.server.records.summary() if self.server.records else {"total": 0, "by_mode": {}}
        latest = self.server.portal.latest() if self.server.portal else None
        total_downloads = self.server.portal.total_downloads() if self.server.portal else 0
        voice_configured = bool(
            re.fullmatch(r"[0-9]{1,10}", directory.gme_id)
            and 0 < int(directory.gme_id) < 2**32
            and len(directory.gme_key.encode()) >= 16
        )
        return {
            "game_name": "东秀麻将 · 安顺捉鸡",
            "game_version": latest["version"] if latest else self.server.game_version,
            "server_status": "online",
            "started_at": self.server.started_at,
            "uptime_seconds": int(time.monotonic() - self.server.started_monotonic),
            "public_host": directory.host,
            "rooms_active": len(rooms),
            "rooms_max": directory.max_rooms,
            "players_online": players_online,
            "voice_configured": voice_configured,
            "records_archived": records_summary["total"],
            "records_by_mode": records_summary["by_mode"],
            "downloads_total": total_downloads,
            "hotpatches_available": len(self.server.portal.list_hotpatches()) if self.server.portal else 0,
            "latest_release": latest,
        }

    def do_HEAD(self):
        self._handle_read(head_only=True)

    def do_GET(self):
        self._handle_read(head_only=False)

    def _handle_read(self, head_only: bool):
        path = urlsplit(self.path).path
        directory = self.server.directory
        try:
            if path == "/v1/status":
                self._reply(200, self._status_payload())
            elif path == "/v1/updates/manifest":
                manifest = self.server.portal.update_manifest() if self.server.portal else {
                    "schema": 1, "game_version": self.server.game_version,
                    "latest_release": None, "packages": {}, "hotpatches": [],
                }
                self._reply(200, manifest)
            elif path == "/v1/releases":
                releases = self.server.portal.list_releases() if self.server.portal else []
                self._reply(200, {"releases": releases, "downloads_total": self.server.portal.total_downloads() if self.server.portal else 0})
            elif path == "/v1/releases/latest":
                latest = self.server.portal.latest() if self.server.portal else None
                if latest is None:
                    self._reply(404, {"error": "暂无可下载的客户端安装包"})
                else:
                    self._reply(200, {"release": latest})
            elif path.startswith("/v1/downloads/") and path.count("/") == 3:
                filename = path.rsplit("/", 1)[-1]
                file_path, redirect = self.server.portal.resolve_download(filename) if self.server.portal else (None, None)
                if file_path is None:
                    self._reply(404, {"error": "安装包不存在"})
                    return
                if not head_only:
                    range_hdr = self.headers.get("Range", "")
                    if not range_hdr or range_hdr.startswith("bytes=0-"):
                        self.server.portal.record_download(filename)
                if redirect:
                    self.send_response(HTTPStatus.FOUND)
                    self.send_header("Location", redirect)
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                else:
                    ctype = "application/vnd.android.package-archive" if filename.endswith(".apk") else "application/octet-stream"
                    self._serve_file(file_path, ctype, "no-store", head_only=head_only, attachment_name=filename)
            elif path == "/v1/rooms":
                self._reply(200, {"rooms": directory.list_rooms()})
            elif path == "/v1/gme-auth":
                try:
                    query = parse_qs(urlsplit(self.path).query, max_num_fields=4)
                except ValueError:
                    raise DirectoryError(400, "语音请求无效") from None
                self._reply(200, directory.voice_auth(query, self.headers.get("X-Room-Token", "")))
            elif path == "/v1/records" or path.startswith("/v1/records/"):
                expected = self.server.records_key
                actual = self.headers.get("Authorization", "")
                if not expected or not hmac.compare_digest(actual.encode(), ("Bearer " + expected).encode()):
                    raise DirectoryError(403, "无权读取私人牌谱")
                if path == "/v1/records":
                    try:
                        query = parse_qs(urlsplit(self.path).query, max_num_fields=1)
                        limit = int(query.get("limit", ["20"])[0])
                    except ValueError:
                        raise DirectoryError(400, "数量无效") from None
                    if not 1 <= limit <= 100:
                        raise DirectoryError(400, "数量无效")
                    self._reply(200, {"records": self.server.records.list_metadata(limit)})
                else:
                    self._reply(200, self.server.records.read(path.removeprefix("/v1/records/")))
            elif path.startswith("/v1/rooms/") and NUMBER.fullmatch(path.rsplit("/", 1)[-1]) and path.count("/") == 3:
                try:
                    room = directory.find(path.rsplit("/", 1)[-1])
                except DirectoryError as exc:
                    if exc.status != 404:
                        raise
                    self._reply(404, {"error": str(exc), "reason": "room_not_found"})
                else:
                    self._reply(200, {"room": room})
            else:
                asset = self.server.web_assets.resolve(path) if self.server.web_assets else None
                if asset is not None:
                    self._serve_file(asset[0], asset[1], asset[2], head_only=head_only)
                else:
                    self._reply(404, {"error": "未找到该接口"})
        except (DirectoryError, RecordError) as exc:
            self._reply(exc.status, {"error": str(exc)})

    def do_POST(self):
        path = urlsplit(self.path).path
        if path not in {"/v1/rooms", "/v1/records"}:
            self._reply(404, {"error": "未找到该接口"})
            return
        try:
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = 0
            key = self.server.rate_key(self.client_address[0], self.headers.get("X-Forwarded-For"))
            if path == "/v1/records":
                self.server.records.admit(key)
            if self.headers.get("Transfer-Encoding") or not 0 < length <= (MAX_RECORD if path == "/v1/records" else MAX_BODY):
                raise DirectoryError(413, "请求大小无效")
            if self.headers.get_content_type() != "application/json":
                raise DirectoryError(415, "仅接受 JSON 请求")
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise DirectoryError(400, "请求不完整")
            try:
                data = json.loads(raw)
            except (ValueError, RecursionError):
                raise DirectoryError(400, "请求内容无效") from None
            if not isinstance(data, dict):
                raise DirectoryError(400, "创建参数无效")
            if path == "/v1/records":
                if data.get("mode") == "online":
                    signature = self.headers.get("X-Dongxiu-Record-Signature", "")
                    expected = hmac.new(self.server.directory.record_key, raw, hashlib.sha256).hexdigest()
                    if not re.fullmatch(r"[a-f0-9]{64}", signature) or not hmac.compare_digest(signature, expected):
                        raise DirectoryError(403, "在线牌谱来源验证失败")
                self._reply(200, self.server.records.submit(data, authority_verified=data.get("mode") == "online"))
            else:
                room = self.server.directory.create(data, key)
                self._reply(HTTPStatus.CREATED, {"room": room})
        except (DirectoryError, RecordError) as exc:
            self._reply(exc.status, {"error": str(exc)})
        except (OSError, sqlite3.Error):
            self._reply(503, {"error": "服务暂时无法完成请求"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot executable")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1] / "game")
    parser.add_argument("--runtime", type=Path, required=True, help="Private writable room process directory")
    parser.add_argument("--public-host", required=True, help="ENet hostname returned to players")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--first-game-port", type=int, default=7600)
    parser.add_argument("--max-rooms", type=int, default=32)
    parser.add_argument("--certfile")
    parser.add_argument("--keyfile")
    parser.add_argument("--trusted-proxy", action="append", default=[], help="Explicitly trusted reverse proxy IP or subnet")
    parser.add_argument("--record-limit", type=int, default=100, help="Maximum archived diagnostic rounds")
    parser.add_argument("--web-dir", type=Path, default=Path(__file__).resolve().parents[1] / "web", help="Official web frontend directory")
    parser.add_argument("--downloads-dir", type=Path, default=None, help="Downloadable client release directory")
    parser.add_argument("--download-redirect-prefix", default="", help="Optional static URL prefix (e.g. /updates/) for fast Nginx APK downloads")
    parser.add_argument("--game-version", default="", help="Published client version fallback")
    args = parser.parse_args()
    if bool(args.certfile) != bool(args.keyfile):
        parser.error("HTTPS requires both --certfile and --keyfile")
    if not args.certfile and not ipaddress.ip_address(args.bind).is_loopback:
        parser.error("use HTTPS for an external listener, or a loopback listener behind a TLS reverse proxy")
    directory = RoomDirectory(args.godot, args.project, args.runtime, args.public_host, args.first_game_port, args.max_rooms)
    server = HttpServer(
        (args.bind, args.port),
        directory,
        args.trusted_proxy,
        args.record_limit,
        web_dir=args.web_dir,
        downloads_dir=args.downloads_dir,
        download_redirect_prefix=args.download_redirect_prefix,
        game_version=args.game_version or os.getenv("DONGXIU_GAME_VERSION") or _default_game_version(),
    )
    if args.certfile:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.certfile, args.keyfile)
        server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
        if not os.getenv("DONGXIU_RECORD_URL"):
            directory.record_url = f"https://{args.public_host}:{server.server_port}/v1/records"
    try:
        print(f"Directory listening on {args.bind}:{server.server_port}", flush=True)
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
