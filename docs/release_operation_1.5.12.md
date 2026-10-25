# 1.5.12 发布与部署记录

版本：`1.5.12`  
Android versionCode：`43`  
构建日期：2026-10-25

## 本版内容

- 点击「报听」后，才黄色高亮可报听的出牌；未点击不提前提示；
- 选中可报听牌并出牌后，立即锁定手牌并显示金色边框；
- 报听状态立即同步，不再等下一次自己摸牌才出现金边；
- 报听后自动摸打，摸到并自动打出的牌不再做黄色高亮；
- 碰杠/幺鸡优先放在自己手牌左侧或上方，选位按离自己手牌最近排序；
- 兜底位置必须完整位于牌桌内，不再飘到桌面外或其他玩家区域；
- 碰杠/幺鸡避开四家手牌、摸牌区、弃牌区、牌桌中心和操作控件；
- 上家/下家的幺鸡按各自座位方向并排，侧边座位在底家屏幕上显示为竖排。

## 测试

```text
run_suites.py：70 / 70
smoke_table_layout：通过
table_interaction：16 项通过
settlement_animation_flow：通过
```

## 产物

```text
APK 94,793,826 字节
SHA-256 9219adc2cae54e1abc4e00e5351774589fa7bf8d097a29cf1cfaa3907b220589

EXE 120,356,344 字节
SHA-256 366f3f38e10652c89a31b4c40305b504c6b4abd1916797f2a79c8d827d73d73e

Android/Windows 热补丁 243,708 字节
SHA-256 f6d97f3b97b7e80a7f0db910f2fc1b1c09d703f938477c877a426cdd857a8871
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.12
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-2ce768d
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.9 / 1.4.13-boot1
```
