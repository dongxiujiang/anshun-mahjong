"""Oracle SL 双头：共享 trunk，出牌/响应分头。

turn 头覆盖 0..108，response 头覆盖 109..112；最终仍是同一套 113 动作空间。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from train_oracle_sl import load_split, masked_logits


class DualNet(nn.Module):
    def __init__(self, feature_dim: int = 584, hidden: int = 256):
        super().__init__()
        self.trunk = nn.Sequential(
            nn.Linear(feature_dim, hidden), nn.ReLU(),
            nn.Linear(hidden, hidden), nn.ReLU(),
        )
        self.turn_policy = nn.Linear(hidden, 109)
        self.resp_policy = nn.Linear(hidden, 4)
        self.value = nn.Linear(hidden, 1)

    def forward(self, x):
        h = self.trunk(x)
        return self.turn_policy(h), self.resp_policy(h), self.value(h).squeeze(-1)

    def global_logits(self, x):
        turn, resp, value = self.forward(x)
        return torch.cat([turn, resp], dim=1), value


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--data", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--lr", type=float, default=3e-4)
    p.add_argument("--hidden", type=int, default=256)
    p.add_argument("--seed", type=int, default=20261101)
    return p.parse_args()


def split_loss(logits, mask, target, soft):
    target = target.clamp(0, 108)
    if soft is not None and float(soft.sum()) > 0:
        return -(soft * F.log_softmax(logits, dim=-1)).sum(-1).mean()
    return F.cross_entropy(logits, target)


def main():
    args = parse_args()
    torch.manual_seed(args.seed)
    root = Path(args.data)
    Xtr, Mtr, Atr, Vtr, Gtr, Ptr = load_split(root, "train")
    Xv, Mv, Av, Vv, Gv, Pv = load_split(root, "val")
    model = DualNet(Xtr.shape[1], args.hidden)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    X = torch.tensor(Xtr)
    M = torch.tensor(Mtr).bool()
    A = torch.tensor(Atr)
    P = torch.tensor(Ptr)
    Xv_t = torch.tensor(Xv)
    Mv_t = torch.tensor(Mv).bool()
    Av_t = torch.tensor(Av)
    Pv_t = torch.tensor(Pv)
    n = len(A)
    best = None
    best_state = None
    history = []
    for epoch in range(1, args.epochs + 1):
        model.train()
        order = torch.randperm(n)
        total = 0.0
        seen = 0
        for start in range(0, n, args.batch_size):
            idx = order[start:start + args.batch_size]
            turn_logits, resp_logits, value = model(X[idx])
            turn_sel = A[idx] <= 108
            resp_sel = ~turn_sel
            loss = torch.zeros((), dtype=torch.float32)
            if turn_sel.any():
                turn_mask = M[idx][turn_sel][:, :109]
                loss = loss + split_loss(turn_logits[turn_sel], turn_mask, A[idx][turn_sel],
                                         P[idx][turn_sel][:, :109])
            if resp_sel.any():
                resp_mask = M[idx][resp_sel][:, 109:]
                loss = loss + split_loss(resp_logits[resp_sel], resp_mask,
                                         A[idx][resp_sel] - 109, P[idx][resp_sel][:, 109:])
            loss = loss + 0.25 * F.mse_loss(value, torch.zeros_like(value))
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            total += float(loss.item()) * len(idx)
            seen += len(idx)
        model.eval()
        with torch.no_grad():
            turn, resp, _ = model(Xv_t)
            turn_logits = masked_logits(turn, Mv_t[:, :109])
            resp_logits = masked_logits(resp, Mv_t[:, 109:])
            turn_sel = Av_t <= 108
            resp_sel = ~turn_sel
            t_top1 = (turn_logits[turn_sel].argmax(1) == Av_t[turn_sel]).float().mean().item() if turn_sel.any() else 0.0
            r_top1 = (resp_logits[resp_sel].argmax(1) == (Av_t[resp_sel] - 109)).float().mean().item() if resp_sel.any() else 0.0
            all_logits = torch.cat([turn, resp], 1)
            all_logits = masked_logits(all_logits, Mv_t)
            top1 = (all_logits.argmax(1) == Av_t).float().mean().item()
            top5 = (all_logits.topk(min(5, 113), 1).indices == Av_t[:, None]).any(1).float().mean().item()
        metrics = {"epoch": epoch, "train_loss": total / max(1, seen), "top1": top1,
                   "top5": top5, "turn_top1": t_top1, "resp_top1": r_top1}
        history.append(metrics)
        print(json.dumps(metrics, ensure_ascii=False), flush=True)
        if best is None or top1 > best["top1"]:
            best = metrics
            best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}
    if best_state is not None:
        model.load_state_dict(best_state)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out / "oracle_dual.pt")
    weights = {k: v.detach().cpu().tolist() for k, v in model.state_dict().items()}
    (out / "oracle_dual_weights.json").write_text(json.dumps(weights, ensure_ascii=False), encoding="utf-8")
    (out / "metadata.json").write_text(json.dumps({
        "feature_dim": int(Xtr.shape[1]), "hidden": args.hidden, "train_rows": int(len(A)),
        "val_rows": int(len(Av)), "best": best, "history": history,
        "architecture": f"{Xtr.shape[1]}->{args.hidden}->{args.hidden}->[109,4]",
        "feature_version": 2 if Xtr.shape[1] == 584 else (3 if Xtr.shape[1] == 811 else 1),
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print("saved", out, best)


if __name__ == "__main__":
    main()
