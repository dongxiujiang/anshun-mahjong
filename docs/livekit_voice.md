# 联机语音（自建 LiveKit）部署与操作手册

## 1. 架构

1.3.0 起，联机语音不再通过 ENet 转发原始 PCM，而是：

```text
Godot 客户端
  ├─ 游戏状态：ENet / 权威房间进程（不变）
  └─ 语音：WebRTC → 自建 LiveKit Server
                    ├─ Opus 编解码
                    ├─ WebRTC AEC / NS / AGC / 高通
                    ├─ 抖动缓冲、丢包隐藏、FEC
                    └─ TURN（对称 NAT 兜底）

房间进程
  └─ 只负责游戏状态，不再接触语音包

房间目录 Python 服务
  └─ /livekit-token 签发短时 JWT
```

语音令牌只在进入牌桌后签发，默认有效期 1 小时。LiveKit API Secret 只保存在服务器 `.env`，不会进入客户端。

## 2. 平台限制

| 平台 | 状态 |
|---|---|
| Android arm64 | 支持 |
| Windows x86_64 | 支持 |
| Linux x86_64 | 支持（桌面） |
| Android armeabi-v7a | 不支持 |
| iOS | 不支持 |
| 浏览器 | 未接入 |

Android 导出必须只勾选 **arm64-v8a**。1.3.0 的客户端是完整 APK，不能通过 100KB 热补丁升级，因为需要携带 LiveKit 原生库。

## 3. 服务器要求

- 已有 `mj.dongxiu.fun` 的 HTTPS 证书；
- Docker / Docker Compose；
- 公网开放：
  - TCP 443（Nginx）
  - TCP 7881（LiveKit RTC TCP fallback）
  - UDP 7882（LiveKit RTC UDP）
  - UDP 3478（TURN）
  - TCP/UDP 5349（TURN TLS）
  - UDP 30000-30050（TURN relay）
- 服务器安全组也要放行以上端口，不能只开系统防火墙。

## 4. 服务器配置

在服务器项目目录（当前生产为 `/home/admin/mahjong`）的 `.env` 加入：

```dotenv
LIVEKIT_URL=wss://mj.dongxiu.fun/livekit
LIVEKIT_API_KEY=APIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
LIVEKIT_API_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
LIVEKIT_KEYS=APIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
LIVEKIT_TOKEN_TTL=3600
```

`LIVEKIT_API_KEY`/`LIVEKIT_API_SECRET` 供 Python 签发 JWT；`LIVEKIT_KEYS` 供 LiveKit Server 校验同一个密钥。两处必须一致。

`server/livekit.yaml` 关键配置：

```yaml
port: 7880
rtc:
  tcp_port: 7881
  udp_port: 7882
  use_external_ip: true
  node_ip: <公网 IP>
turn:
  enabled: true
  domain: mj.dongxiu.fun
  cert_file: /etc/letsencrypt/live/mj.dongxiu.fun/fullchain.pem
  key_file: /etc/letsencrypt/live/mj.dongxiu.fun/privkey.pem
  udp_port: 3478
  tls_port: 5349
  relay_range_start: 30000
  relay_range_end: 30050
```

启动：

```bash
docker compose -f compose.prod.yaml up -d livekit
docker logs --tail 50 mahjong-online-livekit-1
```

看到以下日志即正常：

```text
starting LiveKit server ... portHttp 7880
Starting TURN server ... portUDP 3478
```

## 5. Nginx

站点 `mj.dongxiu.fun` 的 `server` 块中，在 `location /` 之前加入：

```nginx
include /etc/nginx/snippets/mahjong-livekit.conf;
```

对应文件见仓库 `docker/nginx-livekit.conf`。它把：

```text
wss://mj.dongxiu.fun/livekit/rtc
```

转发到：

```text
http://127.0.0.1:7880/rtc
```

修改后：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

验证：

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://mj.dongxiu.fun/livekit/
# 200
```

## 6. 令牌接口

```http
GET /livekit-token?room=123456&identity=seat1&name=玩家
```

成功：

```json
{"url":"wss://mj.dongxiu.fun/livekit","token":"eyJ...","room":"123456","identity":"seat1"}
```

失败：

- 503：服务器没有配置 LiveKit API Key/Secret；
- 400：房间号或 identity 无效；
- 404：房间尚未创建或已关闭。

identity 固定为 `seat0`～`seat3`，与游戏座位对应；昵称只用于显示。

## 7. 客户端操作

1. 更新到 1.3.0 完整 APK/EXE；
2. 进入联机牌桌并完成发牌；
3. 右上角点“麦克风 关”开启麦克风；
4. 首次 Android 会请求录音权限；
5. 其他真人昵称旁的喇叭按钮可单独静音该玩家；
6. 设置 → 声音 → 麦克风音量/他人语音音量继续有效。

自己不会听到自己的声音，这是正常的；需要另一台设备验证。

## 8. 构建

LiveKit 原生扩展需要 Godot 4.5+，项目使用 Godot 4.7.2。仓库内置的 `addons/godot-livekit` 必须带 APM（回声消除/降噪/AGC）。

构建工作流：`.github/workflows/build-livekit-addon.yml`

- 从 `NodotProject/godot-livekit` 的固定提交构建；
- Linux、Windows、Android arm64 三个平台；
- 下载 artifact 后合并到 `addons/godot-livekit`；
- 再执行完整 Android/Windows 导出。

完整 APK 构建：

```bash
godot --headless --path . --export-release "Android" build/android/anshun-mahjong-1.3.0.apk
```

## 9. 验证

```bash
python tests/test_livekit_token.py
godot --headless --path . --script res://tests/livekit_plugin.gd
godot --headless --path . --script res://tests/livekit_connect.gd
```

`livekit_connect.gd` 需要 `9999` 测试房间存在，仅用于部署联调，不进入自动测试套件。

## 10. 常见问题

### 能看到房间但没有声音

- 所有玩家是否都升级到 1.3.0；
- 麦克风按钮是否已开启；
- Android 是否授予录音权限；
- 服务器 7881/7882/3478/5349/30000-30050 是否放行；
- Nginx `/livekit/` 是否 200；
- `docker logs` 是否有 TURN 证书错误。

### 有回声

- 先戴耳机测试；
- 确认客户端加载了带 APM 的 LiveKit 扩展（`livekit_plugin.gd` 的 APM 断言）；
- 外放 + 麦克风仍可能有残余回声，这是物理环境问题。

### 只有部分玩家能连

- 检查运营商/公司网络是否阻断 UDP；
- 确认 TURN 3478/5349 与 relay 端口开放；
- LiveKit 日志会显示 candidate/TURN 错误。

### 旧版本客户端

1.2.x 使用 PCM 语音，和 1.3.0 的 LiveKit 不兼容。必须所有玩家升级到 1.3.0 后语音才能互通；游戏状态同步仍兼容。
