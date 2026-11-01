# 高档 AI：Oracle 标签 → SL → PPO

当前实现是训练管线第一阶段，**没有替换线上 AI**。

## 1. 模拟器接口

文件：`rl_env/RlEnv.gd`

### step(state, action)

```gdscript
env.step(visible_state, action_code)
# 或
env.step_state(visible_state, action_code)
```

返回：

```text
ok
state       下一可见 observation
reward     终局实际分数 + 向听改善 shaping
done
action_mask
```

`visible_state` 只包含当前行动者可见信息；隐藏牌和牌墙不会进入 observation。

### oracle_advise(state_visible)

```gdscript
env.oracle_advise(visible_state)
```

返回：

```text
actions   当前合法动作 code
probs     每个动作概率
best      推荐动作
best_action
scores
```

实现：

- 内部可读完整牌墙和所有暗牌；
- 对每个合法动作先 clone 完整状态，再应用该动作；
- 使用完美信息向听/真实剩余进张数估值；
- **不提交原局动作，不改变原局状态**。

`oracle_advise` 只供训练打标签，线上/PPO 不允许调用。

## 2. Oracle 数据生成

```powershell
Godot_v4.7.2-stable_win64.exe --headless --path . `
  --script rl_env/oracle_collector.gd -- `
  --start=2000 --count=200 --level=medium `
  --out=res://build/oracle_data_200.jsonl
```

每局：

1. 随机选择 `oracle_seat`；
2. 四个座位都用启发 AI 演化对局；
3. 只有 `current_actor == oracle_seat` 时调用 Oracle 存标签；
4. Oracle 标签不参与执行；
5. 结束时写入最终分数、步数、鸡标记。

样本格式：

```text
x / mask / action / probs / value / game / oracle_seat / has_chicken
```

## 3. 转 parquet

```powershell
python rl_env/prepare_oracle_dataset.py `
  --input build/oracle_data_200.jsonl `
  --out build/ai_high/oracle_data200 --npz
```

输出：

```text
train.parquet / val.parquet
train.npz / val.npz
stats.json
```

按整局切分训练/验证，避免同局泄漏。

## 4. SL

```powershell
python rl_env/train_oracle_sl.py `
  --data build/ai_high/oracle_data200 `
  --out build/ai_high/oracle_sl `
  --epochs 20
```

结构：

```text
521 可见特征
→ 256 ReLU
→ 256 ReLU
→ 113 动作
```

113 动作沿用 `ActionCodec.gd`：

```text
0..26    弃牌
27..53   报听弃牌
54..80   暗杠
81..107  加杠
108      自摸
109      碰
110      杠响应
111      胡
112      过
```

导出：

```text
oracle_sl.pt
oracle_sl_weights.json
metadata.json
```

## 5. PPO rollout

```powershell
Godot_v4.7.2-stable_win64.exe --headless --path . `
  --script rl_env/ppo_collector.gd -- `
  --start=10000 --count=20 `
  --policy=res://build/ai_high/oracle_sl/oracle_sl_weights.json `
  --snapshots=res://build/ai_high/ppo_round1/ppo_weights.json `
  --out=res://build/ppo_rollout.jsonl
```

当前策略座位使用 SL/PPO 权重，其余位置混合三种启发风格：

```text
均衡
保守
激进
```

Oracle 接口在 PPO 阶段完全不调用。

## 6. PPO 更新

```powershell
python rl_env/train_oracle_ppo.py `
  --input build/ppo_rollout.jsonl `
  --init build/ai_high/oracle_sl/oracle_sl.pt `
  --out build/ai_high/ppo_round1 `
  --epochs 4
```

GAE：

```text
gamma = 0.99
lambda = 0.95
clip = 0.2
```

奖励：

```text
终局：安顺捉鸡实际分差
      包含基础分、冲锋鸡/责任鸡、杠分、点炮惩罚
中途：向听下降 × 0.1
```

导出 `ppo.pt`、`ppo_weights.json`，下一轮 collector 用 `--policy` 指向它。

## 现状

已完整跑通小样本链路：

```text
Oracle 数据 20 局 / 172 条
parquet + npz 转换
SL 训练
SL 权重导出
PPO collector
PPO 小样本更新
```

验证：

```text
oracle_tests.gd       6/6
oracle_actor_test.gd  3/3
prepare_oracle_dataset.py  172 行 / 18 局
train_oracle_sl.py         可导出 oracle_sl.pt / weights
ppo_collector.gd           可生成策略座位转移
train_oracle_ppo.py        GAE + PPO 更新可运行
```

当前样本量太小，不能评估强度，也不能替换线上 AI。需要先扩大数据量、做整局验证，再谈模型上线。

## 限制

- Oracle 当前是完美信息启发估值，不是 MCTS 最优标签；
- PPO collector 目前是“一个策略座位 + 三个启发对手”，还不是完整对手池快照自博弈；
- 响应动作与出牌动作共用 113 类头；
- 还没有 500/2000 局强度评估。
