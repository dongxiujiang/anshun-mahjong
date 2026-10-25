# 1.5.1 发布与部署记录

版本：`1.5.1`  
基线：`1.4.13-boot1`  
Android versionCode：`32`  
构建日期：2026-10-24

## 本版内容

- 烧鸡只把自己的鸡分归 0：自己的出牌鸡、碰中鸡、杠中鸡、翻鸡和杠收入不计；仍赔付赢家的出牌鸡、碰中鸡、杠中鸡、杠分和放炮分；
- 暗杠牌面对自己立即可见，其他玩家保持反扣并按原规则延迟公开；
- 报听后手牌区域显示整圈金色边框，并锁定非摸牌手牌；
- 退出联机房间时，若已无在线真人，房间服务立即销毁；
- 结算阶段四家手牌全部翻开；
- 碰杠区左右摆放逻辑暂不改动，等待明确的目标布局。

## 测试

```text
run_suites.py：70 / 70
run_network.py --section all：通过
run_reconnect.py：通过
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,770,798 字节
SHA-256：bed7a08d3aa9989b0eb86875d9a56891b7cb3ada0f864b02353011125115dc06
versionName：1.5.1
versionCode：32
v2 签名验证通过
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,334,512 字节
SHA-256：475a3cec28c4ceefa94e6c4675583eb6efc09880bbd4272b2f6585e280579a9a
文件版本：1.5.1.0
产品版本：1.5.1.0
```

## 热补丁

```text
anshun-mahjong-android-1.5.1.pck
anshun-mahjong-windows-1.5.1.pck
大小：276,408 字节
SHA-256：7e3d1a177da784a7d74f7ce2e9d8adde58ceb1eb22c625dd240cff4beb9f1ddd
基线：1.4.18
```

完整 PCK：

```text
anshun-mahjong-full-1.5.1.pck
11,043,488 字节
SHA-256：e304097e3e0b94a5e5e43063f55ee3daba075bd260d0a5449e819569f318989a
```

## 更新清单兼容性

1.4.19 APK 内置的 `UpdateManager.verify_manifest_payload` 已用其原公钥验证 1.5.1 清单，签名通过。

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.1
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-80334bd
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```

