# 在线房间服务器

在线模式使用真实的专用游戏服务器：Python 提供房间列表和创建接口，每个房间启动一个无界面 Godot 进程。四名玩家均作为客户端连接，服务器复用项目中的游戏规则、私有手牌同步、选座、换座、准备与发牌流程。无需房主开放家中路由器端口。

## 启动

准备 Python 3.10+、Godot 4.7.2 和完整工程（含牌面、音频和 `.godot` 导入缓存；首次部署先运行一次 `godot --headless --editor --path /srv/mahjong --quit`）。Linux 云主机使用对应版本的 Linux Godot 可执行文件。

```sh
python server/room_directory.py --godot /usr/local/bin/godot --project /srv/mahjong --public-host game.example.com
```

Windows 本机测试示例：

```powershell
python server/room_directory.py --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe" --project "C:/Users/xiu/Desktop/Mahjong-Godot" --public-host 127.0.0.1
```

`--public-host` 必须是玩家可访问的服务器域名/地址；本机测试才使用 `127.0.0.1`。默认 HTTP 监听 8080/TCP，游戏房间使用 7600～7631/UDP，云主机开放这些端口。可用 `--http-port`、`--first-port`、`--max-rooms`、`--bind` 调整。正式部署可以由 HTTPS 反向代理转发房间接口到 8080，UDP 房间端口仍需开放。

游戏中打开「联机房间 → 在线 → 服务器设置」，保存 `http://127.0.0.1:8080`（本机）或部署后的 `https://game.example.com`。其他设备测试时设置可访问的服务地址，无需逐个输入游戏房间 IP。

## 房间生命周期

- `POST /rooms` 创建同号唯一的房间，启动 Godot 游戏进程；创建成功才返回连接地址。
- 创建者收到一次性的 `owner_token`，首次进入时成为房主。公开房间列表不会包含这个令牌；房主进入前其他玩家不能占用房主位置。
- `GET /rooms` 返回房间号、名称、真人数量、等待/开局状态和内部连接地址。客户端默认每 5 秒刷新在线房间。
- 真人最多 4 人，空位由默认准备的人机补齐。服务器只有全体真人准备后才倒数发牌。
- 游戏过程中不接受新玩家。断线后人机代打；房主离开时将房主权限转给仍在房间中的真人。
- 无真人的房间在 60 秒后自动关闭。目录通过进程状态和定期状态文件移除已退出/不响应的房间。日志、临时状态在 `build/room-server/`。
- 这是无账号的基础房间服务；后期需要账号、权限或服务扩容时，可保持接口兼容并替换目录服务。

## HTTP 接口

创建：

```http
POST /rooms
Content-Type: application/json

{"number":"001234","name":"朋友麻将局"}
```

成功返回 201：

```json
{"room":{"number":"001234","name":"朋友麻将局","players":0,"started":false,"host":"game.example.com","port":7600,"owner_token":"一次性房主令牌"}}
```

搜索 `GET /rooms` 返回 200：

```json
{"rooms":[{"number":"001234","name":"朋友麻将局","players":2,"started":false,"host":"game.example.com","port":7600}]}
```

错误格式为 `{"error":"错误说明"}`；输入无效 400，同号已存在 409，房间数达到限制 503，游戏进程启动失败 500。房间号为 4～8 位 ASCII 数字字符串，保留前导零。

## 验证

```sh
python tests/run_network.py --godot /path/to/godot
```

测试会启动真实的独立游戏进程，验证局域网搜索、房间号校验、人机选座、真人交换同意/拒绝、取消准备、首局选庄、已开局拒绝加入、私有手牌同步及完整牌桌对局，再启动本机在线目录验证 HTTP 创建/搜索、重复号拒绝、云端选座准备发牌及房间清理。测试服务自动关闭，不覆盖用户保存的云服务器地址。
