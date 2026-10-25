# 1.5.13 发布与部署记录

版本：`1.5.13`  
Android versionCode：`44`  
构建日期：2026-10-25

## 本版内容

- 碰杠/幺鸡找位时增加组间聚合权重，后一组优先贴住本家上一组；
- 避免两组牌被分别放到桌面两个远处空位；
- 保持组与组之间固定间距，仍优先手牌左侧/上方；
- 继续避开四家手牌、摸牌区、弃牌区、中心与操作控件。

## 测试

```text
run_suites.py：70 / 70
smoke_table_layout：通过
```

## 产物

```text
APK 94,794,050 字节
SHA-256 ad527ff67df441187c429876d5cc57b733fd8704756b1a6e6b3ca16f8703c846

EXE 120,356,504 字节
SHA-256 8070278e9889b4beb5ede5a4faca65ce44ad3de69299ee759e97b33011945625

Android/Windows 热补丁 243,868 字节
SHA-256 074dd0d808bfa8f99d5f1a0ca9e807716303f379980aad0ff43a3f0e011bd6c9
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.13
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-4c93d32
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.9 / 1.4.13-boot1
```
