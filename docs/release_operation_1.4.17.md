# 1.4.17 发布与服务器部署记录

记录时间：2026-10-22  
发布版本：`1.4.17`  
基线：`1.4.13-boot1`  
Android versionCode：`28`

## 1. 发布内容

- 杠优先于碰的独立响应阶段；
- 5 秒应用层心跳，15 秒无响应进入重连；
- RoundReplay 保存并恢复 RNG 状态；
- 建房不再持锁等待 Godot 启动；
- IPv6 建房限流按 `/64` 聚合；
- 增量状态补丁和 DEFLATE 压缩；
- 房间目录定时回收和日志轮转；
- 服务端签发重连 token，客户端加密保存，服务端状态只保存 SHA-256 摘要。

## 2. 源码

```text
main = bc2a397eb11f98f4103db4623e1341bed697f641
```

## 3. GitHub Release

```text
https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.4.17
```

构建运行：

```text
Build release 39786984969 success
```

核心测试、真实网络测试、断线重连测试均通过后再导出。

Android：

```text
文件：anshun-mahjong.apk
大小：94,745,509 字节
SHA-256：01cf90f3a15d0b246d449d96c26d7744bd2a2b42dd67af5759feb88364944e97
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,294,560 字节
SHA-256：7a7b813341f7917f472006b101eb9785be87e0996d2d2b41fa284be2582a8303
```

## 4. 在线更新源

```text
https://mj.dongxiu.fun/updates/anshun-mahjong.apk
https://mj.dongxiu.fun/updates/anshun-mahjong-windows-x64.exe
https://mj.dongxiu.fun/updates/update-manifest.json
```

更新清单版本：

```text
1.4.17
```

本次没有生成热补丁，`patches` 为空；1.4.16 用户需要完整更新。

## 5. 服务端

镜像构建：

```text
Build online server image 39791831658 success
ghcr.io/dongxiujiang/anshun-mahjong:sha-bc2a397
```

部署后的健康检查：

```json
{"ok": true, "rooms": 0, "max_rooms": 16, "version": "1", "app_version": "1.4.17", "build": "bc2a397"}
```

## 6. 测试结果

本地完整 headless 回归：

```text
63 / 63 通过
```

CI 发布构建：

```text
Run core tests                          success
Run real network and reconnect regression success
```

服务端 Python 安全测试：

```text
6 / 6 通过
GME auth checks passed
```

## 7. 已知边界

- 客户端加密密钥来自设备标识，不是硬件安全模块；目标是避免明文配置泄露，不等同于系统级密钥库；
- 新协议客户端使用增量状态，旧协议客户端自动回退完整快照；
- 发布顺序应为先部署服务端，再发布客户端；
- 未做 Android 真机长时间联机和弱网测试。
