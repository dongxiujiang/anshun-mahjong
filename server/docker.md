# Docker 一键部署在线房间服务器

这套部署包含两个容器：

- `app`：Python 房间目录 + 每个房间一个无界面 Godot 权威进程。
- `caddy`：自动申请 HTTPS 证书，把 `https://你的域名` 反向代理到目录服务。

游戏房间使用 ENet UDP，**不经过 Caddy**，由 `app` 容器直接暴露 `7600-7631/udp`。

## 模式二（推荐）：CI 构建镜像，服务器不克隆

仓库新增了 [`.github/workflows/docker-image.yml`](../.github/workflows/docker-image.yml)：

- push `V1.0.*` 标签或手动触发时，构建 `linux/amd64` 镜像并推送到 GHCR。
- 同时上传 `server-deploy-bundle` 产物，里面只有 `compose.prod.yaml`、`docker/Caddyfile`、`deploy-image.sh`、`.env.example`。

服务器只需要这四个文件，**不需要项目源码、Godot 或 Python**：

```text
/opt/mahjong/
  compose.prod.yaml
  docker/Caddyfile
  deploy-image.sh
  .env
```

`.env` 示例：

```dotenv
APP_IMAGE=ghcr.io/<owner>/<repo>:V1.0.4
DOMAIN=play.example.com
PUBLIC_HOST=play.example.com
MAX_ROOMS=16
FIRST_PORT=7600
```

部署/更新/回滚都只换镜像标签：

```sh
sh deploy-image.sh play.example.com ghcr.io/<owner>/<repo>:V1.0.4
```

脚本会更新 `.env` 里的 `APP_IMAGE`，执行 `docker compose -f compose.prod.yaml pull` 和 `up -d`。

如果镜像是私有包，服务器先登录：

```sh
docker login ghcr.io -u <GitHub用户名> -p <带 read:packages 的 PAT>
```

更新时换标签即可；回滚就填旧标签。GHCR 在国内可能较慢，可以把同一镜像重新推到阿里云 ACR/腾讯云 TCR，`APP_IMAGE` 填对应 registry 地址即可。

## 1. 前置条件

- 一台 Linux x86_64 云服务器，建议至少 2 核 4G；4 核 8G 可开更多房间。
- 已安装 Docker Engine 24+ 和 Docker Compose v2。
- 域名 A 记录已指向服务器公网 IPv4。
- 云安全组和系统防火墙放行：
  - TCP `80`、`443`
  - UDP `7600-7631`
  - SSH 端口按你的实际配置
- **不要**对公网开放 `8080`。

如果域名使用 Cloudflare，`DOMAIN` 对应记录必须设为 **DNS only（灰云）**，否则 UDP 房间端口无法直连。

## 2. 模式一：源码构建启动

在仓库根目录执行：

```sh
sh deploy.sh play.example.com
```

它会从 `.env.example` 生成 `.env`，把 `DOMAIN` / `PUBLIC_HOST` 改成传入的域名，然后执行 `docker compose up -d --build`。

如果你想手动控制配置：

```sh
cp .env.example .env
```

编辑 `.env`：

```dotenv
DOMAIN=play.example.com
PUBLIC_HOST=play.example.com
MAX_ROOMS=16
FIRST_PORT=7600
```

然后：

```sh
docker compose up -d --build
```

首次构建会下载 Ubuntu 基础镜像、Godot 4.7.2 和依赖，通常需要几分钟。

查看状态：

```sh
docker compose ps
docker compose logs -f app
docker compose logs -f caddy
```

验证：

```sh
curl -fsS https://play.example.com/healthz
curl -fsS https://play.example.com/rooms
```

`/healthz` 返回类似：

```json
{"ok":true,"rooms":0,"max_rooms":16,"version":"1"}
```

## 3. 客户端设置

游戏内进入：

```text
联机房间 → 在线 → 服务器设置
```

填写：

```text
https://play.example.com
```

保存后写入 `user://network.cfg`。不用填端口，HTTPS 走 443；房间 UDP 端口由目录服务自动返回。

如果客户端连接房间失败，先把 `.env` 的 `PUBLIC_HOST` 临时改成服务器公网 IP 测试，确认是域名解析问题还是 UDP/防火墙问题。

## 4. 端口与房间数

`compose.yaml` 暴露：

```yaml
- "7600-7631:7600-7631/udp"
```

对应最多 32 个房间端口。默认 `MAX_ROOMS=16`，实际使用 `7600-7615`。

如果要把 `MAX_ROOMS` 改到 32，保持端口范围不变即可；超过 32 需要同时修改：

1. `compose.yaml` 的 UDP 端口范围。
2. 云安全组和系统防火墙的 UDP 范围。
3. `.env` 的 `MAX_ROOMS` / `FIRST_PORT`。

每个 Godot 房间进程大约占 150–300MB 内存，先按 `MAX_ROOMS=16` 观察，再决定是否增加。

## 5. Docker 与防火墙

Docker 发布的端口可能绕过 UFW 的默认规则。**以云厂商安全组为准**，并在服务器上检查：

```sh
sudo ss -lunp | grep 76
sudo iptables -S DOCKER-USER
```

如果需要用 UFW 限制 Docker 端口，规则要写在 `DOCKER-USER` 链，而不是普通的 `INPUT` 链。最简单的做法是只在云安全组开放 UDP `7600-7631`，并在主机上不额外开放其他端口。

## 6. 常用运维

更新代码后重建：

```sh
docker compose up -d --build
```

只重启：

```sh
docker compose restart app
```

停止：

```sh
docker compose down
```

查看房间日志：

```sh
docker compose exec app ls -l /app/build/room-server
docker compose exec app tail -f /app/build/room-server/123456.log
```

备份（只需要部署配置，牌局状态在内存里）：

```sh
tar czf mahjong-deploy-$(date +%F).tgz .env compose.yaml Dockerfile docker server
```

## 7. 当前限制

- 目录服务没有账号系统；`POST /rooms` 目前是公开接口，正式公网建议加每 IP 建房限流。
- ENet UDP 是明文传输；域名和 HTTPS 只保护目录接口，不保护牌局流量。
- 一房一 Godot 进程，扩容以增加服务器/容器为主；暂不支持多机房间分片。
- 服务器重启后，内存中的牌局不会恢复；客户端会进入重连失败提示。
- `Dockerfile` 会把工程源码和 Godot 二进制放进镜像；镜像较大是正常的。
