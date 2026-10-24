# 1.5.3 发布与部署记录

版本：`1.5.3`  
基线：`1.4.13-boot1`  
Android versionCode：`34`  
构建日期：2026-10-24

## 本版内容

- 个人本局分改为有符号口径：叫牌为正，未叫牌为负；
- 叫牌个人分 =（翻鸡 + 幺鸡八筒 + 杠 + 牌型 + 放炮 + 自摸）× 倍率；
- 未叫牌个人分 = -（翻鸡 + 幺鸡八筒 + 杠 + 牌型 + 放炮 + 自摸）；
- 两两付款继续按叫牌/未叫牌收付，账本保持零和；
- 2026-10-24 10:32 快照回归：个人分 [0,-8,0,10]，净分 [-10,-18,-10,38]。

## 测试

```text
run_suites.py：70 / 70
scoring_pairwise：28,081 项通过
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,770,762 字节
SHA-256：46f315f300e6744ba7420aa2aa6d3b2d11bb942ca41daaf5a34584bc17cf1182
versionName：1.5.3
versionCode：34
v2 签名验证通过
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,334,528 字节
SHA-256：803ec1098490f981524aa00ccc099c2bf5b3242ccf305cfb0af5bc56c1c5e557
文件版本：1.5.3.0
产品版本：1.5.3.0
```

## 热补丁

```text
anshun-mahjong-android-1.5.3.pck
anshun-mahjong-windows-1.5.3.pck
大小：276,424 字节
SHA-256：32ab4162014acc9eb7bad6812d1c874743607b6adb595dbfbbb0f4d0efd79880
基线：1.4.18
```

完整 PCK：

```text
anshun-mahjong-full-1.5.3.pck
11,043,504 字节
SHA-256：563ae4286e4bca58fbc7ada4ac47c413c99d569e28f244681ee39437e93d4aee
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.3
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-e483db9
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```n
