"""Run registered Godot suites with wall-clock deadlines and persistent logs."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import time

PROJECT = Path(__file__).resolve().parents[1]
LOGS = PROJECT / "build" / "test_results"


def run_suite(godot, suite, timeout):
    name = Path(suite).stem
    output_path = LOGS / f"{name}.log"
    error_path = LOGS / f"{name}.err"
    print(f"[run] {name} (deadline {timeout}s)", flush=True)
    started = time.monotonic()
    failure = ""
    with output_path.open("w", encoding="utf-8") as stdout, error_path.open("w", encoding="utf-8") as stderr:
        process = subprocess.Popen(
            [godot, "--headless", "--path", str(PROJECT), "--script", suite],
            stdout=stdout, stderr=stderr,
        )
        try:
            while process.poll() is None:
                errors = error_path.read_text(encoding="utf-8-sig", errors="replace")
                if "SCRIPT ERROR:" in errors or "ERROR:" in errors:
                    failure = "Godot reported an error"
                    break
                if time.monotonic() - started > timeout:
                    failure = f"deadline exceeded ({timeout}s)"
                    break
                time.sleep(0.1)
        finally:
            # Only terminate the child owned by this suite runner.
            if process.poll() is None:
                process.kill()
            process.wait()
    output = output_path.read_text(encoding="utf-8-sig", errors="replace")
    errors = error_path.read_text(encoding="utf-8-sig", errors="replace")
    completed = any(
        line.startswith(f"[{name}]") and any(word in line for word in ("passed", "通过", "0 failures"))
        for line in output.splitlines()
    )
    if failure or process.returncode != 0 or not completed or "SCRIPT ERROR:" in errors or "ERROR:" in errors:
        print(f"[FAIL] {name}: {failure or 'missing completion or nonzero exit'} (exit {process.returncode})\n{output}\n{errors}", flush=True)
        return False
    elapsed = time.monotonic() - started
    print(f"[ok] {name}: {elapsed:.1f}s", flush=True)
    for line in output.splitlines():
        if line.startswith(f"[{name}]"):
            print(line, flush=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--suite", nargs="+", help="Suite basenames; defaults to all entries in run_all.gd")
    parser.add_argument("--timeout", type=float, default=120, help="Seconds per ordinary suite")
    parser.add_argument("--simulation-timeout", type=float, default=600, help="Seconds per AI simulation suite")
    args = parser.parse_args()
    suites = [f"res://tests/{name.removesuffix('.gd')}.gd" for name in args.suite] if args.suite else re.findall(
        r'"(res://tests/[^"\n]+\.gd)"', (PROJECT / "tests" / "run_all.gd").read_text(encoding="utf-8-sig")
    )
    if not suites:
        print("[run_suites] no suites discovered", flush=True)
        raise SystemExit(1)
    LOGS.mkdir(parents=True, exist_ok=True)
    failed = []
    for suite in suites:
        timeout = args.simulation_timeout if Path(suite).stem in ("smoke_ai", "sweep") else args.timeout
        if not run_suite(args.godot, suite, timeout):
            failed.append(suite)
    print(f"[run_suites] passed {len(suites) - len(failed)}/{len(suites)}", flush=True)
    if failed:
        print("Failed: " + ", ".join(failed), flush=True)
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
