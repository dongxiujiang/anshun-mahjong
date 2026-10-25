# 1.5.2 发布与部署记录

版本：`1.5.2`  
基线：`1.4.13-boot1`  
Android versionCode：`33`  
构建日期：2026-10-24

## 本版内容

- 报听金色边框只包住手牌，不再包含摸牌位；
- 联机模式下其他玩家也能看到报听玩家的金色手牌边框；
- 手牌锁定和自动摸打保持原逻辑。

## 测试

```text
run_suites.py：70 / 70
smoke_table_layout：通过
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,770,746 字节
SHA-256：5adea1cf1c4cbd6a0e764b905775a9102a6171adfe5995631b96b051f50fc960
versionName：1.5.2
versionCode：33
v2 签名验证通过
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,334,528 字节
SHA-256：67fe9f81b997c70b51c3a8e65cc73fba808e7bf56c2db58e955226a40e139767
文件版本：1.5.2.0
产品版本：1.5.2.0
```

## 热补丁

```text
anshun-mahjong-android-1.5.2.pck
anshun-mahjong-windows-1.5.2.pck
大小：276,424 字节
SHA-256：d8c729d82dcf4290df2607454a6c130f33921613995132250e6e72026958c89d
基线：1.4.18
```

完整 PCK：

```text
anshun-mahjong-full-1.5.2.pck
11,043,504 字节
SHA-256：f461550bec104033073b35215ce78b9a096067038687721d8effd3a9382d4a45
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.2
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-<待填>
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```
