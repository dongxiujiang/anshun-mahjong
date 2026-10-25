#!/usr/bin/env python3
"""Calibrate AI discard risk: predicted deal-in probability vs observed rate."""

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
BINS = [(0.0, 0.005), (0.005, 0.01), (0.01, 0.02), (0.02, 0.04), (0.04, 0.08), (0.08, 0.16), (0.16, 0.32), (0.32, 1.01)]


def _split(total: int, workers: int) -> list[tuple[int, int]]:
    base, extra = divmod(total, workers)
    out = []
    start = 0
    for index in range(workers):
        count = base + (1 if index < extra else 0)
        if count:
            out.append((start, count))
        start += count
    return out


def _run(godot: str, root: Path, start: int, count: int, output: Path) -> list:
    cmd = [godot, "--headless", "--path", str(root), "--script",
           "res://tools/ai_risk_calibration_worker.gd", "--",
           "--start", str(start), "--count", str(count), "--output", str(output)]
    proc = subprocess.run(cmd, cwd=str(root), capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=60 * 60 * 4)
    if proc.returncode != 0 or not output.exists():
        raise RuntimeError(f"worker {start}+{count} failed\n{proc.stdout[-1500:]}\n{proc.stderr[-1500:]}")
    return json.loads(output.read_text(encoding="utf-8")).get("samples", [])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--games", type=int, default=4000)
    parser.add_argument("--workers", type=int, default=min(16, os.cpu_count() or 1))
    parser.add_argument("--godot", default=DEFAULT_GODOT)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    parser.add_argument("--output", default="")
    args = parser.parse_args()
    root = Path(args.root).resolve()
    parts = _split(args.games, max(1, min(args.workers, args.games)))
    temp_dir = Path(tempfile.mkdtemp(prefix="ai-risk-", dir=str(root / "build")))
    samples: list = []
    started = time.monotonic()
    print(f"风险标定：{args.games} 局 / {len(parts)} workers", flush=True)
    with ThreadPoolExecutor(max_workers=len(parts)) as pool:
        futures = {pool.submit(_run, args.godot, root, start, count, temp_dir / f"part-{start}.json"): (start, count)
                   for start, count in parts}
        for future in as_completed(futures):
            start, count = futures[future]
            try:
                samples.extend(future.result())
                print(f"worker {start}+{count} 完成", flush=True)
            except Exception as exc:  # noqa: BLE001
                print(f"worker {start} 失败：{exc}", file=sys.stderr, flush=True)
                return 1
    elapsed = time.monotonic() - started
    rows = []
    total = max(1, len(samples))
    brier = 0.0
    logloss = 0.0
    pred_sum = 0.0
    actual_sum = 0.0
    for low, high in BINS:
        bucket = [(s[0], s[1]) for s in samples if low <= s[0] < high]
        n = len(bucket)
        pred = sum(p for p, _ in bucket) / n if n else 0.0
        actual = sum(y for _, y in bucket) / n if n else 0.0
        rows.append((low, high, n, pred, actual))
    for sample in samples:
        p = min(1.0, max(0.0, float(sample[0])))
        y = float(sample[1])
        pred_sum += p
        actual_sum += y
        brier += (p - y) ** 2
        logloss -= y * math.log(max(1e-12, p)) + (1 - y) * math.log(max(1e-12, 1 - p))
    print(f"\n样本：{len(samples)} 次弃牌，实际点炮 {int(actual_sum)} 次")
    print(f"预测均值：{pred_sum / total:.4f}  实际率：{actual_sum / total:.4f}  "
          f"Brier：{brier / total:.5f}  LogLoss：{logloss / total:.4f}")
    print("\n风险区间          样本      预测均值   实际率")
    for low, high, n, pred, actual in rows:
        print(f"[{low:.3f},{high:.3f})  {n:7d}   {pred:.4f}   {actual:.4f}")

    # 先合并稀疏高桶，再做单调校准（PAV），生成预测→实际点炮率查找表。
    table = [[low, high, n, pred * n, actual * n]
             for low, high, n, pred, actual in rows if n > 0]
    while len(table) > 1 and table[-1][2] < 200:
        tail = table.pop()
        table[-1][1] = tail[1]
        table[-1][2] += tail[2]
        table[-1][3] += tail[3]
        table[-1][4] += tail[4]
    index = 0
    while index + 1 < len(table):
        if table[index][4] / table[index][2] <= table[index + 1][4] / table[index + 1][2]:
            index += 1
            continue
        left, right = table[index], table[index + 1]
        table[index] = [left[0], right[1], left[2] + right[2],
                        left[3] + right[3], left[4] + right[4]]
        table.pop(index + 1)
        index = max(0, index - 1)
    calibration = []
    print("\n校准查找表（单调，已合并稀疏高桶）")
    print("预测区间             样本      实际率")
    for low, high, n, pred_total, actual_total in table:
        calibration.append([low, high, n, pred_total / n, actual_total / n])
        print(f"[{low:.3f},{high:.3f})  {n:7d}   {actual_total / n:.4f}")

    strength_bins = [(0.0, 0.2), (0.2, 0.4), (0.4, 0.6), (0.6, 0.8), (0.8, 1.01)]
    loss_by_strength = []
    print("\n对手强度（最高听牌概率）   点炮次数   平均实际损失")
    for low, high in strength_bins:
        bucket = [s for s in samples if s[1] > 0 and low <= s[2] < high]
        avg_loss = sum(float(s[3]) for s in bucket) / len(bucket) if bucket else 0.0
        loss_by_strength.append([low, high, len(bucket), avg_loss])
        print(f"[{low:.1f},{high:.1f})                 {len(bucket):5d}      {avg_loss:8.2f}")
    output = Path(args.output) if args.output else root / "build" / "ai_risk_calibration.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"samples": len(samples), "elapsed_seconds": elapsed,
                                  "predicted_mean": pred_sum / total, "actual_rate": actual_sum / total,
                                  "brier": brier / total, "logloss": logloss / total,
                                  "bins": rows, "calibration": calibration,
                                  "loss_by_strength": loss_by_strength}, ensure_ascii=False, indent=2),
                      encoding="utf-8")
    print(f"\n结果：{output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
