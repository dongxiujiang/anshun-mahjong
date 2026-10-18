# 服务端部署、客户端打包与两级热更新

本文覆盖：

- 服务端从零部署（Docker + 宿主机 Nginx 模式，不使用 Caddy）
- 服务端镜像更新
- 客户端完整包（大版本/首次迁移）
- 客户端热补丁（小版本）
- 自建 HTTPS 更新源的发布与验证

当前生产示例：

```text
域名：mj.dongxiu.fun
更新目录：/var/www/mahjong/updates
app 镜像：ghcr.io/dongxiujiang/anshun-mahjong:<tag>
```

## 1. 运行架构

```text
公网 TCP 80/443 → 宿主机 Nginx → 127.0.0.1:18080 → app 容器
公网 UDP 7600-7631 → app 容器（每房一个 Godot 进程）
公网 HTTPS /updates/ → Nginx 静态目录 → 清单 + PCK/APK
```

- `app` 容器运行 Python 房间目录和 Godot 房间进程。
- Nginx 负责 HTTPS、`/` 反代和 `/updates/` 静态文件。
- `caddy` 容器保留在 compose 文件中，但 Nginx 模式不启动它。
- 客户端只从自建 `/updates/` 检查热更新，不再访问 GitHub API。

## 2. 版本与基线规则

当前基线：

```text
config/version = 1.0.0
updates/base_id = 1.0.0-boot1
baseline release tag = V1.0.0
Android version/code = 5
```

### 2.1 小版本热补丁

同一主版本内的脚本、UI、资源、音频、结算规则变化，使用累计 PCK 补丁：

- 不改 `updates/base_id`
- 不改安装基线目录
- 用 `prepare_hot_update.py patch` 相对 `1.0.0-boot1` 生成
- 例如 `1.1.10`、`1.1.11`

玩家从任意 1.0.x/1.1.x 版本都可以直接升到最新小版本。

### 2.2 大版本

引擎、原生插件、Android 权限、启动配置、Autoload、全局 `class_name`、导出格式等不兼容变化，需要新基线：

- 修改 `config/version`，例如 `2.0.0`
- 修改 `updates/base_id`，例如 `2.0.0-boot1`
- 保存新的基线目录，不能覆盖 `1.0.0-boot1`
- 发布 V2.0.0 完整包
- 旧 1.x PCK 不再适用于 2.x

**本次给 1.1.9 做过渡完整包，不需要改成 V2.0.0。** 继续沿用 `V1.0.0` / `1.0.0-boot1`，只把新完整 APK 作为一次安装桥梁。

### 2.3 服务端和客户端的关系

| 改动类型 | 服务端镜像 | 客户端完整包 | 客户端热补丁 |
|---|---|---|---|
| 只改结算 UI/说明 | 不需要 | 可选 | 需要 |
| 改权威计分/规则/房间逻辑 | **需要** | 可选 | 需要 |
| 改更新源/默认在线地址 | 不需要 | **需要一次** | 后续补丁 |
| 只改文档/README | 不需要 | 不需要 | 不需要 |

服务端是权威端；只更新客户端而不更新服务端，在线对局仍按旧规则结算。

## 3. 服务端从零部署（Nginx 模式）

### 3.1 前置条件

- Ubuntu 24.04 x86_64 云服务器
- 域名 A 记录指向服务器公网 IPv4
- 云安全组开放：
  - TCP `80`、`443`
  - UDP `7600-7631`
  - SSH 端口
- 不在公网开放 `8080`
- 如果域名使用 Cloudflare，对应记录必须是 **DNS only（灰云）**

### 3.2 安装 Docker

```sh
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker

docker --version
docker compose version
```

Docker Hub 是否可访问不影响本方案：Nginx 模式不使用 `caddy:2-alpine`，app 镜像来自 GHCR。

### 3.3 获取 app 镜像

GitHub Actions → **Build online server image** → **Run workflow**，或推送 `V1.0.*` 标签。

手动运行在 `main` 上通常得到：

```text
ghcr.io/dongxiujiang/anshun-mahjong:sha-<短提交>
```

私有包需要 PAT（`read:packages`）：

```sh
echo "$GHCR_TOKEN" | docker login ghcr.io -u dongxiujiang --password-stdin
docker pull ghcr.io/dongxiujiang/anshun-mahjong:sha-<短提交>
```

### 3.4 准备部署目录和文件

```sh
mkdir -p ~/mahjong/docker
cd ~/mahjong
```

优先从镜像里取部署文件，避免访问 GitHub raw：

```sh
docker create --name mahjong-bundle \
  ghcr.io/dongxiujiang/anshun-mahjong:sha-<短提交>

docker cp mahjong-bundle:/app/compose.prod.yaml ~/mahjong/
docker cp mahjong-bundle:/app/docker/Caddyfile ~/mahjong/docker/
docker cp mahjong-bundle:/app/deploy-image.sh ~/mahjong/
docker cp mahjong-bundle:/app/.env.example ~/mahjong/
docker rm mahjong-bundle
```

也可以从 Actions 的 `server-deploy-bundle` 产物下载这四个文件。

### 3.5 配置 `.env`

```sh
cd ~/mahjong
cp .env.example .env
nano .env
```

```dotenv
APP_IMAGE=ghcr.io/dongxiujiang/anshun-mahjong:sha-<短提交>
DOMAIN=mj.dongxiu.fun
PUBLIC_HOST=mj.dongxiu.fun
MAX_ROOMS=16
FIRST_PORT=7600
```

- `APP_IMAGE` 必须是实际镜像标签。
- `PUBLIC_HOST` 是目录返回给客户端的房间地址，通常同域名；如果客户端 ENet 域名解析异常，可改成公网 IP。
- `MAX_ROOMS`、`FIRST_PORT` 要和 `compose.prod.yaml` 的 UDP 范围和云安全组一致。

检查解析：

```sh
docker compose -f compose.prod.yaml config
```

### 3.6 只启动 app

Nginx 模式**不要启动 caddy**。确认 `compose.prod.yaml` 的 app 端口包含：

```yaml
- "127.0.0.1:18080:8080"
- "7600-7631:7600-7631/udp"
```

启动：

```sh
cd ~/mahjong
docker compose -f compose.prod.yaml up -d app --pull never
```

验证本机：

```sh
docker compose -f compose.prod.yaml ps
curl -fsS http://127.0.0.1:18080/healthz
```

返回：

```json
{"ok":true,"rooms":0,"max_rooms":16,"version":"1"}
```

不要执行 `docker compose up -d`，否则会启动 caddy 并和 Nginx 抢 80/443。

### 3.7 安装并配置 Nginx

```sh
sudo apt-get install -y nginx
sudo systemctl enable --now nginx
```

创建站点：

```sh
sudo tee /etc/nginx/sites-available/mj.dongxiu.fun >/dev/null <<'NGINX'
server {
    listen 80;
    server_name mj.dongxiu.fun;

    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

sudo ln -sf /etc/nginx/sites-available/mj.dongxiu.fun /etc/nginx/sites-enabled/mj.dongxiu.fun
sudo nginx -t
sudo systemctl reload nginx
```

验证反代：

```sh
curl -i -H 'Host: mj.dongxiu.fun' http://127.0.0.1/healthz
```

返回 200 后申请证书：

```sh
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d mj.dongxiu.fun
```

如果服务器已有 Nginx 和证书，**不要覆盖整份配置**；只在现有 `listen 443 ssl` 的 server 块里增加 `/updates/` include。

### 3.8 配置 /updates/ 静态目录

```sh
sudo mkdir -p /var/www/mahjong/updates
sudo chown admin:admin /var/www/mahjong/updates
sudo chmod 755 /var/www/mahjong/updates

sudo tee /etc/nginx/snippets/mahjong-updates.conf >/dev/null <<'NGINX'
location /updates/ {
    alias /var/www/mahjong/updates/;
    add_header Cache-Control "no-store";

    types {
        application/octet-stream pck;
        application/vnd.android.package-archive apk;
        application/json json;
    }
    default_type application/octet-stream;
}
NGINX
```

在现有 443 server 块中加：

```nginx
include /etc/nginx/snippets/mahjong-updates.conf;
```

```sh
sudo nginx -t
sudo systemctl reload nginx
```

验证 location 已加载：

```sh
sudo nginx -T | grep -n -A12 "location /updates/"
```

### 3.9 服务端验收

```sh
curl -fsS https://mj.dongxiu.fun/healthz
curl -fsS https://mj.dongxiu.fun/rooms
```

期望：

```json
{"ok":true,"rooms":0,"max_rooms":16,"version":"1"}
{"rooms":[]}
```

客户端服务器地址填：

```text
https://mj.dongxiu.fun
```

加入房间还需要 UDP `7600-7631` 已放行。

### 3.10 更新服务端镜像

只在服务端代码（计分、规则、房间逻辑等）变化时执行：

```sh
cd ~/mahjong

docker pull ghcr.io/dongxiujiang/anshun-mahjong:<新标签>
sed -i 's|^APP_IMAGE=.*|APP_IMAGE=ghcr.io/dongxiujiang/anshun-mahjong:<新标签>|' .env

docker compose -f compose.prod.yaml up -d app --pull never
curl -fsS https://mj.dongxiu.fun/healthz
```

Nginx、证书、UDP 配置都不需要动。

## 4. 客户端完整包

### 4.1 什么时候需要完整包

- 首次安装
- 1.1.9 等旧版迁移到自建更新源
- 大版本（新基线）
- 修改了引擎、权限、导出配置、Autoload 等不能热更新的内容

### 4.2 GitHub Actions 构建

```text
Actions → Build release → Run workflow
```

`full` 模式填写：

```text
release_kind = full
baseline_run_id = 留空
baseline_source = release
baseline_release_tag = V1.0.0
patch_version = 留空
publish_release = 不勾
release_notes = 可留空
```

`full` 模式不使用 `baseline_*` 和 `patch_version`，保留默认值即可。

构建产物在 `full-release-<run_id>` 中，包含：

- `anshun-mahjong.apk`
- `anshun-mahjong-windows-x64.exe`
- `build/releases/<version>/update-manifest.json`

### 4.3 1.1.9 过渡包

1.1.9 的更新器仍先访问 GitHub API，无法通过热更新切换到自建源，所以必须安装一次新的完整 APK。

这个完整 APK 必须包含：

```ini
[updates]
manifest_url=""
manifest_urls=[
"https://mj.dongxiu.fun/updates/update-manifest.json",
"https://mj.dongxiu.fun/updates/update-manifest-fallback.json"
]
```

同时必须：

- 包含新的结算规则/UI
- 使用正式签名
- Android `version/code` 不小于 1.1.9，最好递增

当前 `export_presets.cfg`：

```text
version/code = 5
version/name = 1.0.0
```

如果 1.1.9 的 versionCode 大于 5，先把 `version/code` 调大，提交并重新构建完整包；否则 Android 会拒绝覆盖安装。

本次**不需要**把基线改成 V2.0.0，继续沿用 `V1.0.0` / `1.0.0-boot1`。

### 4.4 安装完整 APK

把 APK 链接发给 1.1.9 用户安装。安装后：

- 更新器读取 `https://mj.dongxiu.fun/updates/update-manifest.json`
- 在线服务器地址仍是 `https://mj.dongxiu.fun`
- 后续小版本只下载 PCK

## 5. 客户端小版本热补丁

### 5.1 生成补丁

在本地仓库：

```powershell
python tools/update/prepare_hot_update.py patch `
  --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe" `
  --baseline build/update_baselines/1.0.0-boot1 `
  --version 1.1.10 `
  --notes "优化手机端热更新与结算显示"
```

输出：

```text
build/releases/v1.1.10/
  update-manifest.json
  anshun-mahjong-windows-1.1.10.pck
  anshun-mahjong-android-1.1.10.pck
```

补丁始终相对 `1.0.0-boot1` 累计生成，玩家可从 1.0.0 直接升到最新 1.1.x。

如果使用 GitHub Actions：

```text
Build release → patch
baseline_source = release
baseline_release_tag = V1.0.0
patch_version = 1.1.10
publish_release = 不勾
```

### 5.2 可选：把完整 APK 放进补丁目录

为了让新安装用户也能从 `/updates/anshun-mahjong.apk` 下载完整包，可以把完整 APK 复制到补丁目录：

```powershell
Copy-Item build/android/anshun-mahjong.apk `
  build/releases/v1.1.10/anshun-mahjong.apk
```

`publish_self_hosted.py` 会把 APK 一起上传，并让清单的 `installation_url` 指向它。

> 不要把 `full` 生成的 1.0.0 清单直接覆盖到 `/updates/update-manifest.json`。完整包只用于安装，最新清单必须来自补丁目录（例如 1.1.10），否则客户端会认为已是最新 1.0.0。

### 5.3 推送到服务器

```powershell
python tools/update/publish_self_hosted.py `
  --release build/releases/v1.1.10 `
  --domain mj.dongxiu.fun `
  --ssh admin@47.108.185.96 `
  --remote-dir /var/www/mahjong/updates
```

脚本会：

- 把清单里的下载地址改写成 `https://mj.dongxiu.fun/updates/<文件名>`
- 生成 `update-manifest.json` 和 `update-manifest-fallback.json`
- 先上传临时文件，再原子替换
- 先传资源，最后替换清单

不指定 `--ssh` 时只在本地生成 `build/self-hosted/<domain>/`，可手动上传。

先 dry-run：

```powershell
python tools/update/publish_self_hosted.py `
  --release build/releases/v1.1.10 `
  --domain mj.dongxiu.fun --dry-run
```

### 5.4 验证清单和资源

```sh
curl -fsS https://mj.dongxiu.fun/updates/update-manifest.json
curl -fsS https://mj.dongxiu.fun/updates/update-manifest-fallback.json
```

检查：

- `version` 是最新版本
- `patches.android.url` / `patches.windows.url` 都指向 `mj.dongxiu.fun`
- `sha256`、`size` 与本地文件一致

下载 PCK 校验：

```sh
curl -fsS -o /tmp/android.pck \
  https://mj.dongxiu.fun/updates/anshun-mahjong-android-1.1.10.pck
sha256sum /tmp/android.pck
```

## 6. 客户端热更新流程

1. 客户端启动或点「检查更新」
2. `UpdateManager` 读取 `manifest_urls` 主清单
3. 主清单失败，自动读取 `update-manifest-fallback.json`
4. 比较版本，下载对应 PCK
5. SHA-256 和大小校验
6. 退出房间/对局后重启应用
7. PatchBoot 挂载补丁；失败自动回退旧版

不会访问 GitHub API；自建清单和 PCK 都在 `mj.dongxiu.fun`。

## 7. 发布顺序检查表

每次发布按顺序：

### 服务端有改动

- [ ] 提交/推送代码
- [ ] CI 测试通过
- [ ] `Build online server image` 手动运行成功
- [ ] 服务器 `docker pull` 新标签
- [ ] `.env` 更新 `APP_IMAGE`
- [ ] `docker compose up -d app --pull never`
- [ ] `/healthz` 200
- [ ] 在线房间实测

### 客户端有改动

- [ ] 提交/推送代码
- [ ] 决定 full 还是 patch
- [ ] 生成完整 APK 或 PCK
- [ ] 校验 Android versionCode / 签名
- [ ] 推送到 `/updates/`
- [ ] 验证主清单和回退清单
- [ ] 1.1.9 用户安装完整 APK
- [ ] 游戏内检查更新/下载/重启
- [ ] 确认补丁生效且可回退

## 8. 回滚

### 客户端补丁

- 客户端设置里可恢复上一小版本
- 服务器保留上一份 PCK 和清单；重新发布旧清单即可让新客户端回退
- 不要删除当前和上一成功补丁

### 服务端镜像

```sh
cd ~/mahjong
sed -i 's|^APP_IMAGE=.*|APP_IMAGE=ghcr.io/dongxiujiang/anshun-mahjong:<旧标签>|' .env
docker compose -f compose.prod.yaml up -d app --pull never
```

### 完整 APK

Android 不允许 versionCode 降级；回滚完整包必须发布更高 versionCode 的修复包。

## 9. 常见问题

### GitHub Actions artifact 下载慢

Actions artifact 不是 Release asset，`ghproxy` 不能直接代理；`full-release` 还包含 Windows EXE，体积通常 200 MB 以上。

如果只需要 Android APK，可以运行仓库里的 `Promote full release artifact` 工作流：

```text
Actions → Promote full release artifact → Run workflow
run_id = 39136889832
artifact_name = full-release-39136889832
tag = V1.0.0-bridge-39136889832
```

它会在 GitHub 内部下载 artifact，只把 APK 和 `update-manifest.json` 发布成 Release 资产，然后从 Release 下载：

```text
https://github.com/dongxiujiang/anshun-mahjong/releases/download/<tag>/anshun-mahjong.apk
```

国内网络可在前面加代理：

```text
https://ghproxy.net/https://github.com/dongxiujiang/anshun-mahjong/releases/download/<tag>/anshun-mahjong.apk
```

`baseline` artifact 仍建议保留；它只有约 24 MB，后续打补丁需要。

| 现象 | 处理 |
|---|---|
| `/healthz` 502 | `docker compose ps` 看 app；`docker compose logs app` |
| `/updates/` 404 | 检查 Nginx include、alias 路径、文件是否存在 |
| `/updates/` 403 | 目录 755、文件 644，Nginx 用户可读 |
| 完整 APK 装不上 | versionCode 不高于已安装版本，或签名不一致 |
| 客户端显示已是最新 | 清单 version 不高于当前 effective version，或清单缓存未刷新 |
| 热更新下载失败 | PCK URL、HTTPS 证书、SHA/大小、`/updates` 可访问性 |
| Docker Hub 超时 | 本方案不使用 caddy 镜像；app 从 GHCR 拉取 |
| Caddy 抢 80/443 | 只启动 app；不要 `docker compose up -d` |
| 域名 HTTPS 失败 | DNS、80/443 安全组、Cloudflare 灰云 |
| 服务器重启后房间丢失 | 房间在内存中，服务器重启不恢复对局 |
