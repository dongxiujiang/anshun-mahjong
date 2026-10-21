"""Real multi-process LAN, lobby, table UI and local cloud-server integration."""
from pathlib import Path
import argparse
import importlib.util
import json
import subprocess
import threading
import time
import urllib.error
import urllib.request

PROJECT = Path(__file__).resolve().parents[1]
LOGS = PROJECT / "build"


def launch(godot, name, scene, user_args=()):
    LOGS.mkdir(parents=True, exist_ok=True)
    stdout = (LOGS / f"{name}.log").open("w", encoding="utf-8")
    stderr = (LOGS / f"{name}.err").open("w", encoding="utf-8")
    args = [godot, "--headless", "--path", str(PROJECT)]
    args += ["--script", scene] if scene.endswith(".gd") else [scene]
    args += ["--quit-after", "60000"]
    if user_args: args += ["--", *user_args]
    return subprocess.Popen(args, stdout=stdout, stderr=stderr), stdout, stderr


def finish(item, name, timeout=70):
    process, stdout, stderr = item
    failure = ""
    deadline = time.monotonic() + timeout
    try:
        while process.poll() is None:
            errors = (LOGS / f"{name}.err").read_text(encoding="utf-8-sig", errors="replace")
            if "SCRIPT ERROR:" in errors or "ERROR:" in errors:
                failure = "Godot reported an error"
                break
            if time.monotonic() >= deadline:
                failure = f"timed out after {timeout}s"
                break
            time.sleep(0.1)
    finally:
        if process.poll() is None:
            process.kill()
        code = process.wait()
        stdout.close()
        stderr.close()
    output = (LOGS / f"{name}.log").read_text(encoding="utf-8-sig", errors="replace")
    errors = (LOGS / f"{name}.err").read_text(encoding="utf-8-sig", errors="replace")
    if failure or code != 0 or "SCRIPT ERROR:" in errors or "ERROR:" in errors or "passed" not in output and "completed" not in output:
        raise AssertionError(f"{name}: {failure} exit {code}\n{output}\n{errors}")
    print(f"[ok] {name}", flush=True)


def request(base, method="GET", data=None):
    payload = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(base + "/rooms", data=payload, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def run(godot, lan_interface=False, section="all"):
    children = []
    try:
        if section in ("all", "lan"):
            host = launch(godot, "lobby_host", "res://tests/lobby_network.tscn", ["--lobby-host"])
            children.append(host)
            time.sleep(0.5)
            client = launch(godot, "lobby_client", "res://tests/lobby_network.tscn", ["--lobby-interface"] if lan_interface else [])
            children.append(client)
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                if "GAME_STARTED" in (LOGS / "lobby_host.log").read_text(encoding="utf-8-sig"): break
                if host[0].poll() is not None: break
                time.sleep(0.05)
            late = launch(godot, "lobby_late", "res://tests/lobby_network.tscn", ["--lobby-late"])
            children.append(late)
            finish(late, "lobby_late")
            finish(client, "lobby_client")
            finish(host, "lobby_host")
            host = launch(godot, "table_host", "res://tests/net_table_ui.tscn", ["--table-host"])
            children.append(host)
            time.sleep(0.5)
            client = launch(godot, "table_client", "res://tests/net_table_ui.tscn")
            children.append(client)
            finish(client, "table_client")
            finish(host, "table_host")
        if section in ("all", "ready"):
            ready_clients = []
            for role in range(4):
                item = launch(godot, f"ready_player_{role}", "res://tests/next_round_network.gd", [f"--ready-role={role}"])
                children.append(item)
                ready_clients.append(item)
                time.sleep(0.15)
            for role, item in enumerate(ready_clients):
                finish(item, f"ready_player_{role}", 70)
    finally:
        for process, stdout, stderr in children:
            if process.poll() is None:
                process.kill()
                process.wait()
            stdout.close()
            stderr.close()
    if section not in ("all", "online"):
        print(f"[run_network] {section} passed", flush=True)
        return
    spec = importlib.util.spec_from_file_location("room_directory", PROJECT / "server" / "room_directory.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    directory = module.RoomDirectory(godot, PROJECT, "127.0.0.1", 7540, 2)
    server = module.ThreadingHTTPServer(("127.0.0.1", 0), module.Handler)
    server.directory = directory
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{server.server_port}"
    cloud_clients = []
    try:
        code, data = request(base)
        assert code == 200 and data == {"rooms": []}, "Empty online directory"
        for invalid in ["123", "123456789", "12a34", "-1234", 12345]:
            code, data = request(base, "POST", {"number": invalid})
            assert code == 400, "Invalid room number accepted"
        code, data = request(base, "POST", {"number": "654321", "name": "在线测试"})
        assert code == 201 and data["room"]["owner_token"], f"Creation failed: {data}"
        room = data["room"]
        code, data = request(base, "POST", {"number": "654321"})
        assert code == 409, "Duplicate room accepted"
        code, data = request(base)
        assert code == 200 and len(data["rooms"]) == 1 and "owner_token" not in data["rooms"][0], "Owner secret leaked in list"
        cloud_client = launch(godot, "online_room", "res://tests/online_room.tscn",
                              [f"--directory={base}", f"--owner-token={room['owner_token']}"])
        cloud_clients.append(cloud_client)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if "OWNER_WAITING" in (LOGS / "online_room.log").read_text(encoding="utf-8-sig"): break
            if cloud_client[0].poll() is not None: break
            time.sleep(0.05)
        guest = launch(godot, "online_guest", "res://tests/online_room.tscn", [f"--directory={base}"])
        cloud_clients.append(guest)
        finish(guest, "online_guest", 115)
        finish(cloud_client, "online_room", 55)
        directory.rooms["654321"]["process"].terminate()
        directory.rooms["654321"]["process"].wait(timeout=5)
        code, data = request(base)
        assert code == 200 and data == {"rooms": []}, "Dead rooms not removed"
        flow = launch(godot, "online_lobby_flow", "res://tests/smoke_lobby_flow.gd", [f"--directory={base}"])
        cloud_clients.append(flow)
        finish(flow, "online_lobby_flow", 40)
        print("[ok] online HTTP validation, real room creation, private ownership, stale removal", flush=True)
    finally:
        for process, stdout, stderr in cloud_clients:
            if process.poll() is None:
                process.kill()
                process.wait()
            stdout.close()
            stderr.close()
        server.shutdown()
        server.server_close()
        directory.close()
        thread.join(timeout=2)
    print("[run_network] all passed", flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--lan-interface", action="store_true", help="Require a connected private IPv4 interface; suppress loopback discovery")
    parser.add_argument("--section", choices=("all", "lan", "ready", "online"), default="all")
    args = parser.parse_args()
    run(args.godot, args.lan_interface, args.section)
