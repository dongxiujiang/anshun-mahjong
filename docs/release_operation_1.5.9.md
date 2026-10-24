# 1.5.9 发布与部署记录

版本：`1.5.9`  
基线：`1.4.13-boot1`  
Android versionCode：`40`  
构建日期：2026-10-24

## 本版内容

- 结算页恢复“返回座位”和“准备下一局”两个按钮；
- 返回座位使用房间投票，所有在线真人同意后返回大厅/座位选择；
- 按钮直接显示真人返回比例，如“返回座位 0/1”，不额外加 UI；`n- 返回座位与准备下一局按钮改为同宽同高 250×126，HBox 等距排布；`n- 手牌冻结期间，碰杠/鸡牌锚点改用打牌前手牌左边界，刷新后切回新锚点；
- 退出房间界面的“返回座位”移除，取消按钮改为“继续游戏”；
- 退出房间确认后直接退出，不再混入返回座位逻辑。

## 测试

```text
run_suites.py：70 / 70
settlement_animation_flow：66,445 项通过
settlement_card：3,789 项通过`nscoring_pairwise：28,097 项通过
```


## 产物

```text
APK 94,773,462 字节
SHA-256 051bd3a78280dfa3afb6ad591f9016633db2f42227046e7c9e1986945085f788

EXE 120,337,264 字节
SHA-256 73780f7918a8ad788c3d62c0dd1f2362fe5030388ed112827e3a50c205f4b2b8

PCK 303,024 字节
SHA-256 7fe4928ee4e50f65773ce0d7524a0af163ed32059c53d0d1ef9481d39dc01113

完整PCK 11,046,240 字节
SHA-256 ee1eeb07f9e534b97b4ea7495c2696729266860e253b8ac88c760996183b4f56
```n

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.9
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-4d98dde
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```n
