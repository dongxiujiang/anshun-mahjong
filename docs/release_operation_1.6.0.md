# 1.6.0 发布与部署记录

版本：`1.6.0`  
Android versionCode：`61`  
构建日期：2026-10-26

## 本版内容

- 所有人准备后立即开局/进入下一局，不再等待 3 秒/1 秒；
- 未报听玩家自己摸牌时，有自摸同时有暗杠/加杠会显示全部按钮；
- 未报听玩家响应弃牌同时可胡和碰/明杠时，显示胡、碰、明杠、过；报听仍只能自摸/胡；
- 流局时未叫牌玩家按叫牌玩家能形成的最高牌型分补付，无牌型付荒牌基础4，牌型分替代基础4；
- 干扣/大干扣按“赢家自己所有鸡分为0 + 所有叫牌玩家鸡分为0”判定；
- 「返回座位」和「准备下一局」独立计数；
- 移除结算「跳过动画」按钮，移除「即时」结算选项；
- 结算速度改为快速（0.8倍）/正常/慢速，「细看」改为「快速」；
- 保留 1.5.26 的测试模式、投票提案ID、开局速度首帧同步、热补丁基线修复。

## 测试

```text
run_suites.py：71 / 71
remote test_mode：测试房接受，正式房拒绝
remote proposal：proposal_id、错误ID拒绝、并发拒绝
draw pattern：清七对44/无牌型4/多叫牌分别补付
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.6.0
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```
