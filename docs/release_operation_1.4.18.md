# 1.4.18 发布与服务器部署记录

记录时间：2026-10-23  
发布版本：`1.4.18`  
基线：`1.4.13-boot1`  
Android versionCode：`29`

## 1. 发布内容

本轮发布包含第二轮代码审查的修复，以及新增的规则、UI、性能、联机、AI 和 Python 安全测试。

主要修复：

- 联机大厅空座导致整局卡死；
- 返回大厅投票取消后仍自动同意；
- AI 选择刚碰的禁打牌；
- Windows 更新失败日志不可见；
- 恢复前台误挂出牌按钮；
- GME 鉴权失败后每状态帧重试；
- room_directory 重启后活房间不可见、端口分配失败；
- 发布脚本远端路径注入和清单哈希校验；
- 语音座位抖动缓冲序号回退；
- 换座后台计时、回放保存、状态请求限流、empty peer 大厅操作等健壮性问题。

## 2. 测试

本地完整 headless 回归：

```text
69 / 69 通过
```

新增测试：

```text
rules_priority_edges.gd
ui_regression.gd
performance_budget.gd
network_security.gd
ai_safety.gd
lobby_safety.gd
test_publish_self_hosted.py
```

服务端 Python：

```text
14 项 unittest 全通过
```

CI 发布构建同时通过：

```text
Run core tests                              success
Run real network and reconnect regression   success
Run update hot-patch and proxy regression   success
```

## 3. GitHub Release

标签：

```text
V1.4.18
```

构建运行：

```text
Build release 39954299944 success
```

Android：

```text
文件：anshun-mahjong.apk
大小：94,750,333 字节
SHA-256：e032e698a393ccf86f50d86e174ec3a4b13832b04dadb7c608997940451b5ee7
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,299,728 字节
SHA-256：71eae44f916d0d28646cae8649190e2a2076b9694e13a4cf8fbeeef512d87c8e
```

## 4. 在线更新源

```text
https://mj.dongxiu.fun/updates/anshun-mahjong.apk
https://mj.dongxiu.fun/updates/anshun-mahjong-windows-x64.exe
https://mj.dongxiu.fun/updates/update-manifest.json
```

清单版本：

```text
1.4.18
```

本次没有生成热补丁，`patches` 为空。

## 5. 服务端

镜像构建：

```text
Build online server image 39956267476 success
ghcr.io/dongxiujiang/anshun-mahjong:sha-1ddac5c
```

部署后健康检查：

```json
{"ok": true, "rooms": 0, "max_rooms": 16, "version": "1", "app_version": "1.4.18", "build": "1ddac5c"}
```

## 6. 已知边界

- 自建更新清单仍未做独立签名；当前依赖 HTTPS 和清单内哈希。
- 大文件 SHA-256 校验仍在主线程。
- AI 未叫牌付款方成本模型仍是近似值。
- AI 教打关闭 MCTS 以避免卡顿，但仍同步执行价值模型。
