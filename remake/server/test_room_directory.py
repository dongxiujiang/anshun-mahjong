"""Run the real HTTP directory, standalone Godot room and two remote ENet seats locally."""
import argparse
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile
import threading
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from unittest.mock import patch

from room_directory import HttpServer, RoomDirectory


def status(url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    try:
        with urlopen(Request(url, data=data, headers={"Content-Type": "application/json"}), timeout=12) as reply:
            return reply.status, json.load(reply)
    except HTTPError as exc:
        return exc.code, json.load(exc)


def run(godot, observe_grace):
    project = Path(__file__).resolve().parents[1] / "game"
    with tempfile.TemporaryDirectory() as runtime:
        directory = RoomDirectory(godot, project, runtime, "127.0.0.1", first_port=0, max_rooms=3)
        directory.gme_id = "234567"
        directory.gme_key = "local-test-room-signing-key"
        server = HttpServer(("127.0.0.1", 0), directory)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            assert status(base + "/v1/rooms")[1]["rooms"] == []
            missing = status(base + "/v1/rooms/9999")
            assert missing[0] == 404 and missing[1]["reason"] == "room_not_found"
            assert "reason" not in status(base + "/not-a-room")[1]
            assert status(base + "/v1/rooms", {"name": "test", "settings": {"external_presentation": True}})[0] == 400
            result = subprocess.run([godot, "--headless", "--path", str(project), "--script", "res://tests/test_online_directory.gd"],
                                    env={**os.environ, "DONGXIU_DIRECTORY_TEST_URL": base,
                                         "APPDATA": runtime, "XDG_DATA_HOME": runtime},
                                    capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=155)
            print(result.stdout, flush=True)
            assert result.returncode == 0 and "0 failures" in result.stdout and "ERROR:" not in result.stderr, result.stderr
            rooms = directory.list_rooms()
            assert len(rooms) == 1 and rooms[0]["number"] == "004291" and rooms[0]["players"] == 2
            saved = server.records.list_metadata(10)
            assert len(saved) == 1 and saved[0]["mode"] == "online"
            assert set(rooms[0]) == {"number", "name", "host", "port", "players", "started", "room_instance_id", "seats", "owner_player_id"}
            assert len(rooms[0]["seats"]) == 4
            public_fields = {"player_id", "nickname", "score", "voice_pack", "avatar", "connected", "away"}
            assert all(set(seat) <= public_fields for seat in rooms[0]["seats"])
            assert re.fullmatch(r"[a-f0-9]{64}", rooms[0]["room_instance_id"])
            with patch.object(directory, "_snapshot", return_value=None):
                assert status(base + "/v1/rooms/004291")[0] == 503
            # Reconstruct the public index after a directory process restart, keeping the game alive.
            restarted = RoomDirectory(godot, project, runtime, "127.0.0.1", 0, 3)
            assert restarted.find("004291") == rooms[0]
            assert status(base + "/v1/rooms", {"name": "不能重号", "number": "004291"})[0] == 409
            limited = [status(base + "/v1/rooms", {"name": "不能重号", "number": "004291"})[0] for _ in range(3)]
            assert limited[-1] == 429
            owned = list(directory.rooms.values())
            if observe_grace:
                print("Observing real five-minute disconnected-room grace period", flush=True)
                deadline = time.monotonic() + 308
                while time.monotonic() < deadline and directory.list_rooms():
                    time.sleep(0.25)
                elapsed = time.monotonic() - (deadline - 308)
                assert 295 < elapsed < 308 and not directory.list_rooms(), elapsed
                print(f"Authority expired and disappeared from directory after {elapsed:.1f}s", flush=True)
            directory.stop_owned_rooms()
            assert all(room.process.poll() is not None for room in owned)
            assert status(base + "/v1/rooms")[1]["rooms"] == []
            print("HTTP creation, listing, rate and duplicate checks, restart/recovery, two-seat game and process shutdown passed.")
        finally:
            directory.stop_owned_rooms()
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--observe-grace", action="store_true")
    args = parser.parse_args()
    run(args.godot, args.observe_grace)
