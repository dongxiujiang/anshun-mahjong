"""Exercise real ENet reconnection in the lobby and during gameplay."""
import argparse
import importlib.util
from pathlib import Path
import time
import tempfile

def run(godot):
    spec = importlib.util.spec_from_file_location("network_runner", Path(__file__).with_name("run_network.py"))
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    children = []
    try:
        host = runner.launch(godot, "reconnect_host", "res://tests/reconnect_network.gd", ["--reconnect-host"])
        children.append(host)
        time.sleep(0.5)
        client = runner.launch(godot, "reconnect_client", "res://tests/reconnect_network.gd")
        children.append(client)
        runner.finish(client, "reconnect_client", 40)
        runner.finish(host, "reconnect_host", 10)
    finally:
        for process, stdout, stderr in children:
            if process.poll() is None:
                process.kill()
                process.wait()
            stdout.close()
            stderr.close()
    run_restart(godot, runner)


def run_restart(godot, runner):
    """A new OS process must recover from disk, including a settled round."""
    children = []
    runner.LOGS.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="restart_reconnect_", dir=runner.LOGS) as temporary:
        folder = Path(temporary).resolve()

        def launch(role):
            name = f"restart_reconnect_{role}"
            item = runner.launch(godot, name, "res://tests/restart_reconnect_network.gd",
                                 [f"--restart-role={role}", f"--restart-dir={folder.as_posix()}"])
            children.append((item, name))
            return item

        def wait_marker(name, seconds=25):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                for item, label in children:
                    errors = (runner.LOGS / f"{label}.err").read_text(encoding="utf-8-sig", errors="replace")
                    if "ERROR:" in errors:
                        raise AssertionError(f"{label}: {errors}")
                if (folder / f"{name}.json").exists():
                    return
                time.sleep(0.05)
            raise AssertionError(f"Restart test timed out waiting for {name}")

        def kill_client(item, label):
            process, stdout, stderr = item
            assert process.poll() is None, f"{label} exited before forced restart"
            process.kill()
            process.wait(timeout=5)
            stdout.close()
            stderr.close()
            print(f"[ok] {label}: force-closed process; next client uses disk state only", flush=True)

        try:
            host = launch("host")
            time.sleep(0.5)
            first = launch("first")
            wait_marker("first_ready")
            kill_client(first, "restart_reconnect_first")
            restarted = launch("resume")
            wait_marker("settled_ready")
            kill_client(restarted, "restart_reconnect_resume")
            settled = launch("settled")
            runner.finish(settled, "restart_reconnect_settled", 25)
            wait_marker("replacement_ready")
            expired = launch("expired")
            runner.finish(expired, "restart_reconnect_expired", 20)
            runner.finish(host, "restart_reconnect_host", 15)
        finally:
            for item, _ in children:
                process, stdout, stderr = item
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
                stdout.close()
                stderr.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    run(parser.parse_args().godot)
