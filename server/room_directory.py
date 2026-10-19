"""Room directory + real dedicated Godot rooms. Python 3.10+, no dependencies."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

from livekit_token import make_token

NUMBER = re.compile(r"[0-9]{4,8}\Z")
VERSION = "1"
APP_VERSION = os.environ.get("APP_VERSION", "dev")
BUILD_SHA = os.environ.get("BUILD_SHA", "")
LIVEKIT_API_KEY = os.environ.get("LIVEKIT_API_KEY", "")
LIVEKIT_API_SECRET = os.environ.get("LIVEKIT_API_SECRET", "")
LIVEKIT_URL = os.environ.get("LIVEKIT_URL", "wss://mj.dongxiu.fun/livekit")
LIVEKIT_TOKEN_TTL = int(os.environ.get("LIVEKIT_TOKEN_TTL", "3600"))
IDENTITY = re.compile(r"[A-Za-z0-9_-]{1,64}\Z")

class RoomDirectory:
    def __init__(self, godot, project, public_host, first_port=7600, max_rooms=32):
        self.godot, self.project, self.public_host = godot, Path(project).resolve(), public_host
        self.first_port, self.max_rooms = first_port, max_rooms
        self.runtime = self.project / "build" / "room-server"
        self.runtime.mkdir(parents=True, exist_ok=True)
        self.rooms = {}
        self.lock = threading.RLock()

    def _cleanup(self):
        for number, room in list(self.rooms.items()):
            if room["process"].poll() is not None:
                room["log"].close()
                room["status"].unlink(missing_ok=True)
                del self.rooms[number]

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

    def create(self, number, name):
        if not isinstance(number, str) or not NUMBER.fullmatch(number):
            raise ValueError("房间号必须是 4～8 位数字")
        if not isinstance(name, str): raise ValueError("房间名称无效")
        with self.lock:
            self._cleanup()
            if number in self.rooms: raise FileExistsError("这个房间号已在使用")
            if len(self.rooms) >= self.max_rooms: raise OverflowError("服务器房间已满，请稍后重试")
            used = {room["port"] for room in self.rooms.values()}
            port = next(p for p in range(self.first_port, self.first_port + self.max_rooms) if p not in used)
            token = secrets.token_urlsafe(24)
            status = self.runtime / f"{number}-{secrets.token_hex(6)}.json"
            log = (self.runtime / f"{number}.log").open("ab")
            args = [self.godot, "--headless", "--path", str(self.project),
                    "--script", "res://server/RoomServer.gd", "--",
                    f"--room-number={number}", f"--room-name={name.strip()[:24] or '在线麻将'}",
                    f"--room-port={port}", f"--status-file={status}", f"--owner-token={token}"]
            try:
                process = subprocess.Popen(args, stdout=log, stderr=log,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            except OSError:
                log.close()
                raise RuntimeError("无法启动游戏服务器，请检查 Godot 路径") from None
            room = {"port": port, "status": status, "process": process, "log": log}
            self.rooms[number] = room
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline and process.poll() is None:
                view = self._view(room)
                if view:
                    return {**view, "owner_token": token}
                time.sleep(0.1)
            if process.poll() is None: process.terminate()
            process.wait(timeout=5)
            self._cleanup()
            raise RuntimeError("房间启动失败，请检查服务器日志")

    def close(self):
        with self.lock:
            for room in self.rooms.values():
                if room["process"].poll() is None: room["process"].terminate()
            for room in self.rooms.values():
                try: room["process"].wait(timeout=5)
                except subprocess.TimeoutExpired:
                    room["process"].kill()
                    room["process"].wait()
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
        if path == "/livekit-token":
            if not LIVEKIT_API_KEY or not LIVEKIT_API_SECRET:
                return self._reply(503, {"error": "语音服务尚未配置"})
            query = parse_qs(urlsplit(self.path).query)
            room = str(query.get("room", [""])[0]).strip()
            identity = str(query.get("identity", [""])[0]).strip()
            name = str(query.get("name", [""])[0]).strip()[:32]
            if not NUMBER.fullmatch(room):
                return self._reply(400, {"error": "房间号必须是 4～8 位数字"})
            if not IDENTITY.fullmatch(identity):
                return self._reply(400, {"error": "语音身份无效"})
            if not self.server.directory.has_room(room):
                return self._reply(404, {"error": "房间不存在或已关闭"})
            try:
                token = make_token(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, room,
                                   identity, name or identity, LIVEKIT_TOKEN_TTL)
            except (ValueError, TypeError) as error:
                return self._reply(503, {"error": str(error)})
            return self._reply(200, {"url": LIVEKIT_URL, "token": token,
                                     "room": room, "identity": identity})
        if path != "/rooms":
            return self._reply(404, {"error": "接口不存在"})
        self._reply(200, {"rooms": self.server.directory.list()})

    def do_POST(self):
        if urlsplit(self.path).path != "/rooms":
            return self._reply(404, {"error": "接口不存在"})
        self.connection.settimeout(10)
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 4096: raise ValueError("请求大小无效")
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict): raise ValueError("请求格式无效")
            room = self.server.directory.create(data.get("number"), data.get("name", "在线麻将"))
            self._reply(201, {"room": room})
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
