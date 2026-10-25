# 1.5.0 发布与部署记录

版本：`1.5.0`  
基线：`1.4.13-boot1`  
Android versionCode：`31`  
构建日期：2026-10-24

## 本版内容

- 结算阶段四家手牌全部翻开显示牌面，包括胡牌、普通流局、四家叫牌流局；
- 结算前仍保持对手手牌隐藏；
- 包牌计入双方碰中鸡；
- 翻鸡普通牌不计入包牌，幺鸡/八筒保留金鸡加倍；
- 自带暗杠/加杠的小牌放炮加 4 分；
- 断线重连凭证跨局保留 30 分钟；
- 自建更新清单 RSA 签名。

## 测试

```text
run_suites.py：70 / 70
settlement_animation_flow：66,145 项断言通过
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,768,430 字节
SHA-256：c122297f23bafbc3da5a026da2b53397a96960db4444757fcb5c5e1fe7a60a5f
versionName：1.5.0
versionCode：31
v2 签名验证通过
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,332,144 字节
SHA-256：2b665114f68d8653d9f9d189e7712348fc8edd9bf6552e4fce65dd94f8c6c183
文件版本：1.5.0.0
产品版本：1.5.0.0
```

## 热补丁

```text
anshun-mahjong-android-1.5.0.pck
anshun-mahjong-windows-1.5.0.pck
大小：248,340 字节
SHA-256：9da2e2aaff0c0ef055ef5e2bf1761ad1e86ce1621c18468cfd5d5b808c612c5e
基线：1.4.18
```

完整 PCK：

```text
anshun-mahjong-full-1.5.0.pck
11,041,120 字节
SHA-256：9bdc0379306dae1f2e14a25a55ab4e0550d55d11ae5893b4fd2eb24bad361104
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.0
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-0f019aa
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```

