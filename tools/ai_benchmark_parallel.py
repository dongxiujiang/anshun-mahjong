#!/usr/bin/env python3
"""Run the authoritative Godot AI benchmark in parallel headless workers.

Each worker uses the real RoundState, scoring and AI code, so the rules cannot
drift from the shipped game. Only the 10000-game workload is split.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

LEVELS = ("low", "medium", "high")
LEVEL_NAMES = {"low": "低", "medium": "中", "high": "高"}
DEFAULT_GODOT = r"C:\Users\xiu\Desktop\Godot_v4.7.2-stable_win64.exe"


def _split(total: int, workers: int) -> list[tuple[int, int]]:
    base, extra = divmod(total, workers)
    parts: list[tuple[int, int]] = []
    start = 0
    for index in range(workers):
        count = base + (1 if index < extra else 0)
        if count:
            parts.append((start, count))
        start += count
    return parts


def _run_part(godot: str, root: Path, start: int, count: int, output: Path) -> dict:
    cmd = [
        godot,
        "--headless",
        "--path",
        str(root),
        "--script",
        "res://tools/ai_benchmark_worker.gd",
        "--",
        "--start",
        str(start),
        "--count",
        str(count),
        "--output",
        str(output),
    ]
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60 * 60 * 4,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"worker start={start} count={count} exit={proc.returncode}\n"
            f"stdout:\n{proc.stdout[-2000:]}\nstderr:\n{proc.stderr[-2000:]}"
        )
    if not output.exists():
        raise RuntimeError(f"worker start={start} did not write {output}")
    return json.loads(output.read_text(encoding="utf-8"))


def _empty_stats() -> dict:
    return {level: {"games": 0, "wins": 0, "deal_ins": 0, "score": 0.0} for level in LEVELS}


def _merge(stats: dict, report: dict) -> None:
    for level in LEVELS:
        src = report.get("levels", {}).get(level, {})
        dst = stats[level]
        for key in ("games", "wins", "deal_ins"):
            dst[key] += int(src.get(key, 0))
        dst["score"] += float(src.get("score", 0.0))


def _format(stats: dict, games: int, elapsed: float) -> str:
    lines = [f"AI测试：{games} 局，用时 {elapsed / 60.0:.1f} 分钟"]
    for level in LEVELS:
        item = stats[level]
        n = max(1, item["games"])
        lines.append(
            f"{LEVEL_NAMES[level]}：胜率 {100.0 * item['wins'] / n:.1f}%  "
            f"放炮 {100.0 * item['deal_ins'] / n:.1f}%  "
            f"均分 {item['score'] / n:.1f}"
        )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games", type=int, default=10000)
    parser.add_argument("--workers", type=int, default=min(16, os.cpu_count() or 1))
    parser.add_argument("--godot", default=DEFAULT_GODOT)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    workers = max(1, min(args.workers, args.games))
    if not Path(args.godot).exists():
        print(f"Godot not found: {args.godot}", file=sys.stderr)
        return 2

    parts = _split(args.games, workers)
    temp_dir = Path(tempfile.mkdtemp(prefix="ai-benchmark-", dir=str(root / "build")))
    stats = _empty_stats()
    started = time.monotonic()
    print(f"并行 AI 测试：{args.games} 局 / {len(parts)} workers", flush=True)

    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=len(parts)) as pool:
        futures = {
            pool.submit(_run_part, args.godot, root, start, count, temp_dir / f"part-{start}.json"): (start, count)
            for start, count in parts
        }
        completed_games = 0
        for future in as_completed(futures):
            start, count = futures[future]
            try:
                report = future.result()
            except Exception as exc:  # noqa: BLE001 - surface worker failures clearly
                failures.append(str(exc))
                print(f"worker {start} 失败：{exc}", file=sys.stderr, flush=True)
                continue
            _merge(stats, report)
            completed_games += int(report.get("games", 0))
            print(f"worker {start}+{count} 完成，累计 {completed_games}/{args.games}", flush=True)

    elapsed = time.monotonic() - started
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1

    text = _format(stats, completed_games, elapsed)
    print("\n" + text)
    output = Path(args.output) if args.output else root / "build" / "ai_benchmark_parallel.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {"games": completed_games, "elapsed_seconds": elapsed, "workers": len(parts), "levels": stats},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"\n结果：{output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
