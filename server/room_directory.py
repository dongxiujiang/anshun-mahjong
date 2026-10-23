"""Room directory + real dedicated Godot rooms. Python 3.10+, no dependencies."""
from __future__ import annotations
import argparse
import base64
import hashlib
import hmac
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gme_auth import make_auth_buffer

NUMBER = re.compile(r"[0-9]{4,8}\Z")
OPEN_ID = re.compile(r"[A-Za-z0-9_-]{1,64}\Z")
VERSION = "1"
APP_VERSION = os.environ.get("APP_VERSION", "dev")
BUILD_SHA = os.environ.get("BUILD_SHA", "")


def _trusted_networks():
    raw = os.environ.get("TRUSTED_PROXIES", "127.0.0.1/32,::1/128")
    networks = []
    for item in raw.split(","):
        item = item.strip()
        if not item:
            continue
        try:
            networks.append(ipaddress.ip_network(item, strict=False))
        except ValueError:
            continue
    return networks


TRUSTED_PROXIES = _trusted_networks()


def client_identity(peer, forwarded, trusted=None):
    """Use the socket peer unless it is a configured proxy, then walk the
    forwarded chain from the right and return the first non-proxy address."""
    trusted = TRUSTED_PROXIES if trusted is None else trusted

    def is_trusted(value):
        try:
            address = ipaddress.ip_address(value)
        except ValueError:
            return False
        return any(address in network for network in trusted)

    if not is_trusted(peer):
        return peer
    chain = [part.strip() for part in str(forwarded).split(",") if part.strip()]
    for value in reversed(chain):
        if not is_trusted(value):
            return value
    return peer

def token_digest(token):
    return "sha256:" + hashlib.sha256(token.encode("utf-8")).hexdigest()

def authenticate_stored_token(stored, token):
    if not isinstance(stored, str) or not stored or not isinstance(token, str) or not token:
        return False
    if stored.startswith("sha256:"):
        return hmac.compare_digest(stored, token_digest(token))
    # Backward compatibility with status files from older room processes.
    return hmac.compare_digest(stored, token)

def rate_limit_key(client_id):
    """Aggregate IPv6 clients by /64 so address rotation cannot bypass quotas."""
    try:
        address = ipaddress.ip_address(str(client_id))
    except ValueError:
        return str(client_id)
    if address.version == 6:
        # A v4-mapped address (e.g. ::ffff:1.2.3.4) is one IPv4 client, not a
        # /64 containing every IPv4 client.
        if address.ipv4_mapped is not None:
            return str(address.ipv4_mapped)
        return str(ipaddress.ip_network(f"{address}/64", strict=False))
    return str(address)

GME_APP_ID = os.environ.get("GME_APP_ID", "1400802279")
GME_APP_KEY = os.environ.get("GME_APP_KEY", "")

class RoomDirectory:
    def __init__(self, godot, project, public_host, first_port=7600, max_rooms=32):
        self.godot, self.project, self.public_host = godot, Path(project).resolve(), public_host
        self.first_port, self.max_rooms = first_port, max_rooms
        self.runtime = self.project / "build" / "room-server"
        self.runtime.mkdir(parents=True, exist_ok=True)
        self.rooms = self._recover_rooms()
        self.lock = threading.RLock()
        self.create_attempts = {}
        self.max_creates_per_minute = int(os.environ.get("MAX_CREATES_PER_MINUTE", "3"))
        self.max_log_bytes = 5 * 1024 * 1024
        self._maintenance_stop = threading.Event()
        self._maintenance_thread = None

    def start_maintenance(self, interval=10.0):
        """Reap dead rooms even when no HTTP request happens to call _cleanup."""
        if self._maintenance_thread is not None:
            return
        def loop():
            while not self._maintenance_stop.wait(interval):
                try:
                    with self.lock:
                        self._cleanup()
                except Exception:
                    # Maintenance must never take down the directory process.
                    pass
        self._maintenance_thread = threading.Thread(target=loop, name="room-maintenance", daemon=True)
        self._maintenance_thread.start()

    def _open_room_log(self, number):
        path = self.runtime / f"{number}.log"
        try:
            if path.exists() and path.stat().st_size >= self.max_log_bytes:
                rotated = self.runtime / f"{number}.log.1"
                rotated.unlink(missing_ok=True)
                path.replace(rotated)
        except OSError:
            pass
        return path.open("ab")

    def _recover_rooms(self):
        """Recover live child rooms after the directory process restarts.

        The child status file now carries its UDP port, so list/auth/port
        allocation can resume even though the Python process no longer owns a
        Process handle. Stale recovered entries are pruned by _cleanup.
        """
        recovered = {}
        for status in self.runtime.glob("*.json"):
            try:
                state = json.loads(status.read_text(encoding="utf-8-sig"))
                if time.time() - float(state["updated"]) > 30: continue
                number = state["number"]
                port = int(state.get("port", 0))
                if not isinstance(number, str) or not NUMBER.fullmatch(number): continue
                if port < 1 or port > 65535: continue
                recovered[number] = {"port": port, "status": status, "process": None,
                                     "log": None, "recovered": True}
            except (OSError, ValueError, KeyError, TypeError):
                continue
        return recovered

    def _cleanup(self):
        for number, room in list(self.rooms.items()):
            process = room.get("process")
            if process is not None and process.poll() is not None:
                if room.get("log") is not None:
                    room["log"].close()
                room["status"].unlink(missing_ok=True)
                self.rooms.pop(number, None)
            elif process is None and room.get("recovered"):
                try:
                    state = json.loads(room["status"].read_text(encoding="utf-8-sig"))
                    if time.time() - float(state["updated"]) <= 30: continue
                except (OSError, ValueError, KeyError, TypeError):
                    pass
                room["status"].unlink(missing_ok=True)
                self.rooms.pop(number, None)

    @staticmethod
    def _port_available(port):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind(("0.0.0.0", port))
            return True
        except OSError:
            return False
        finally:
            sock.close()

    def _view(self, room):
        try:
            state = json.loads(room["status"].read_text(encoding="utf-8-sig"))
            if time.time() - float(state["updated"]) > 15: return None
        except (OSError, ValueError, KeyError):
            return None
        return {"number": state["number"], "name": state["name"],
                "players": state["players"], "started": state["started"],
                "host": self.public_host, "port": room["port"]}

    def list(self):
        with self.lock:
            self._cleanup()
            return sorted([view for room in self.rooms.values() if (view := self._view(room))], key=lambda r: r["number"])

    def has_room(self, number):
        with self.lock:
            self._cleanup()
            room = self.rooms.get(number)
            return room is not None and self._view(room) is not None

    def allow_create(self, client_id):
        """Bound each source's room churn without changing the global limit."""
        now = time.monotonic()
        key = rate_limit_key(client_id)
        with self.lock:
            attempts = [stamp for stamp in self.create_attempts.get(key, [])
                        if now - stamp < 60.0]
            if len(attempts) >= max(1, self.max_creates_per_minute):
                self.create_attempts[key] = attempts
                return False
            attempts.append(now)
            self.create_attempts[key] = attempts
            return True

    def authenticate_member(self, number, open_id, token):
        """Only a current room member's resume token may request GME auth."""
        if not isinstance(token, str) or token == "" or not OPEN_ID.fullmatch(open_id):
            return False
        if not isinstance(number, str) or not NUMBER.fullmatch(number):
            return False
        if not open_id.startswith(number):
            return False
        seat_text = open_id[len(number):]
        if seat_text not in ["0", "1", "2", "3"]:
            return False
        with self.lock:
            self._cleanup()
            room = self.rooms.get(number)
            if room is None:
                return False
            try:
                state = json.loads(room["status"].read_text(encoding="utf-8-sig"))
                if time.time() - float(state["updated"]) > 15:
                    return False
                members = state.get("members", {})
                expected = members.get(seat_text, "")
                if authenticate_stored_token(expected, token):
                    return True
                # A locally hosted room has no member record for its own seat 0.
                host_token = state.get("host_token", "")
                return seat_text == "0" and authenticate_stored_token(host_token, token)
            except (OSError, ValueError, KeyError, TypeError):
                return False

    def create(self, number, name, client_id=""):
        if not isinstance(number, str) or not NUMBER.fullmatch(number):
            raise ValueError("房间号必须是 4～8 位数字")
        if not isinstance(name, str): raise ValueError("房间名称无效")
        # Reserve the number and port under the lock, but never hold the global
        # directory lock while starting/waiting for a Godot process. A slow or
        # failed room must not block listing, GME auth, or other room creates.
        with self.lock:
            self._cleanup()
            if number in self.rooms: raise FileExistsError("这个房间号已在使用")
            if len(self.rooms) >= self.max_rooms: raise OverflowError("服务器房间已满，请稍后重试")
            if client_id and not self.allow_create(client_id):
                raise PermissionError("创建房间过于频繁，请稍后重试")
            used = {room["port"] for room in self.rooms.values()}
            try:
                port = next(p for p in range(self.first_port, self.first_port + self.max_rooms)
                            if p not in used and self._port_available(p))
            except StopIteration:
                raise OverflowError("服务器房间端口已满，请稍后重试") from None
            token = secrets.token_urlsafe(24)
            status = self.runtime / f"{number}-{secrets.token_hex(6)}.json"
            # process/log are filled after the process starts. The reservation
            # must be visible so another request cannot take the same number or
            # port, while _cleanup/_view skip entries that are not ready yet.
            room = {"port": port, "status": status, "process": None, "log": None}
            self.rooms[number] = room
        log = None
        try:
            log = self._open_room_log(number)
            args = [self.godot, "--headless", "--path", str(self.project),
                    "--script", "res://server/RoomServer.gd", "--",
                    f"--room-number={number}", f"--room-name={name.strip()[:24] or '在线麻将'}",
                    f"--room-port={port}", f"--status-file={status}"]
            # Keep the owner bearer token out of the process command line,
            # where ps/procfs would expose it to other local users.
            child_env = os.environ.copy()
            child_env["MAHJONG_OWNER_TOKEN"] = token
            process = subprocess.Popen(args, stdout=log, stderr=log, env=child_env,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            room["process"] = process
            room["log"] = log
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline and process.poll() is None:
                view = self._view(room)
                if view:
                    return {**view, "owner_token": token}
                time.sleep(0.1)
            if process.poll() is None: process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise RuntimeError("房间启动失败，请检查服务器日志")
        except OSError as exc:
            raise RuntimeError("无法启动游戏服务器，请检查 Godot 路径") from exc
        finally:
            # A successful room stays in self.rooms. On every failure remove the
            # reservation so the port/number can be reused immediately.
            if room.get("process") is None or room["process"].poll() is not None:
                with self.lock:
                    if self.rooms.get(number) is room:
                        self.rooms.pop(number, None)
                if log is not None:
                    log.close()

    def close(self):
        self._maintenance_stop.set()
        if self._maintenance_thread is not None:
            self._maintenance_thread.join(timeout=2)
            self._maintenance_thread = None
        with self.lock:
            for room in self.rooms.values():
                process = room.get("process")
                if process is not None and process.poll() is None: process.terminate()
            for room in self.rooms.values():
                process = room.get("process")
                if process is not None:
                    try: process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                if room.get("log") is not None:
                    room["log"].close()
                room["status"].unlink(missing_ok=True)
            self.rooms.clear()

class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.connection.settimeout(10)
        path = urlsplit(self.path).path
        if path == "/healthz":
            rooms = self.server.directory.list()
            return self._reply(200, {
                "ok": True,
                "rooms": len(rooms),
                "max_rooms": self.server.directory.max_rooms,
                "version": VERSION,
                "app_version": APP_VERSION,
                "build": BUILD_SHA,
            })
        if path == "/gme-auth":
            if not GME_APP_KEY:
                return self._reply(503, {"error": "GME 语音密钥尚未配置"})
            query = parse_qs(urlsplit(self.path).query)
            room = str(query.get("room", [""])[0]).strip()
            open_id = str(query.get("openid", [""])[0]).strip()
            token = str(self.headers.get("X-Room-Token", "")).strip()
            if not NUMBER.fullmatch(room):
                return self._reply(400, {"error": "房间号必须是 4～8 位数字"})
            if not OPEN_ID.fullmatch(open_id):
                return self._reply(400, {"error": "语音身份无效"})
            if not self.server.directory.has_room(room):
                return self._reply(404, {"error": "房间不存在或已关闭"})
            if not self.server.directory.authenticate_member(room, open_id, token):
                return self._reply(403, {"error": "语音身份不属于当前房间成员"})
            try:
                auth = make_auth_buffer(int(GME_APP_ID), room, open_id, GME_APP_KEY)
            except (ValueError, TypeError) as error:
                return self._reply(503, {"error": str(error)})
            return self._reply(200, {"app_id": GME_APP_ID, "room": room,
                                     "openid": open_id,
                                     "auth": base64.b64encode(auth).decode("ascii")})
        if path != "/rooms":
            return self._reply(404, {"error": "接口不存在"})
        self._reply(200, {"rooms": self.server.directory.list()})

    def do_POST(self):
        if urlsplit(self.path).path != "/rooms":
            return self._reply(404, {"error": "接口不存在"})
        self.connection.settimeout(10)
        client_id = client_identity(self.client_address[0],
                                    self.headers.get("X-Forwarded-For", ""))
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 4096: raise ValueError("请求大小无效")
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict): raise ValueError("请求格式无效")
            room = self.server.directory.create(data.get("number"), data.get("name", "在线麻将"), client_id)
            self._reply(201, {"room": room})
        except PermissionError as error: self._reply(429, {"error": str(error)})
        except FileExistsError as error: self._reply(409, {"error": str(error)})
        except OverflowError as error: self._reply(503, {"error": str(error)})
        except (ValueError, TypeError) as error: self._reply(400, {"error": str(error)})
        except RuntimeError as error: self._reply(500, {"error": str(error)})
        except (OSError, TimeoutError): self._reply(408, {"error": "请求超时"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--public-host", required=True)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--http-port", type=int, default=8080)
    parser.add_argument("--first-port", type=int, default=7600)
    parser.add_argument("--max-rooms", type=int, default=32)
    args = parser.parse_args()
    if not 1 <= args.max_rooms <= 128 or not 1 <= args.first_port <= 65536 - args.max_rooms:
        parser.error("Invalid game port range or room limit")
    directory = RoomDirectory(args.godot, args.project, args.public_host, args.first_port, args.max_rooms)
    directory.start_maintenance()
    server = ThreadingHTTPServer((args.bind, args.http_port), Handler)
    server.daemon_threads = True
    server.directory = directory
    print(f"Room directory listening on {args.bind}:{args.http_port}", flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        server.server_close()
        directory.close()

if __name__ == "__main__": main()
