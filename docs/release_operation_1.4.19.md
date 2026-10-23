# 1.4.19 发布与服务器部署记录

版本：`1.4.19`  
基线：`1.4.13-boot1`  
Android versionCode：`30`  
构建日期：2026-10-24

## 本版内容

- 包牌：叫牌者碰中的幺鸡/八筒也计入双方包牌；
- 翻鸡普通牌不计入包牌，幺鸡/八筒保留金鸡加倍；
- 自带暗杠/加杠的玩家以普通小牌胡别人弃牌时，放炮者另付 4 分；
- 自建更新清单加入 RSA 签名校验；
- 断线重连凭证跨局保留 30 分钟，Android 长时间切后台后可返回原座位；
- 重连 UI 统一为游戏内面板；
- 修复 `Network.reset()` 空节点保护、发布门禁和房间空房回收。

## 本地测试

```text
run_suites.py：70 / 70
run_network.py --section all：通过
run_reconnect.py：通过
本地 build-release 检查：core_tests / network_tests / reconnect_tests 全绿
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,768,530 字节
SHA-256：4e800f559486361c36aebebb824105feed371cf92be1fcab1b4b52a632111e3b
versionName：1.4.19
versionCode：30
v2 签名验证通过
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,332,240 字节
SHA-256：b286e55dc87bb8e38794c9295d01ed05a1d4501fdce64b5a946bf5c7e3d9e2d0
文件版本：1.4.19.0
产品版本：1.4.19.0
```

## 热补丁

```text
anshun-mahjong-android-1.4.19.pck
anshun-mahjong-windows-1.4.19.pck
大小：229,368 字节
SHA-256：4918aa4083ccd26e8529b3663d420e68f24acf63b0fbb533fe2646886a6ee2ad
基线：1.4.18
```

清单：

```text
build/release-final-1.4.19/v1.4.19/update-manifest.json
build/release-final-1.4.19/v1.4.19/update-manifest-fallback.json
```

两份清单均通过内置公钥 RSA 校验。

## 待发布步骤

- 推送 GitHub；
- 创建 V1.4.19 Release 并上传四个文件；
- 更新自建更新源；
- 部署服务端镜像并复验健康检查。
