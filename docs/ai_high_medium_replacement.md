# 高档替换中档记录

日期：2026-10-31  
状态：本地测试代码，未发布、未提交。

## 当前配置

```text
低档 = main 1.6.3 中档参数
中档 = 原高档 H29
高档 = 原高档 H29
B18 = 保留为独立档位 "b18"
```

中档和高档目前参数相同：

```text
MCTS = 16
defense_weight = 0.55
risk_inflation = 0.40
candidate_slack = 0
search_window = 0.35
ready_bonus = 2.5
safety_margin = 4.0
tenpai_weight = 65
distance_weight = -85
outs_weight = 2.30
keep_tenpai = true
keep_tenpai_slack = 2
candidate_limit = 8
```

## 5,000 局同锚点结果

焦点座位轮转，其余三家固定为原 B18 中档，同一 seed：

| AI | 胜率 | 放炮率 | 平均得分 |
|---|---:|---:|---:|
| 原高档 H29 | 24.68% | 4.00% | +0.8412 |
| 原 B18 中档 | 24.04% | 3.94% | +0.5960 |

差值：

```text
胜率：+0.64pp
放炮率：+0.06pp（略差）
平均得分：+0.245/局
```

分片 95% 置信区间：

```text
得分差：[-0.039, +0.527]
胜率差：[+0.0008, +0.012]
```

结论：方向上略优，但得分优势不显著，放炮率没有改善；不能称为明显强于 B18。

## 保留的 B18 参数

```text
MCTS = 16
defense_weight = 0.50
risk_inflation = 0.35
candidate_slack = 0
search_window = 0.20
ready_bonus = 1.5
safety_margin = 3.0
tenpai_weight = 40
distance_weight = -60
outs_weight = 1.80
keep_tenpai = true
keep_tenpai_slack = 2
candidate_limit = 8
```

代码中已保留：

```text
AiPlayer.set_difficulty("b18")
```

## 后期切回 B18 中档

方法一：把 `set_difficulty` 的 `"medium"` 块改成 `"b18"` 块的参数。

方法二：测试/离线代码直接实例化：

```gdscript
var ai := AiPlayer.new("AI", "b18")
```

如果要让 UI 的中档切回 B18，必须把 UI 传入的档位从 `"medium"` 映射到 `"b18"`，或把 `"medium"` 块恢复为 B18 参数。

## 测试与构建

```text
单元/场景测试：71/71 通过
本地 APK：待重新构建
GitHub：未提交
线上服务器：未更新
```
