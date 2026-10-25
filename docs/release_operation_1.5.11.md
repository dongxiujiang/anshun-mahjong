# 1.5.11 发布与部署记录

版本：`1.5.11`  
Android versionCode：`42`  
构建日期：2026-10-25

## 本版内容

- Android 在安全区内铺满牌桌，消除左右黑边；
- 报听/可报听时，合法出牌黄色高亮，其他手牌保持原样；
- 报听后手牌锁定，只用金色边框提示，不再用绿色填充遮挡牌面；
- 报听金边随权威 `ready` 状态同步到其他玩家；
- 碰杠/鸡牌始终从手牌左边缘向左排列，兜底右缘也不越过手牌；
- 兜底优先向上/向左让位，不主动压住自己手牌、摸牌位和其他家手牌；
- 报听自摸有牌型：牌型分 + 20 + 鸡，只计算一个自摸 4；
- 杀报 24：报听者放炮或他人自摸时，仅该报听者额外支付 24。

## 测试

```text
run_suites.py：70 / 70
rules_spec_v2：通过
scoring_audit：83,040 项通过
settlement_animation_flow：通过
settlement_card：3,789 项通过
```

## 产物

```text
APK 94,792,122 字节
SHA-256 d88978a88f2d7630dfc2675151cc57ea18f0a8e13b14e08fe5d5fe07abad5690

EXE 120,354,536 字节
SHA-256 89dbfc8544973791ea2743eb1dba992d5f023ea8fe7f9fc022768bb5d46624f7

Android 热补丁 222,772 字节
SHA-256 c806e049319659873f2abbbd2ec6a05f62c1a6ddc7fe2adbeb5318ee48ef2af6

Windows 热补丁 222,772 字节
SHA-256 c806e049319659873f2abbbd2ec6a05f62c1a6ddc7fe2adbeb5318ee48ef2af6
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.11
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-acfaaeb
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.9 / 1.4.13-boot1
```
