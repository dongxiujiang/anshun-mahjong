# 1.5.4 发布与部署记录

版本：`1.5.4`  
基线：`1.4.13-boot1`  
Android versionCode：`35`  
构建日期：2026-10-24

## 本版内容

- 修正未叫牌杠主被反向收取杠基础分的问题；
- 未叫牌杠主不收自己的杠基础分，也不再向叫牌玩家支付该 4 分；
- 未叫牌仍要补自己的出牌鸡、碰中鸡、杠中鸡和荒牌基础分；
- 个人本局分保持有符号口径。

## 快照回归

2026-10-24 10:32 快照：

```text
个人分 [0, -4, 0, 10]
净分   [-10, -14, -10, 34]
```

其中 1 号未叫牌只承担自己的冲锋鸡 4 分，不再承担自己的明杠基础 4 分。

## 测试

```text
run_suites.py：70 / 70
scoring_pairwise：28,081 项通过
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,770,398 字节
SHA-256：88900e6dcad3cde3f8d16f54e8f178bf682c50ff0708d267545b3b3a0a816660
versionName：1.5.4
versionCode：35
v2 签名验证通过
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,334,128 字节
SHA-256：299fe51939b9e711c5a549e206590353069a0ed572d3987e476c4ca1179a32d1
文件版本：1.5.4.0
产品版本：1.5.4.0
```

## 热补丁

```text
anshun-mahjong-android-1.5.4.pck
anshun-mahjong-windows-1.5.4.pck
大小：276,024 字节
SHA-256：2ef5d0b8141456db213aeb15493055afe5876ae43c4fdd7c91d1b59f50029f11
基线：1.4.18
```

完整 PCK：

```text
anshun-mahjong-full-1.5.4.pck
11,043,104 字节
SHA-256：45eb235e733f31e65a6ec7cd4b40728180a7c4b66671f944085c376e77c61c10
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.4
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-ac3dcce
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```n
