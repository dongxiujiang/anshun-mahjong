# 在线房间服务器

在线模式使用真实的专用游戏服务器：Python 提供房间列表和创建接口，每个房间启动一个无界面 Godot 进程。四名玩家均作为客户端连接，服务器复用项目中的游戏规则、私有手牌同步、选座、换座、准备与发牌流程。无需房主开放家中路由器端口。

> Docker 一键部署（推荐生产使用）：见 [docker.md](docker.md)。

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

## GME 语音鉴权

Android 1.4.0 起使用腾讯云 GME。服务器 `.env` 配置：

```dotenv
GME_APP_ID=1400802279
GME_APP_KEY=<GME 控制台鉴权密钥>
```

牌桌进入后请求：

```http
GET /gme-auth?room=001234&openid=0012341
X-Room-Token: <该座位当前 resume_token>
```

服务端只给**当前房间成员**签发：`openid` 必须是 `房间号+座位号`，`X-Room-Token` 必须匹配该座位当前成员凭证，否则返回 403。返回短时 AuthBuffer（base64），客户端用 AppID、OpenID、RoomID 和该 AuthBuffer 进入 GME 房间。AppKey 不得进入客户端。完整接入步骤见 [../docs/gme_voice.md](../docs/gme_voice.md)。

建房接口默认同一来源每分钟最多成功创建 3 个房间，可用 `MAX_CREATES_PER_MINUTE` 调整；超限返回 429。只有来自 `TRUSTED_PROXIES`（默认 `127.0.0.1/32,::1/128`）的请求才会读取 `X-Forwarded-For`，直连请求始终使用 TCP 对端地址，避免伪造来源绕过配额。生产环境应关闭后端 HTTP 端口的公网访问，只允许代理访问。

## 对局记录接口

设置页「提交本局记录」将完整对局提交到同一服务器。局中点击会登记，结束结算后才上传；结算后点击立即上传。单机由本机提交，局域网由房主提交，在线房间由权威房间进程提交。普通客户端不会收到隐藏牌墙，局域网房主需要能访问云端 HTTP 服务。未结束便退出的单机局、被关闭的未完成房间不作为完整样本提交。网络失败会提示重试，不显示虚假成功。

服务器 `.env` 配置：

```dotenv
RECORDS_LIMIT=100
RECORDS_API_KEY=<仅用于分析的长随机密钥>
```

默认全服务器共保留最近100局，可设置1～10000；重启目录服务后生效，降低上限时立即清理最旧记录。`build/room-server/round-records.sqlite3` 位于现有 `room_logs` 持久卷，重建容器和关闭房间不会删除它。请勿删除该持久卷。分析密钥只放服务器及分析工具，不写入客户端、源码或下载链接；不设置密钥时读取接口返回503。

| 接口 | 用途 |
|---|---|
| `POST /round-records` | JSON `{ "mode": "single或lan或online", "record": 完整RoundReplay对象 }`，首次保存201、同内容重复提交200 |
| `GET /round-records?limit=10` | `Authorization: Bearer <RECORDS_API_KEY>`；按首次提交时间倒序返回最多10局完整样本 |

读取响应包含 `count`（本次数量）、`total`（现存数量）、`capacity`（保存上限）及 `records` 数组。每项包含 `id`、服务器UTC `submitted_at`、`mode` 和可直接交给 `RoundReplay.replay()` 的 `record`。`limit` 默认10，允许1～10000，超过现存数量或保存上限时返回现有记录。重复提交不占第二个名额、不改变原来的时间顺序；同一编号内容不同返回409，保留原记录。

```sh
curl --fail --show-error \
  -H "Authorization: Bearer $RECORDS_API_KEY" \
  'https://mj.dongxiu.fun/round-records?limit=20' \
  -o latest-rounds.json
```

记录含版本、初始四家手牌、完整108张牌墙与位置、骰子和发牌事件、摸打碰杠/报听的操作、结算事件、最终四家状态及逐项收付。`actions` 供规则重放，`events` 供流程检查；没有屏幕录像、麦克风录音或系统日志。步前完整状态指纹仍默认关闭，避免恢复逐操作序列化造成卡顿；最终指纹保留。分析时应使用记录版本的规则代码。

单条请求不超过2MiB，每个来源每分钟最多60次提交，JSON格式或未结算记录返回400，读取未鉴权返回401。HTTP层检查结构和分数守恒，不把客户端上报当成经过服务端规则认证的成绩；分析前仍应重放校验。Nginx反代此路径时需允许 `client_max_body_size 2m`（Caddy默认无需调整），并使用HTTPS。专用房间通过目录注入的 `MAHJONG_RECORDS_URL` 访问本机服务，不走玩家配置的地址。

## 验证命令

```sh
python tests/run_network.py --godot /path/to/godot
python tests/run_record_submission.py --godot /path/to/godot
python -m unittest discover -s tests -p 'test_round_records.py'
```

测试会启动真实的独立游戏进程，验证局域网搜索、房间号校验、人机选座、真人交换同意/拒绝、取消准备、首局选庄、已开局拒绝加入、私有手牌同步及完整牌桌对局，再启动本机在线目录验证 HTTP 创建/搜索、重复号拒绝、云端选座准备发牌及房间清理。测试服务自动关闭，不覆盖用户保存的云服务器地址。
