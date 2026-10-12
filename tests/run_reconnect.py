"""Exercise real ENet reconnection in the lobby and during gameplay."""
import argparse
import importlib.util
from pathlib import Path
import time

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

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    run(parser.parse_args().godot)
