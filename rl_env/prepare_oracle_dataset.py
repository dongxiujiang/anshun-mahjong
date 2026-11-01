"""把 oracle_collector.gd 的 JSONL 转成可训练的 parquet/npz 数据集。

用法：
    python rl_env/prepare_oracle_dataset.py \
      --input build/oracle_data_20.jsonl \
      --out build/ai_high/oracle_data

输出：
    train.parquet / val.parquet
    train.npz / val.npz（可选，--npz）
    stats.json
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--input", action="append", required=True,
                   help="JSONL 文件，可重复传入")
    p.add_argument("--out", required=True)
    p.add_argument("--val-ratio", type=float, default=0.1)
    p.add_argument("--min-steps", type=int, default=20)
    p.add_argument("--require-chicken", action="store_true")
    p.add_argument("--npz", action="store_true")
    return p.parse_args()


def load_rows(paths: list[str], min_steps: int, require_chicken: bool) -> list[dict]:
    rows: list[dict] = []
    for name in paths:
        path = Path(name)
        if not path.exists():
            raise FileNotFoundError(path)
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if int(row.get("steps", 0)) < min_steps:
                    continue
                if require_chicken and not bool(row.get("has_chicken", False)):
                    continue
                mask = row.get("mask", [])
                action = int(row.get("action", -1))
                if action < 0 or action >= len(mask) or not int(mask[action]):
                    continue
                rows.append(row)
    return rows


def write_split(rows: list[dict], path: Path, with_npz: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    table = pa.table({
        "game": pa.array([int(r["game"]) for r in rows], type=pa.int64()),
        "step": pa.array([int(r.get("step", 0)) for r in rows], type=pa.int32()),
        "seat": pa.array([int(r.get("seat", 0)) for r in rows], type=pa.int8()),
        "kind": pa.array([str(r.get("kind", "")) for r in rows], type=pa.string()),
        "x": pa.array([[float(v) for v in r["x"]] for r in rows],
                      type=pa.list_(pa.float32())),
        "mask": pa.array([[int(v) for v in r["mask"]] for r in rows],
                         type=pa.list_(pa.uint8())),
        "action": pa.array([int(r["action"]) for r in rows], type=pa.int16()),
        "probs": pa.array([json.dumps(r.get("probs", {}), ensure_ascii=False) for r in rows],
                          type=pa.string()),
        "value": pa.array([float(r.get("value", 0.0)) for r in rows], type=pa.float32()),
        "oracle_seat": pa.array([int(r.get("oracle_seat", 0)) for r in rows], type=pa.int8()),
        "has_chicken": pa.array([bool(r.get("has_chicken", False)) for r in rows], type=pa.bool_()),
        "has_kong": pa.array([bool(r.get("has_kong", False)) for r in rows], type=pa.bool_()),
        "has_charge_chicken": pa.array([bool(r.get("has_charge_chicken", False)) for r in rows], type=pa.bool_()),
    })
    pq.write_table(table, path.with_suffix(".parquet"), compression="zstd")
    if with_npz:
        np.savez_compressed(
            path.with_suffix(".npz"),
            X=np.asarray([r["x"] for r in rows], dtype=np.float32),
            M=np.asarray([r["mask"] for r in rows], dtype=np.uint8),
            A=np.asarray([r["action"] for r in rows], dtype=np.int64),
            V=np.asarray([r["value"] for r in rows], dtype=np.float32),
            G=np.asarray([int(r["game"]) for r in rows], dtype=np.int64),
        )


def main() -> None:
    args = parse_args()
    rows = load_rows(args.input, args.min_steps, args.require_chicken)
    games = sorted({int(r["game"]) for r in rows})
    if not games:
        raise SystemExit("no valid rows")
    rng = np.random.default_rng(20261101)
    rng.shuffle(games)
    val_count = max(1, int(round(len(games) * args.val_ratio))) if len(games) > 1 else 0
    val_games = set(int(g) for g in games[:val_count])
    train_rows = [r for r in rows if int(r["game"]) not in val_games]
    val_rows = [r for r in rows if int(r["game"]) in val_games]
    out = Path(args.out)
    write_split(train_rows, out / "train", args.npz)
    write_split(val_rows, out / "val", args.npz)
    stats = {
        "source": args.input,
        "games": len(games),
        "train_games": len(games) - len(val_games),
        "val_games": len(val_games),
        "rows": len(rows),
        "train_rows": len(train_rows),
        "val_rows": len(val_rows),
        "feature_dim": len(rows[0]["x"]),
        "action_dim": len(rows[0]["mask"]),
        "chicken_rows": sum(1 for r in rows if r.get("has_chicken")),
        "kong_rows": sum(1 for r in rows if r.get("has_kong")),
        "charge_chicken_rows": sum(1 for r in rows if r.get("has_charge_chicken")),
    }
    (out / "stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
