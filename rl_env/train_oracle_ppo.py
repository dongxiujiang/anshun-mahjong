"""PPO 小批量更新：消费 ppo_collector.gd 的策略轨迹。

真实 PPO 需要在线采样；当前脚本按轮次工作：
1. GDScript collector 用当前权重采样；
2. 本脚本做 GAE + PPO clipped update；
3. 导出权重给下一轮 collector。

奖励来自 RlEnv.step_state：终局实际分数 + 向听改善 shaping。
"""
from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F


class PolicyNet(nn.Module):
    def __init__(self, feature_dim: int = 521, action_dim: int = 113):
        super().__init__()
        self.trunk = nn.Sequential(
            nn.Linear(feature_dim, 256), nn.ReLU(),
            nn.Linear(256, 256), nn.ReLU(),
        )
        self.policy = nn.Linear(256, action_dim)
        self.value = nn.Linear(256, 1)

    def forward(self, x):
        h = self.trunk(x)
        return self.policy(h), self.value(h).squeeze(-1)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--input", action="append", required=True)
    p.add_argument("--init", default="")
    p.add_argument("--out", required=True)
    p.add_argument("--epochs", type=int, default=4)
    p.add_argument("--batch-size", type=int, default=128)
    p.add_argument("--clip", type=float, default=0.2)
    p.add_argument("--gamma", type=float, default=0.99)
    p.add_argument("--lam", type=float, default=0.95)
    p.add_argument("--lr", type=float, default=1e-4)
    p.add_argument("--seed", type=int, default=20261101)
    return p.parse_args()


def load_rows(patterns):
    rows = []
    for pattern in patterns:
        for name in sorted(glob.glob(pattern)):
            with open(name, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        rows.append(json.loads(line))
    return rows


def gae(rows, gamma: float, lam: float):
    """每个 game 内单独计算 return/advantage；行已经按 step 顺序。"""
    out = []
    groups = {}
    for r in rows:
        groups.setdefault(int(r["game"]), []).append(r)
    for game_rows in groups.values():
        game_rows.sort(key=lambda r: int(r["step"]))
        advantage = 0.0
        next_value = 0.0
        for r in reversed(game_rows):
            reward = float(r["reward"])
            value = float(r["value"])
            done = bool(r["done"])
            delta = reward + (0.0 if done else gamma * next_value) - value
            advantage = delta + (0.0 if done else gamma * lam * advantage)
            r = dict(r)
            r["return"] = advantage + value
            r["advantage"] = advantage
            out.append(r)
            next_value = value
    return out


def main():
    args = parse_args()
    torch.manual_seed(args.seed)
    rows = gae(load_rows(args.input), args.gamma, args.lam)
    if not rows:
        raise SystemExit("no PPO rows")
    X = torch.tensor([r["x"] for r in rows], dtype=torch.float32)
    M = torch.tensor([r["mask"] for r in rows], dtype=torch.bool)
    A = torch.tensor([r["action"] for r in rows], dtype=torch.long)
    old_logp = torch.tensor([r["logprob"] for r in rows], dtype=torch.float32)
    old_value = torch.tensor([r["value"] for r in rows], dtype=torch.float32)
    returns = torch.tensor([r["return"] for r in rows], dtype=torch.float32)
    adv = torch.tensor([r["advantage"] for r in rows], dtype=torch.float32)
    adv = (adv - adv.mean()) / (adv.std() + 1e-8)

    model = PolicyNet(int(X.shape[1]), int(M.shape[1]))
    if args.init:
        state = torch.load(args.init, map_location="cpu")
        model.load_state_dict(state)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr)
    n = len(rows)
    for epoch in range(args.epochs):
        order = torch.randperm(n)
        total = 0.0
        for start in range(0, n, args.batch_size):
            idx = order[start:start + args.batch_size]
            logits, values = model(X[idx])
            logits = logits.masked_fill(~M[idx], -1e9)
            logp = F.log_softmax(logits, dim=-1).gather(1, A[idx, None]).squeeze(1)
            ratio = torch.exp(logp - old_logp[idx])
            pg1 = ratio * adv[idx]
            pg2 = torch.clamp(ratio, 1 - args.clip, 1 + args.clip) * adv[idx]
            policy_loss = -torch.min(pg1, pg2).mean()
            value_loss = F.mse_loss(values, returns[idx])
            entropy = -(F.softmax(logits, -1) * F.log_softmax(logits, -1)).sum(-1).mean()
            loss = policy_loss + 0.5 * value_loss - 0.01 * entropy
            opt.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 0.5)
            opt.step()
            total += float(loss.item()) * len(idx)
        print(f"ppo epoch {epoch+1}: loss={total/n:.4f} rows={n}", flush=True)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), out / "ppo.pt")
    weights = {k: v.detach().cpu().tolist() for k, v in model.state_dict().items()}
    (out / "ppo_weights.json").write_text(json.dumps(weights, ensure_ascii=False), encoding="utf-8")
    metadata = {
        "rows": n,
        "games": len({int(r["game"]) for r in rows}),
        "architecture": f"{X.shape[1]}->256->256->{M.shape[1]}",
        "clip": args.clip,
        "gamma": args.gamma,
        "lam": args.lam,
        "mean_return": float(returns.mean().item()),
        "mean_value": float(old_value.mean().item()),
    }
    (out / "metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == "__main__":
    main()
