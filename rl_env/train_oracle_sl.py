"""Oracle 标签 SL：521 维可见特征 → 113 个固定动作。

输入由 prepare_oracle_dataset.py 生成。训练/验证按整局切分，避免同局泄漏。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


class OracleNet(nn.Module):
    def __init__(self, feature_dim: int = 521, action_dim: int = 113):
        super().__init__()
        self.trunk = nn.Sequential(
            nn.Linear(feature_dim, 256), nn.ReLU(),
            nn.Linear(256, 256), nn.ReLU(),
        )
        self.policy = nn.Linear(256, action_dim)
        self.value = nn.Linear(256, 1)

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        h = self.trunk(x)
        return self.policy(h), self.value(h).squeeze(-1)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--data", default="build/ai_high/oracle_data20")
    p.add_argument("--out", default="build/ai_high/oracle_sl")
    p.add_argument("--epochs", type=int, default=20)
    p.add_argument("--batch-size", type=int, default=64)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--seed", type=int, default=20261101)
    return p.parse_args()


def load_split(root: Path, split: str) -> tuple[np.ndarray, ...]:
    npz = root / f"{split}.npz"
    if npz.exists():
        d = np.load(npz)
        return d["X"], d["M"], d["A"], d["V"], d["G"]
    import pyarrow.parquet as pq
    table = pq.read_table(root / f"{split}.parquet").to_pydict()
    return (
        np.asarray(table["x"], dtype=np.float32),
        np.asarray(table["mask"], dtype=np.uint8),
        np.asarray(table["action"], dtype=np.int64),
        np.asarray(table["value"], dtype=np.float32),
        np.asarray(table["game"], dtype=np.int64),
    )


def masked_logits(logits: torch.Tensor, mask: torch.Tensor) -> torch.Tensor:
    return logits.masked_fill(~mask, -1e9)


def evaluate(model: OracleNet, X: torch.Tensor, M: torch.Tensor, A: torch.Tensor) -> dict:
    model.eval()
    with torch.no_grad():
        logits, _value = model(X)
        logits = masked_logits(logits, M.bool())
        top1 = (logits.argmax(1) == A).float().mean().item()
        k = min(5, logits.shape[1])
        top5 = (logits.topk(k, dim=1).indices == A[:, None]).any(1).float().mean().item()
        loss = F.cross_entropy(logits, A).item()
    return {"loss": loss, "top1": top1, "top5": top5, "rows": int(len(A))}


def main() -> None:
    args = parse_args()
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)
    root = Path(args.data)
    Xtr, Mtr, Atr, Vtr, Gtr = load_split(root, "train")
    Xv, Mv, Av, Vv, Gv = load_split(root, "val")
    assert Xtr.shape[1] in (521, 584) and Mtr.shape[1] == 113, (Xtr.shape, Mtr.shape)
    assert Av.size > 0, "empty validation split"

    Xtr_t = torch.from_numpy(Xtr)
    Mtr_t = torch.from_numpy(Mtr).bool()
    Atr_t = torch.from_numpy(Atr)
    Xv_t = torch.from_numpy(Xv)
    Mv_t = torch.from_numpy(Mv).bool()
    Av_t = torch.from_numpy(Av)

    model = OracleNet(Xtr.shape[1], Mtr.shape[1])
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    dl = torch.utils.data.DataLoader(
        torch.utils.data.TensorDataset(Xtr_t, Mtr_t, Atr_t),
        batch_size=args.batch_size, shuffle=True,
    )
    best = None
    best_state = None
    history = []
    for epoch in range(1, args.epochs + 1):
        model.train()
        total = 0.0
        seen = 0
        for xb, mb, ab in dl:
            opt.zero_grad(set_to_none=True)
            logits, value = model(xb)
            logits = masked_logits(logits, mb)
            loss = F.cross_entropy(logits, ab) + 0.25 * F.mse_loss(value, torch.zeros_like(value))
            loss.backward()
            opt.step()
            total += float(loss.item()) * len(xb)
            seen += len(xb)
        metrics = evaluate(model, Xv_t, Mv_t, Av_t)
        metrics["epoch"] = epoch
        metrics["train_loss"] = total / max(1, seen)
        history.append(metrics)
        print(json.dumps(metrics, ensure_ascii=False), flush=True)
        if best is None or metrics["top1"] > best["top1"]:
            best = metrics
            best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}

    if best_state is not None:
        model.load_state_dict(best_state)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out / "oracle_sl.pt")
    weights = {k: v.detach().cpu().tolist() for k, v in model.state_dict().items()}
    (out / "oracle_sl_weights.json").write_text(
        json.dumps(weights, ensure_ascii=False), encoding="utf-8"
    )
    metadata = {
        "feature_dim": int(Xtr.shape[1]),
        "action_dim": int(Mtr.shape[1]),
        "train_rows": int(len(Atr)),
        "val_rows": int(len(Av)),
        "best_val": best,
        "history": history,
        "architecture": f"{Xtr.shape[1]}->256->256->113",
        "feature_version": 2 if Xtr.shape[1] == 584 else 1,
    }
    (out / "metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("saved", out, "best", best)


if __name__ == "__main__":
    main()
