# 1.5.5 发布与部署记录

版本：`1.5.5`  
基线：`1.4.13-boot1`  
Android versionCode：`36`  
构建日期：2026-10-24

## 本版内容

- 未叫牌杠组的个人分只扣一次：杠基础 + 杠中鸡 + 翻鸡；
- 2026-10-24 12:17 快照：
  - 0号加杠幺鸡，翻牌九条，金鸡16 + 普通八筒2 + 加杠4 = 个人分 -22；
  - 不再把杠中鸡按三家重复累计成 -48；
  - 个人分 [ -22, 5, 8, 2 ]；
- 未叫牌杠主不收自己的杠基础分，也不再反向支付；
- 两两付款仍按叫牌/未叫牌收付。

## 测试

```text
run_suites.py：70 / 70
scoring_pairwise：28,084 项通过
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,769,966 字节
SHA-256：48c967ce8b1fbb5df3b8b7782bb5c18bdb8756f4943ec564eb625dca436d59c6
versionName：1.5.5
versionCode：36
v2 签名验证通过
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,333,712 字节
SHA-256：e1cab673361e632e58f33e745ced7881a0a2ee212ac084acae156d462f0cc2e8
文件版本：1.5.5.0
产品版本：1.5.5.0
```

## 热补丁

```text
anshun-mahjong-android-1.5.5.pck
anshun-mahjong-windows-1.5.5.pck
大小：275,608 字节
SHA-256：6465a9b1753cb8d7c97e7c7a062f76aead8dd2bd909a6642671fbcd26b4caca0
基线：1.4.18
```

完整 PCK：

```text
anshun-mahjong-full-1.5.5.pck
11,042,688 字节
SHA-256：f3f89c499e796e65f8de56d2d57641cb4b9e9a0873ce4725bd3df36edace348a
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.5
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-4bfce18
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```n
