#!/usr/bin/env python3
"""Paired-seed A/B benchmark for the Godot AI.

Same seed, wall and deal for candidate and baseline; only the AI policy at one
seat changes. Reports win rate, deal-in rate, average score, paired score delta
and per-decision latency.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

DEFAULT_GODOT = r"C:\Users\xiu\Desktop\Godot_v4.7.2-stable_win64.exe"


def _split(total: int, workers: int) -> list[tuple[int, int]]:
    base, extra = divmod(total, workers)
    out: list[tuple[int, int]] = []
    start = 0
    for index in range(workers):
        count = base + (1 if index < extra else 0)
        if count:
            out.append((start, count))
        start += count
    return out


def _run(godot: str, root: Path, start: int, count: int, candidate: str, baseline: str, defense: float, inference: float, calibrated: bool, risk_aversion: float, output: Path) -> dict:
    cmd = [
        godot, "--headless", "--path", str(root), "--script",
        "res://tools/ai_paired_ab_worker.gd", "--",
        "--start", str(start), "--pairs", str(count),
        "--candidate", candidate, "--baseline", baseline, "--defense", str(defense),
        "--inference", str(inference),
        "--output", str(output),
    ]
    if calibrated:
        cmd.append("--calibrated")
    cmd += ["--risk-aversion", str(risk_aversion)]
    proc = subprocess.run(cmd, cwd=str(root), capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=60 * 60 * 4)
    if proc.returncode != 0 or not output.exists():
        raise RuntimeError(f"worker {start}+{count} failed exit={proc.returncode}\n{proc.stdout[-1500:]}\n{proc.stderr[-1500:]}")
    return json.loads(output.read_text(encoding="utf-8"))


def _p95(values: list[float]) -> float:
    if not values:
        return 0.0
    data = sorted(values)
    return data[min(len(data) - 1, int(len(data) * 0.95))]


def _merge(total: dict, part: dict) -> None:
    for key in ("pairs", "failed", "candidate_wins", "baseline_wins", "candidate_deals", "baseline_deals"):
        total[key] += int(part.get(key, 0))
    total["candidate_score"] += float(part.get("candidate_score", 0.0))
    total["baseline_score"] += float(part.get("baseline_score", 0.0))
    for key in ("candidate_expected_discard_loss", "baseline_expected_discard_loss",
                "candidate_actual_discard_loss", "baseline_actual_discard_loss"):
        total[key] += float(part.get(key, 0.0))
    total["expected_loss_deltas"].extend(part.get("expected_loss_deltas", []))
    total["actual_loss_deltas"].extend(part.get("actual_loss_deltas", []))
    total["deltas"].extend(part.get("deltas", []))
    total["candidate_ms"].extend(part.get("candidate_ms", []))
    total["baseline_ms"].extend(part.get("baseline_ms", []))


def _mean_ci(values: list[float]) -> tuple[float, float]:
    mean = sum(values) / max(1, len(values))
    variance = sum((x - mean) ** 2 for x in values) / max(1, len(values) - 1)
    ci = 1.96 * math.sqrt(variance / max(1, len(values))) if len(values) > 1 else 0.0
    return mean, ci


def _report(total: dict, elapsed: float) -> str:
    n = max(1, total["pairs"])
    deltas = total["deltas"]
    mean = sum(deltas) / max(1, len(deltas))
    variance = sum((x - mean) ** 2 for x in deltas) / max(1, len(deltas) - 1)
    ci = 1.96 * math.sqrt(variance / max(1, len(deltas))) if len(deltas) > 1 else 0.0
    exp_mean, exp_ci = _mean_ci(total["expected_loss_deltas"])
    act_mean, act_ci = _mean_ci(total["actual_loss_deltas"])
    cand_ms = total["candidate_ms"]
    base_ms = total["baseline_ms"]
    lines = [
        f"配对 A/B：{total['pairs']} 对，失败 {total['failed']}，用时 {elapsed / 60.0:.1f} 分钟",
        f"候选 {total['candidate']} vs baseline {total['baseline']}",
        f"候选：胜率 {100.0 * total['candidate_wins'] / n:.2f}%  放炮 {100.0 * total['candidate_deals'] / n:.2f}%  均分 {total['candidate_score'] / n:+.2f}",
        f"基准：胜率 {100.0 * total['baseline_wins'] / n:.2f}%  放炮 {100.0 * total['baseline_deals'] / n:.2f}%  均分 {total['baseline_score'] / n:+.2f}",
        f"配对分差：{mean:+.3f}  95%CI [{mean - ci:+.3f}, {mean + ci:+.3f}]",
        f"决策耗时 候选 avg {sum(cand_ms) / max(1, len(cand_ms)):.1f}ms p95 {_p95(cand_ms):.1f}ms  "
        f"基准 avg {sum(base_ms) / max(1, len(base_ms)):.1f}ms p95 {_p95(base_ms):.1f}ms",
        f"弃牌级校准期望损失：候选 {total['candidate_expected_discard_loss'] / n:.2f}  "
        f"基准 {total['baseline_expected_discard_loss'] / n:.2f}  "
        f"配对Δ {exp_mean:+.3f} CI [{exp_mean - exp_ci:+.3f}, {exp_mean + exp_ci:+.3f}]",
        f"弃牌级实际损失：候选 {total['candidate_actual_discard_loss'] / n:.2f}  "
        f"基准 {total['baseline_actual_discard_loss'] / n:.2f}  "
        f"配对Δ {act_mean:+.3f} CI [{act_mean - act_ci:+.3f}, {act_mean + act_ci:+.3f}]",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pairs", type=int, default=1000)
    parser.add_argument("--workers", type=int, default=min(16, os.cpu_count() or 1))
    parser.add_argument("--candidate", default="medium")
    parser.add_argument("--baseline", default="low")
    parser.add_argument("--defense", type=float, default=0.0)
    parser.add_argument("--inference", type=float, default=1.0)
    parser.add_argument("--calibrated", action="store_true")
    parser.add_argument("--risk-aversion", type=float, default=1.0)
    parser.add_argument("--godot", default=DEFAULT_GODOT)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    workers = max(1, min(args.workers, args.pairs))
    if not Path(args.godot).exists():
        print(f"Godot not found: {args.godot}", file=sys.stderr)
        return 2
    parts = _split(args.pairs, workers)
    temp_dir = Path(tempfile.mkdtemp(prefix="ai-paired-", dir=str(root / "build")))
    total = {
        "pairs": 0, "failed": 0, "candidate": args.candidate, "baseline": args.baseline,
        "candidate_wins": 0, "baseline_wins": 0, "candidate_deals": 0, "baseline_deals": 0,
        "candidate_score": 0.0, "baseline_score": 0.0, "defense_weight": args.defense,
        "inference_weight": args.inference, "calibrated": args.calibrated,
        "risk_aversion": args.risk_aversion,
        "candidate_expected_discard_loss": 0.0, "baseline_expected_discard_loss": 0.0,
        "candidate_actual_discard_loss": 0.0, "baseline_actual_discard_loss": 0.0,
        "expected_loss_deltas": [], "actual_loss_deltas": [],
        "deltas": [], "candidate_ms": [], "baseline_ms": [],
    }
    started = time.monotonic()
    print(f"配对 A/B：{args.pairs} 对 / {len(parts)} workers", flush=True)
    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=len(parts)) as pool:
        futures = {
            pool.submit(_run, args.godot, root, start, count, args.candidate, args.baseline, args.defense, args.inference, args.calibrated, args.risk_aversion,
                        temp_dir / f"part-{start}.json"): (start, count)
            for start, count in parts
        }
        for future in as_completed(futures):
            start, count = futures[future]
            try:
                _merge(total, future.result())
                print(f"worker {start}+{count} 完成", flush=True)
            except Exception as exc:  # noqa: BLE001
                failures.append(str(exc))
                print(f"worker {start} 失败：{exc}", file=sys.stderr, flush=True)
    elapsed = time.monotonic() - started
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print("\n" + _report(total, elapsed))
    output = Path(args.output) if args.output else root / "build" / "ai_paired_ab.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({**total, "elapsed_seconds": elapsed, "workers": len(parts)},
                                 ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n结果：{output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
