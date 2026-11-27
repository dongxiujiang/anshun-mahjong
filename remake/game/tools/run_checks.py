"""Run the remake's real Godot suites, retaining bounded logs and source hashes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
from datetime import datetime, timezone


PROJECT = Path(__file__).resolve().parents[1]
REPOSITORY = PROJECT.parents[1]


def source_hashes():
    paths = [PROJECT / "project.godot"]
    paths += sorted((REPOSITORY / "docs").rglob("*.md"))
    paths += sorted((PROJECT / "src").rglob("*.gd"))
    paths += sorted((PROJECT / "tests").rglob("*.gd"))
    paths += sorted((PROJECT / "tests").rglob("*.json"))
    paths += sorted((PROJECT / "assets/layouts").glob("*.json"))
    paths.append(Path(__file__).resolve())
    return {str(path.relative_to(REPOSITORY)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--suite", action="append", help="Name such as test_wall; repeat to select multiple suites")
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--dice-samples", type=int, default=24)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.godot.is_file():
        parser.error("Godot executable does not exist")
    suites = sorted((PROJECT / "tests").glob("test_*.gd"))
    if args.suite:
        missing = set(args.suite) - {path.stem for path in suites}
        if missing:
            parser.error("Unknown suites: " + ", ".join(sorted(missing)))
        suites = [path for path in suites if path.stem in args.suite]
    started = datetime.now(timezone.utc)
    output = args.output or REPOSITORY / "build/remake-acceptance" / started.strftime("%Y%m%dT%H%M%S%fZ")
    output.mkdir(parents=True, exist_ok=True)
    hashes_before = source_hashes()
    records = []
    for suite in suites:
        command = [str(args.godot.resolve()), "--headless", "--path", str(PROJECT), "--fixed-fps", "60", "--script", "res://tests/" + suite.name]
        if suite.stem == "test_dice":
            command += ["--", "--samples=" + str(args.dice_samples)]
        begin = time.monotonic()
        timed_out = False
        try:
            process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=args.timeout)
            log = process.stdout + process.stderr
            code = process.returncode
        except subprocess.TimeoutExpired as error:
            timed_out = True
            # subprocess.run kills and waits for the one Godot child on timeout.
            chunks = [error.stdout or b"", error.stderr or b""]
            log = "".join(chunk.decode("utf-8", "replace") if isinstance(chunk, bytes) else chunk for chunk in chunks)
            log += "\nSUITE TIMED OUT\n"
            code = None
        marker = bool(re.search(r"\b\d+ checks, 0 failures\b|\btests passed\b", log))
        engine_error = bool(re.search(r"\b(?:SCRIPT ERROR|ERROR):", log))
        passed = code == 0 and marker and not engine_error and not timed_out
        (output / (suite.stem + ".log")).write_text(log, encoding="utf-8")
        records.append({"suite": suite.stem, "passed": passed, "exit_code": code, "timed_out": timed_out,
                        "pass_marker": marker, "engine_error": engine_error, "seconds": round(time.monotonic() - begin, 3), "command": command})
        print(("PASS " if passed else "FAIL ") + suite.stem, flush=True)
        if not passed:
            print(f"  exit_code={code} timed_out={timed_out} pass_marker={marker} engine_error={engine_error}", flush=True)
            print("  Last 40 non-empty log lines:", flush=True)
            print("\n".join([line for line in log.splitlines() if line.strip()][-40:]), flush=True)
    hashes_after = source_hashes()
    stable = hashes_before == hashes_after
    passed = bool(records) and stable and all(record["passed"] for record in records)
    report = {"started_utc": started.isoformat(), "kind": "Godot headless logic and physics checks; not mobile or release acceptance",
              "passed": passed, "sources_unchanged_during_run": stable, "suites": records,
              "sources_before": hashes_before, "sources_after": hashes_after}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Report: " + str(output / "report.json"), flush=True)
    if not stable:
        print("Source changed during this run; the combined result cannot be accepted.", flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
