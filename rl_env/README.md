# rl_env：Suphx 式训练阶段 0

这是独立分支上的环境封装，**不修改任何规则、结算或线上代码**。

## 2026-11 新增：Oracle → SL → PPO 管线

```text
RlEnv.step(state, action)          可见状态推进接口
RlEnv.oracle_advise(visible)       隐牌只读 Oracle 标签
oracle_collector.gd                Oracle 标签数据生成
prepare_oracle_dataset.py          JSONL → parquet/npz
train_oracle_sl.py                 113 类动作 SL
ppo_collector.gd                   策略座位 rollout + 启发/快照对手池
train_oracle_ppo.py                GAE + PPO clipped update
```

完整说明见 [`docs/oracle_training.md`](../docs/oracle_training.md)。

## 基础实现

```text
RlEnv.gd         同步 reset/step/observation/action_mask
ActionCodec.gd   固定动作编码，共 113 个动作
tests/           原生一致性、随机合法动作、观测隐私测试
```

动作编码：

```text
0..26      弃牌（27 种牌）
27..53     报听弃牌
54..80     暗杠/杠
81..107    加杠
108        自摸
109        碰
110        响应杠
111        响应胡
112        过
```

合法性始终来自：

```text
RoundState.allowed_actions()
```

不使用自写规则。

## 观测

`observation()` 只包含行动者可见信息：

```text
自己的手牌/摸牌/副露
四家弃牌和弃牌历史
四家已揭示副露
公开报听标记
分数、牌墙数量、庄家
翻鸡/鸡分公开信息
当前响应窗口
```

不包含对手暗牌或牌墙顺序。

`oracle_state()` 单独存在，只供训练 Oracle 使用，**禁止写入普通 replay 或 observation**。

## 测试

```powershell
C:\Users\xiu\Desktop\Godot_v4.7.2-stable_win64.exe `
  --headless --path . `
  --script rl_env/tests/phase0_tests.gd `
  --quit-after 1000
```

验收：

```text
同 seed/同动作序列：Env 与原生 RoundState 一致
随机合法动作：无非法提交、无死锁
observation：无对手暗牌/牌墙泄漏
```

## 下一步

1. 批量 env worker，测吞吐；
2. 生成 SL 数据；
3. 小规模 PPO；
4. 2000 局评估；
5. 通过后才考虑高档替换。

## 重要限制

- 当前是 GDScript env，适合正确性验证；
- 大规模 PPO 需要批量/C++ 或离线轨迹管线；
- 动作编码暂未包含“吃”，因为当前项目规则没有吃；
- 响应窗口由原生 `RoundState` 推进，不能假设固定回合顺序。

## 阶段1试点（已完成第一版，质量不达标）

已生成 5,000 局全动作轨迹、210,770 条决策：

```text
rl_env/sl_collector.gd
```

训练：

```powershell
python rl_env/train_sl.py
```

当前模型：

```text
观测 521 维（含合法动作 mask）
动作 113
策略 top1 ≈ 61.8%
top5 ≈ 92.1%
```

30 对评估：

```text
SL 焦点座：1 胜，-765 分
低档基准：5 胜，-76 分
```

结论：模型能完成对局，但行为克隆强度明显不足，不能作为高档。
需要更多数据、分动作头/PPO，而不是直接上线。

## 双头 SL 试点

为降低 113 类混训的类别干扰，新增：

```text
rl_env/train_sl_dual.py
```

结构：

```text
共享 trunk
→ turn 头 109 类
→ response 头 4 类（胡/碰/杠/过）
```

验证集：

```text
turn_top1 ≈ 62.2%
resp_top1 ≈ 71.3%
```

仍然不足；说明问题不只是头结构，数据量和行为策略质量也是瓶颈。

## 20,000 局 MCTS 老师数据

```text
20,000 局
849,041 条决策
老师：中档 + MCTS
```

双头 SL（抽 300,000 条训练）：

```text
turn_top1 ≈ 57.6%
resp_top1 ≈ 72.0%
```

30 对评估仍然失败：

```text
SL 焦点座：0 胜，-936 分
低档基准：5 胜，-76 分
```

结论：增加数据没有改变结构性问题。当前 SL 还不能作为 PPO 初始策略。

## SL 诊断

用同一环境验证老师强度（30 对）：

```text
中档焦点座：8 胜，169 分
低档基准：7 胜，46 分
```

老师确实更强，因此当前差距不是环境或基线问题，而是 SL 模型本身没有学好。

## DAgger

新增：

```text
rl_env/dagger_collector.gd
```

2,000 局 DAgger 轨迹、124,914 条偏离状态样本；与 20k 老师数据混合训练后：

```text
turn_top1 ≈ 53.8%
resp_top1 ≈ 69.8%
```

30 对评估：

```text
SL：1 胜，-709 分
低档：5 胜，-76 分
```

DAgger 没有把模型拉到可用水平，说明还需要改特征/动作表示，而不是继续堆同构数据。

## 只学出牌的对照

为了排除响应头的干扰，新增：

```text
rl_env/train_sl_turn.py
rl_env/SlTurnActor.gd
rl_env/eval_turn.gd
```

只训练 109 类出牌/报听/杠动作，响应交给中档规则 AI。

验证集：

```text
turn_top1 ≈ 56.1%
top5 ≈ 89.4%
```

30 对评估：

```text
SL 出牌 + 规则响应：3 胜，-662 分
低档：7 胜，46 分
```

比全动作模型好，但仍远低于规则低档。问题已经收敛到“出牌策略/特征表达”，不是响应头。

## 向听数对照

在只学出牌的模型上追加向听数（公开信息）：

```text
turn_top1 ≈ 56.5%
top5 ≈ 89.4%
```

30 对：

```text
3 胜，-637 分
低档：7 胜，46 分
```

向听数略微改善离线指标，但对局仍不合格。`ObservationCodec` 保持 521 维给双头模型，`encode_turn` 单独追加 1 维向听数，避免破坏已有双头模型。

## 手牌 CNN 对照

结构：

```text
手牌 3×9 → 2 层 CNN
其余 494 维公开特征 → dense
→ 109 类出牌头 + 价值头
```

验证集：

```text
turn_top1 ≈ 62.9%
top5 ≈ 95.2%
```

30 对：

```text
CNN 出牌 + 规则响应：5 胜，-330 分
低档：7 胜，46 分
```

CNN 比 MLP 好，但依然不能上线。说明牌型结构特征有帮助，但仍不够。

## 宽 CNN 结果

```text
conv 32 → 64
turn_top1 ≈ 67.25%
top5 ≈ 97.30%
```

30 对：8 胜 vs 低档 7 胜，但总分 -162 vs 46。
60 对：13 胜 vs 低档 14 胜，总分 -509 vs 88。

胜场已经接近，但得分仍明显落后。说明 CNN 能学会基本出牌，但还不会控制风险/收益。

## 后段安全回退对照

CNN 正常出牌，有对手报听或牌墙 <= N 时改用中档规则 AI。

```text
N=28：15 胜，-391 分
N=40：13 胜，-278 分
N=55（几乎全用老师）：16 胜，213 分
低档：14 胜，88 分
```

结论：CNN 只在早期出牌，后段规则 AI 接管时，总分会改善；但全场几乎交给规则中档时反而最好。说明当前 CNN 的边际贡献仍为负，不能靠简单回退冒充自学习成果。

## 搜索蒸馏

老师 MCTS 访问分布作为软标签，新增：

```text
rl_env/train_sl_soft.py
```

5,000 局搜索蒸馏数据、187,549 条 turn 样本：

```text
top1 ≈ 67.7%
```

60 对：

```text
软标签 CNN：9 胜，-366 分
低档：14 胜，88 分
```

比硬标签 CNN 的 -509 分略好，但胜场更低。仍未达到可用水平；未替换现有 CNN 权重。
