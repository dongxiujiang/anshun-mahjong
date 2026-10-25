# 安顺麻将 · 捉鸡（Godot 4.7）

108 张（万/条/筒 × 1-9 × 4，无字牌）的安顺麻将「捉鸡」四人对局游戏。仅支持 **Android**。

牌面使用 `res/tiles` 素材：**1-9.png=筒子，11-19.png=条子，21-29.png=万字**（270×360）；牌背无素材，由程序化绘制（缺图时牌面也自动回退程序化绘制）。

- 单机：1 名真人（座位0，首局为庄）+ 3 个 AI；之后按本局结果换庄。
- 联机：局域网自动搜索房间，也支持连接云端房间服务；先选座、换座和准备，人不够由默认准备的 AI 补位，全部准备后开局。
- 更新：主菜单和联机大厅都可「检查更新」。新完整 APK 默认使用自建 HTTPS 更新源，主清单和回退清单都在 `https://mj.dongxiu.fun/updates/`；1.1.9 及更早版本仍需先安装一次新完整包。
- 联机语音：正在从 LiveKit 迁移到腾讯云 GME；Android 使用 GME arm64，Windows 暂时保留 PCM。需要服务器 `GME_APP_ID`/`GME_APP_KEY`，详见 [GME 语音接入手册](docs/gme_voice.md)。

联机采用可靠的状态同步和权威端校验，不采用帧同步；断线保留座位并由 AI 暂代，详情见 [联机网络模型](docs/network_model.md)。当前版本 **1.5.18**，完整规则见 [当前游戏规则与玩法](docs/当前游戏规则与玩法.txt)，新增界面规范见 [UI 风格指南](docs/ui_style_guide.md)。GitHub Actions 的 Windows/Android 构建、签名和热补丁流程见 [CI/CD 发布说明](docs/ci_release.md)。

应用更新使用本项目公开仓库的 GitHub Releases：兼容小版本在 Windows 和 Android 游戏内下载补丁，重启生效，不必重装；大版本更新完整 EXE/APK。首次使用热更新须安装包含 PatchBoot 的完整版本。自 1.4.19 起，自建更新清单必须携带离线 RSA 签名，客户端只信任内置公钥验证通过的 `signed_payload`；发布与基线保存流程见 [docs/updates.md](docs/updates.md)。

---

## 一、运行（PC）

1. 用桌面上的 `Godot_v4.7.2-stable_win64.exe` 打开本工程（选择 `project.godot`）。
2. 直接按 F5 运行（主场景 `scenes/MainMenu.tscn`）。
3. 主菜单选择「单机对局」即可开始；「联机」进入建房/加入。

命令行运行：
```
Godot_v4.7.2-stable_win64.exe --path "桌面/Mahjong-Godot"
```

## 二、玩法操作

- 轮到你：轻点一次**手牌或摸牌**即可打出，不再显示「出牌」按钮。拖动不会误出牌；开局发牌和自己的摸牌动画完成前不能出牌。若可自摸/暗杠/加杠/报听，右下操作区会出现对应按钮。
- 别家打出牌：底部出现 **胡 / 碰 / 杠 / 过**，点选即可。
- 报听：在自己第一次摸牌后的出牌机会，打出一张即可听牌时可点「报听」；此前允许连续暗杠并从牌尾补牌，但不能有碰、明杠或加杠。报听后手牌区域显示一整圈金色边框并锁定，只允许打出刚摸到的牌；金色边框只包住手牌，不含摸牌位，联机其他玩家也可见；自动摸打，只能打摸到的牌；自动出牌等待与人机速度设置一致，摸到可自摸的牌或别人点炮可胡时停下，等待玩家选择自摸/胡。
- 暗杠：只开放两个窗口——开局手牌已有四张，第一次弃牌前；或本回合摸到第四张，本次弃牌前。选择弃牌后这张牌本局不能再暗杠。加杠只在本回合摸到第四张时开放；本次不选择加杠，本局该牌不能再加杠。明杠响应中若本可杠却选择碰，本局该牌也不能再加杠。自己的牌桌视图立即显示暗杠牌面，其他玩家看到四张反扣。暗杠补牌后的本轮出牌仍保持对其他玩家反扣，下一轮该玩家出牌后四张一起翻开；同一轮连续暗杠一起翻开，不同轮暗杠各自等待。亮出后联机公开牌面，AI也开始计入可见牌；提前结算时展示完整牌面。
- 四家分数默认各 200，可为负；牌桌各玩家名字下显示当前累计分数，叫牌和本局记分明细放在局末结算卡片。单机可继续下一局，保留累计分数。
- **个人本局分**：叫牌玩家记正数，未叫牌玩家记负数。叫牌为 `+（翻鸡 + 幺鸡八筒 + 杠 + 牌型 + 放炮 + 自摸）× 倍率`；未叫牌为 `-（翻鸡 + 幺鸡八筒 + 杠 + 牌型 + 放炮 + 自摸）`。之后按叫牌/未叫牌两两付款：未叫玩家支付“叫牌玩家的个人分 + 自己的负分”，总计保持零和。未叫牌杠主反向支付杠基础分：明杠只付给放杠者，暗杠/加杠付给每位叫牌者。叫牌玩家之间按分差少给多，未叫玩家之间不互付。
- 牌桌中央只保留四家的累计分数：单机不显示东南西北或相对称呼；联机在分数上方显示玩家自己输入的姓名，AI 统一显示“人机”。四个分数相对中央正方形的上、右、下、左边水平/垂直居中，庄家标识紧贴自己的分数。当前出牌玩家对应的正方形外边缘会出现淡黄色散射光；等待碰杠胡、发牌、结算时熄灭。
- **胡牌那张牌停在摸牌位**：自摸或胡别人打出的牌，那张牌都单独显示在右侧摸牌位，不并回手牌排序里，一眼能看出胡的是哪张。
- **结算卡片**：从上到下为你、上家、对家、下家。每家第一行显示累计分数、自己的「本局分」，以及从该玩家自己视角与上家、对家、下家的三笔收付（正数收款，负数付款）。本局分是得分点合计，明杠基础4分仅向放杠者收，不混入通用本局分。明细显示叫牌状态、自摸等奖励及完整牌面：同类型、同单张分值的牌合并一组，普通鸡2、金鸡4、冲锋鸡4、冲锋金鸡8分别展示，翻鸡也按张数合计。所有杠集中放在最后，四张牌与基础杠分、杠内鸡分一并展示；暗杠、加杠四张都竖放。明杠来源是下家时第四张右横，上家时第一张左横，对家时三张竖牌上方居中横放第四张。明细多时独立换行和滚动。卡片右上角「看牌桌」与「查看结算」在同一位置切换。结算动画按“清零/重置 → 翻鸡展示 → 翻鸡计分 → 幺鸡八筒 → 暗杠/加杠 → 胡牌分项 → 两两收支滚动 → 最终分数”推进；结算卡默认不遮挡牌桌，玩家可手动打开结算页查看明细。进入结算阶段后四家手牌全部翻开显示牌面，包括流局和四家叫牌流局。
- 牌桌按四向围坐排布，Android 固定横屏：自己的手牌和摸牌使用 2.40 倍牌面（上版的 1.5 倍），自己的碰杠牌和鸡牌使用 1.60 倍，其他三家使用 1.35 倍，弃牌保持 1.10 倍；牌墙数据继续用于骰子和发牌，但牌桌不绘制牌墙。东西两家手牌与摸牌位整体水平居中，操作按钮放在摸牌位上方，报听、碰、杠、胡、自摸等选择按钮统一为 177×126（原按钮的 1.5 倍），字号为 42，与手牌留出 56 像素的空隙；手牌变短时按钮会向右避开自己的弃牌区，允许覆盖下家弃牌区。碰杠后仍会按空间向内换行。碰杠/鸡牌固定从手牌左边缘向左排列，满一行后向上换行；不再向手牌右侧溢出，空间不足时使用确定性紧凑兜底。东西两家的弃牌容器扩大并隐藏滚动条，牌面尺寸不变。幺鸡、八筒各自全场首张打出的牌横放表示冲锋鸡；被碰杠后原弃牌区和记录移除，冲锋标记跟随到领取者的碰杠组。碰不标来源；明杠与结算采用相同的上/对/下家横牌排列；暗杠、加杠全部四竖。联机时自己的座位始终在下方。
- 右上角可调 AI 出牌速度：**快 0.8 秒 / 中 1.3 秒 / 慢 2 秒**；碰/杠响应与出牌等待一致，单机和主机即时生效。
- 设置面板新增 **AI强度**：弱 / 中 / 强三挡，当前默认弱；中、强策略后续接入。
- 右上角新增 **AI教打**：点击后分析自己手牌和刚摸到的牌，复用 AI 的公开信息模型，推荐牌高亮，手牌上方显示类似结算的消息，包含向听数和进张数。不会读取对手暗手或牌墙顺序。
- 联机模式下，其他真人的喇叭/静音按钮移到自己分数附近，不再伸到弃牌区上方。
- 主菜单「声音设置」或牌桌右上角「设置」可分别开关、调整背景音乐、出牌/动作语音和落桌音效。设置自动保存，下次运行继续使用。默认背景音乐12%、语音80%，音乐较轻，不盖过喊牌。
- 进入牌桌循环播放 Kevin MacLeod《Ripples》（57 BPM，舒缓拨弦风格，CC BY 4.0），已降低响度并在声音设置中署名。四家使用两男两女的不同普通话声音，绑定座位，换庄也保留原声音。每次实际出牌喊对应牌名（一条喊「幺鸡」），碰、明杠/暗杠/加杠、报听分别喊「碰」「杠」「报听」，自摸喊「自摸」，胡别人或抢杠喊「胡了」。无效动作和流局不喊胡；加杠从宣告到完成只喊一次，暗杠不喊具体牌名。喊牌时音乐自动降低音量，语音结束后恢复；返回大厅停止牌桌音频。声音设置可分别试听四套声音。素材随工程运行，PC/Android 均无需联网或安装语音引擎。

## 三、联机

1. 主菜单 →「联机房间」，默认进入「局域网」，自动搜索同一局域网内的房间，不需要输入 IP。
2. 创建者输入 **4～8 位数字房间号**（保留前导零）、昵称和房间名称；昵称修改时房间名称自动变为“昵称+麻将局”，手动修改房间名称后不再自动跟随。其他玩家可以按房间号/名称筛选并点击「加入」。局域网已有同号房间时禁止创建。
3. 创建/加入后进入等待房间，**此时不发牌**。点击人机位置直接选座；点击真人位置发送换座申请，由对方同意或拒绝，20 秒未响应自动取消。
4. 空位由人机补齐且默认准备；真人点击「准备」。加入、离开、交换或更换座位会取消真人准备，变更「我想当庄」取消自己的准备。全部准备后倒数 **3 秒**，取消准备可以停止倒数。
5. 首局从勾选「我想当庄」的玩家中随机选庄；仅一人勾选则直接当庄，无人勾选则四家随机。后续局继续按胡牌、放炮、流局规则换庄，累计分数保留。
6. 已开局房间不接受新加入者；真人中途断线由人机代打。局域网主机关闭则房间结束，在线房主退出可转交房主权限。
7. 选择「在线」后，在「服务器设置」保存房间服务地址，之后自动搜索在线房间，创建/加入沿用同一准备流程。在线房主也是客户端，游戏由云端 Godot 进程权威运行，房主可以点「下一局」。**没有配置服务器时显示设置提示，不显示模拟房间。**

工程附带可部署的云端服务，当前已部署在 `https://mj.dongxiu.fun`。完整 Docker 生产流程见下面的 3.1；服务端脚本和排障细节见 [server/README.md](server/README.md) 与 [server/docker.md](server/docker.md)。

局域网同时使用 UDP 广播、绑定 Wi-Fi/热点网卡的定向查询和有节奏的本地网段扫描（7499～7508）；房主也会向搜索端口 7509～7518 主动发送房间信息。这样手机给电脑开热点时不依赖系统转发全网广播，也无需输入 IP。只扫描当前私有 IPv4 地址所在的 /24，不扫描公网；更大网段仍使用广播发现。游戏端口建房时自动选取，不在 UI 展示 IP。在线使用 HTTP(S) 房间目录 + ENet/UDP 独立游戏端口，玩家无需配置本地端口映射。

### 3.1 在线服务器 Docker 部署

完整的服务端从零部署、客户端完整包、热补丁和自建更新源发布流程见 [docs/deploy_release_update.md](docs/deploy_release_update.md)；本次已走通的实操命令见 [docs/self_hosted_update_operation.md](docs/self_hosted_update_operation.md)。1.4.16 的实际发布与部署记录见 [docs/release_operation_1.4.16.md](docs/release_operation_1.4.16.md)，1.4.17 记录见 [docs/release_operation_1.4.17.md](docs/release_operation_1.4.17.md)，1.4.18 记录见 [docs/release_operation_1.4.18.md](docs/release_operation_1.4.18.md)，1.4.19 记录见 [docs/release_operation_1.4.19.md](docs/release_operation_1.4.19.md)，1.5.0 记录见 [docs/release_operation_1.5.0.md](docs/release_operation_1.5.0.md)，1.5.1 记录见 [docs/release_operation_1.5.1.md](docs/release_operation_1.5.1.md)，1.5.2 记录见 [docs/release_operation_1.5.2.md](docs/release_operation_1.5.2.md)，1.5.3 记录见 [docs/release_operation_1.5.3.md](docs/release_operation_1.5.3.md)，1.5.4 记录见 [docs/release_operation_1.5.4.md](docs/release_operation_1.5.4.md)，1.5.5 记录见 [docs/release_operation_1.5.5.md](docs/release_operation_1.5.5.md)，1.5.6 记录见 [docs/release_operation_1.5.6.md](docs/release_operation_1.5.6.md)，1.5.7 记录见 [docs/release_operation_1.5.7.md](docs/release_operation_1.5.7.md)，1.5.8 记录见 [docs/release_operation_1.5.8.md](docs/release_operation_1.5.8.md)，1.5.9 记录见 [docs/release_operation_1.5.9.md](docs/release_operation_1.5.9.md)，1.5.10/1.5.11 记录见 [docs/release_operation_1.5.11.md](docs/release_operation_1.5.11.md)，1.5.12 记录见 [docs/release_operation_1.5.12.md](docs/release_operation_1.5.12.md)，1.5.13 记录见 [docs/release_operation_1.5.13.md](docs/release_operation_1.5.13.md)，1.5.14 记录见 [docs/release_operation_1.5.14.md](docs/release_operation_1.5.14.md)，1.5.15 记录见 [docs/release_operation_1.5.15.md](docs/release_operation_1.5.15.md)，1.5.16 记录见 [docs/release_operation_1.5.16.md](docs/release_operation_1.5.16.md)，1.5.17 记录见 [docs/release_operation_1.5.17.md](docs/release_operation_1.5.17.md)，1.5.18 记录见 [docs/release_operation_1.5.18.md](docs/release_operation_1.5.18.md)。

生产环境由两部分组成：

```text
公网 TCP 80/443 → Nginx（宿主机） → 127.0.0.1:18080 → app 容器
公网 UDP 7600-7631 → app 容器（每个房间一个 Godot 进程）
```

`app` 镜像由 GitHub Actions 构建，服务器只拉镜像，不克隆项目。Nginx 负责 HTTPS；`caddy` 容器在这种模式下保持停止，避免抢 80/443。

#### 3.1.1 构建镜像

GitHub Actions → **Build online server image** → **Run workflow**，或推送 `V1.0.*` 标签。

- 手动运行在 `main` 上：镜像标签通常是 `sha-<短提交>`，例如 `sha-c1d0274`。
- 推版本标签：会同时生成版本标签和 `latest`。
- 镜像地址：`ghcr.io/dongxiujiang/anshun-mahjong:<标签>`。
- 每次运行还会上传 `server-deploy-bundle`，内含 `compose.prod.yaml`、`docker/Caddyfile`、`deploy-image.sh`、`.env.example`。

私有包需要 PAT（`read:packages`）：

```sh
echo "$GHCR_TOKEN" | docker login ghcr.io -u dongxiujiang --password-stdin
```

Public 包可以跳过登录。

#### 3.1.2 服务器安装 Docker

Ubuntu 24.04：

```sh
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
newgrp docker
docker --version
docker compose version
```

Docker Hub 是否可访问不影响 app 镜像（GHCR）；只有使用 `caddy:2-alpine` 时才需要 Docker Hub，或配置阿里云镜像加速器。

#### 3.1.3 获取部署文件

不需要克隆仓库。镜像里已经包含部署文件，拉取后直接复制：

```sh
cd ~
mkdir -p mahjong/docker

docker pull ghcr.io/dongxiujiang/anshun-mahjong:sha-c1d0274

docker create --name mahjong-bundle \
  ghcr.io/dongxiujiang/anshun-mahjong:sha-c1d0274

docker cp mahjong-bundle:/app/compose.prod.yaml ~/mahjong/
docker cp mahjong-bundle:/app/deploy-image.sh ~/mahjong/
docker cp mahjong-bundle:/app/.env.example ~/mahjong/
docker cp mahjong-bundle:/app/docker/Caddyfile ~/mahjong/docker/

docker rm mahjong-bundle
```

也可以从 Actions 下载 `server-deploy-bundle`，或只从仓库取这四个文件。国内服务器直接 `curl raw.githubusercontent.com` 可能很慢，优先用镜像内的文件。

#### 3.1.4 配置 `.env`

```sh
cd ~/mahjong
cp .env.example .env
nano .env
```

```dotenv
APP_IMAGE=ghcr.io/dongxiujiang/anshun-mahjong:sha-c1d0274
DOMAIN=mj.dongxiu.fun
PUBLIC_HOST=mj.dongxiu.fun
MAX_ROOMS=16
FIRST_PORT=7600
```

- `APP_IMAGE` 必须填实际标签。
- `DOMAIN` 用于 Nginx 的 HTTPS 站点名。
- `PUBLIC_HOST` 是目录返回给客户端的房间连接地址，通常同 `DOMAIN`；如果客户端 ENet 解析域名有问题，可改成服务器公网 IP。
- `MAX_ROOMS` 与 `FIRST_PORT` 要和 `compose.prod.yaml` 的 UDP 端口范围、云安全组一致。

#### 3.1.5 只启动 app，使用现有 Nginx

如果 80/443 已被 Nginx 占用，不要启动 `caddy`。在 `compose.prod.yaml` 的 `app.ports` 中确认有：

```yaml
- "127.0.0.1:18080:8080"
- "7600-7631:7600-7631/udp"
```

然后：

```sh
cd ~/mahjong
docker compose -f compose.prod.yaml config
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

不要执行 `docker compose up -d`，否则会启动 `caddy` 并和 Nginx 抢 80/443。

#### 3.1.6 配置 Nginx

```sh
sudo tee /etc/nginx/sites-available/mj.dongxiu.fun >/dev/null <<'NGINX'
server {
    listen 80;
    server_name mj.dongxiu.fun;

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

sudo mkdir -p /var/www/mahjong/updates
sudo chown admin:admin /var/www/mahjong/updates

sudo ln -sf /etc/nginx/sites-available/mj.dongxiu.fun /etc/nginx/sites-enabled/mj.dongxiu.fun
sudo nginx -t
sudo systemctl reload nginx
```

热更新清单和 PCK 放到 `/var/www/mahjong/updates/`；客户端从 `https://mj.dongxiu.fun/updates/update-manifest.json` 读取。发布命令见 [docs/updates.md](docs/updates.md) 的“自建更新源”一节。

先在本机验证反代，不依赖 DNS：

```sh
curl -i -H 'Host: mj.dongxiu.fun' http://127.0.0.1/healthz
```

返回 200 后再申请证书：

```sh
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d mj.dongxiu.fun
```

前提：域名 A 记录指向服务器公网 IP；阿里云安全组开放 TCP 80/443；Cloudflare 对应记录为 DNS only（灰云）。

#### 3.1.7 云安全组和 DNS

必须开放：

```text
TCP 80, 443
UDP 7600-7631
```

只开 80/443 时网页和建房接口正常，但客户端加入房间会连接超时。

#### 3.1.8 验证

```sh
curl -fsS https://mj.dongxiu.fun/healthz
curl -fsS https://mj.dongxiu.fun/rooms
```

正常返回：

```json
{"ok":true,"rooms":0,"max_rooms":16,"version":"1"}
{"rooms":[]}
```

客户端：

```text
联机房间 → 在线 → 服务器设置
https://mj.dongxiu.fun
```

客户端首次启动会预填 `https://mj.dongxiu.fun`；如果本机已经保存过其他服务器地址，以保存值为准，可在服务器设置里改回生产地址。

用客户端创建房间，第二台设备用手机 4G 加入，测准备、发牌、断线重连。

#### 3.1.9 更新和回滚

只更新 app，不启动 Caddy：

```sh
cd ~/mahjong
docker pull ghcr.io/dongxiujiang/anshun-mahjong:<新标签>

sed -i 's|^APP_IMAGE=.*|APP_IMAGE=ghcr.io/dongxiujiang/anshun-mahjong:<新标签>|' .env
docker compose -f compose.prod.yaml up -d app --pull never
```

回滚就是填回旧标签再执行一次。Nginx 配置和证书不需要改。

#### 3.1.10 常见问题

| 现象 | 原因/处理 |
|---|---|
| Caddy 报 `port 80 already in use` | Nginx 占用 80/443；只启动 app，不要启动 Caddy |
| `docker compose pull` 卡住 | Docker Hub 不可达；app 用 GHCR 可直连，Caddy 可走镜像加速器或改用 Nginx |
| GHCR `unauthorized` | 私有包需要 `read:packages` PAT，先 `docker login ghcr.io` |
| `/healthz` 404 | Nginx 没加载站点，检查 `nginx -T` 和 `sites-enabled` 软链 |
| HTTPS 证书失败 | DNS、80 端口、Cloudflare 灰云三项逐一检查 |
| 建房成功但加入超时 | 云安全组 UDP 7600-7631 未开放，或 `PUBLIC_HOST` 客户端不可达 |
| 服务器重启后 Caddy 起来抢端口 | 保持 `caddy` 停止；只使用 `up -d app` |
| app 不健康 | `docker compose -f compose.prod.yaml logs --tail=100 app` |

如果 80/443 完全空闲，也可以使用带 Caddy 的完整模式：`compose.prod.yaml` 同时启动 `app` 和 `caddy`，由 Caddy 自动申请证书，不需要 Nginx 和 Certbot。当前生产服务器已有 Nginx，因此采用 app + Nginx 方案。

## 四、规则实现要点

- **发牌**：庄家/对家面前 28 张（14 墩），上家/下家 26 张（13 墩），合计 108；四人牌墙按物理顺时针连成一环。
- **掷骰破墙**：单颗骰 D。D∈{1,3,5}→破对家墙，D=4→破上家墙，D∈{2,6}→破下家墙；自牌头跳过 D 墩起摸，每次两墩（4 张）。
- **起手**：按庄→下家→对家→上家的顺时针方向轮流拿 4，三轮后各 12，再各 1 共 13；庄再摸 1 成 14 开打。之后统一按顺时针摸牌、出牌和检查响应。
- **行牌**：只能碰/杠，不能吃。杠从牌尾补一张。暗杠和加杠补牌后的第一张弃牌可以被普通牌型胡；只有这两类弃牌被胡才算杠后放炮并烧鸡。明杠后弃牌不再开放普通胡通行资格，只有报听、大对子、七对、清一色、自己有暗杠/加杠等条件仍可胡。只有加杠可以被抢，抢杠胡由被抢杠者支付12分及牌型分。被抢杠者或杠后弃牌放炮者烧鸡：自己的全部鸡分归 0，自己的出牌鸡、碰中鸡、杠中鸡和杠收入都不计；仍必须赔付赢家的出牌鸡、碰中鸡、杠中鸡、杠分和放炮分。胡牌优先于碰牌，碰牌优先于摸牌；同一张弃牌允许多人同胡。小七对、大对子、清一色等牌型可胡别人打出的牌；普通牌只有自摸，除非持有自己的暗杠/加杠、报听，或牌来自报听者/暗杠或加杠后出牌等特殊情形。
- **过牌限制**：过胡后直到自己下一次摸牌前只能自摸；过碰后同张牌在自己下一次摸牌前不能再碰。碰牌后不能立即打出刚碰的同一张牌。
- **报听**：第一次摸牌后的出牌机会，打出后形成听牌且此前只暗杠时可报听；报听胡牌24；报听自摸普通牌只收24+鸡、不再加自摸4；报听自摸有牌型为牌型分+20+鸡（只算一个自摸4）。报听者放炮或他人自摸时，仅该报听者另付杀报24；若赢家也报听，则按报听胡牌由放炮者或自摸三家各付24，不再重复杀报。报听者打出的牌允许直接胡。
- **胡牌分值**：普通自摸4（报听自摸的普通牌不再加4，只收24+鸡）；干扣14、大干扣24；小七对24、龙七对44、大对子14、大对子单吊24、清一色24、清大对34、清七对44、清单吊54、清龙对64。牌型按最高一项计；龙七对不叠加小七对。牌型总分已包含基础自摸4，不重复加4。
- **下局庄家**：自摸者为庄；胡别人或抢加杠时，放炮者/被抢杠者为庄。流局无论是否有人未叫牌均由当前庄家连庄。新庄家首先摸牌出牌，发牌顺序、14/13墩牌墙和骰子破墙都以新庄家为准；单机与联机均保留累计分数。
- **捉鸡**：
  - 鸡牌 = 一条、八筒。
  - 冲锋鸡：幺鸡、八筒各自全场第一张打出的牌为冲锋鸡，每张 4 分；后续同种牌为普通鸡。被碰杠后，原出牌者的弃牌及记录移除，鸡分与冲锋标记归领取者。
  - 叫牌鸡：已叫牌者，保留的出牌鸡与手中、碰杠中的普通鸡每张 2 分。冲锋鸡被碰或杠后按普通鸡计，每张保留 2 分；若翻鸡命中，照普通鸡翻倍。未叫牌者手中鸡仍不计正分，但其**碰中的幺鸡/八筒**也要向每位叫牌者补付。
  - 翻牌鸡：胡牌后翻牌头下一张；上下张同花色首尾循环，翻一取九、一、二，翻九取八、九、一。叫牌者手中（含碰杠）的三张翻牌范围内普通牌每张 1 分；若三张包含幺鸡或八筒，该鸡牌算金鸡，普通鸡从 2 变 4、冲锋鸡从 4 变 8，其他两张仍按翻鸡每张 1 分；出牌鸡也按金鸡翻倍。
  - 普通牌自摸4；报听自摸的普通牌只收24+鸡，不再加自摸4；赢家鸡分为0时干扣总计14；若四家结算鸡分都为0，大干扣改为总计24，不叠加干扣。干扣只用于普通小牌自摸，报听和大牌自摸不加干扣。
  - 杠开 +5；海底（最后四张任意牌）自摸 +5；干扣、牌型、报听分值均按各自条款结算。
  - 胡牌结算的杠基础分：叫牌者暗杠、加杠每组由其他每家各付4；明杠每组仅放杠者付4。杠内鸡/翻鸡纳入完整鸡分逐家比较一次，不再额外重复收鸡分。杠牌者未叫牌不收杠分。例：明杠四张普通鸡，放杠者付鸡分8+杠分4=12，其他无可抵鸡分的玩家各付鸡分8。
  - 有人胡牌时，四家两两比较幺鸡八筒、杠分和翻鸡分（手中、碰杠、保留出牌鸡、金鸡及翻鸡）；未叫牌者自身鸡分按0参与，但其出牌鸡、碰中鸡和杠中鸡按债务补付给叫牌者。自摸由另外三家各付完整胡牌分；普通自摸含4分，报听自摸普通牌为24+鸡、不再加4，有牌型为牌型分+20+鸡、只算一个自摸4；普通放炮不收17/21，**放炮牌型分只由放炮者支付**，其他两家不付牌型分，只按幺鸡八筒、杠分、翻鸡分比较。杠放炮的17/21由放炮者另付；自带暗杠/加杠的玩家以普通小牌胡别人弃牌时，放炮者另付4分（大对子、七对、清一色、报听及以上不加）；抢杠12由被抢杠者另付。多家同胡时放炮者向每位胡牌者分别支付各自的牌型分，赢家之间不互付牌型差额。杠分、报听/杀报按各自付款关系另算。结算卡片“本局分”展示本人的得分点，“上家/对家/下家”展示实际逐家收付；分数从200起累计，可为负。
- **牌墙摸完无人胡牌**：不翻鸡。四家均叫牌时本局不计分，下局鸡分翻倍；连续流局时倍率仍保持 ×2，不继续倍增。若有人未叫牌，由未叫牌者向每位叫牌者补：双方已打出的幺鸡/八筒（翻鸡范围里的普通牌不计，幺鸡/八筒本身仍按金鸡/冲锋金鸡翻倍）、双方碰中的幺鸡/八筒、应付杠分，以及荒牌基础补付4分；叫牌者之间不补差，手中鸡不加入本次补分。
  - 暗杠、加杠：叫牌杠主每组基础杠分 4 分，由其他三家各付；未叫牌杠主不收自己的基础杠分，也不反向支付。杠中每张鸡按个人分计一次，再按叫牌/未叫牌两两付款。
  - 明杠：基础杠分4仅由未叫牌的放杠者付；杠中四张鸡的鸡分8由每个未叫牌者付。放杠者已叫牌时不收其基础4，其他未叫牌者仍补鸡分8。
  - 杠牌者未叫牌则不收杠分。杠内鸡牌在该组杠中计一次；翻倍局杠内鸡分也翻倍，基础杠分4不翻倍。
  - 四家均未叫牌时无收款人，本局不计分。有人胡牌或完成一次查叫补分后，下局鸡分倍率恢复为 1；翻倍只影响鸡分，不影响杠分、额外加分、牌型或报听费用。
- **诈胡**：非法胡牌处罚规则保留在规则设计中，当前版本尚未实现。
- **AI**：先筛选向听数合理的出牌，再综合有效进张、预期净收益和放炮损失。收益计算包含鸡牌/金鸡/翻鸡、流局查叫、定向杠分、龙七对等牌型及报听费用；碰、暗杠、加杠也会比较收益与抢杠风险。根据公开弃牌、碰杠和报听生成受剩余张数约束的对手听牌样本，估计各张牌的危险度及赔付；不读取对手暗手或牌墙顺序。在收益接近的前 6 个候选上再运行有界 MCTS（16 次模拟、深度 2），只作路线细化，不替代向听和防守硬约束。这不是训练模型或无限搜索。

> 所有番值/鸡值集中在 `scripts/autoload/GameConfig.gd`，便于按真实规则微调。

## 五、导出为可执行文件 / APK

工程已配置 Windows 与 Android 导出预设。首次在另一台电脑导出时，需要安装与 Godot 版本相同的导出模板：

1. 用 Godot 打开工程 → 顶部菜单 `编辑器 → 管理导出模板…` → 下载并安装 **4.7.2.stable** 模板。
2. PC：`项目 → 导出…` → 选择预设 **Windows** → `导出项目`，产物在 `build/windows/`。
3. Android：
   - 需安装 **Android SDK**（设置 `编辑器 → 编辑器设置 → 导出 → Android → Android SDK 路径`）与 JDK 17+。
   - 在 `项目 → 导出…` 中配置 **调试密钥库**（Android → 一键创建 debug keystore）。
   - 选择预设 **Android** → `导出项目`，产物在 `build/android/`。
   命令行：`godot --headless --export-release "Android" build/android/安顺麻将.apk`
4. 命令行导出 PC：`godot --headless --export-release "Windows" build/windows/安顺麻将.exe`

1.0.0 正式横屏版本已使用提供的游戏图标重新打包，发布文件位于 `build/releases/v1.0.0/`：Windows 安装向导、免安装主程序、Android 正式签名 APK 和更新清单。热更新基线位于 `build/update_baselines/1.0.0-boot1/`。首次发布与以后的小/大版本更新教程见 [docs/publishing.md](docs/publishing.md)；双击根目录 `生成小版本更新.cmd` 可准备后续小补丁。正式 APK 与旧调试版签名不同，首次需卸载旧调试版；后续正式版保持同一签名。

导出预设已写入 `export_presets.cfg`（Windows + Android，含包名 `com.anshun.mahjong`、arm64-v8a、沉浸式全屏）。

## 六、工程结构

```
scenes/        MainMenu / Lobby / GameTable 场景
scripts/
  autoload/    GameConfig(规则数值) · AudioManager(音轨/音量/去重) · Network(联机入口)
              PatchBoot(启动前挂载小版本补丁、失败回退)
              UpdateManager(GitHub Releases 两级更新、下载、校验和重启)
  core/        Tiles / TileSetFactory / WallBuilder / WallRing / PlayerState
               RuleEngine(判胡番型听牌) / Shanten(向听数) / ScoringEngine(捉鸡结算) / RoundState(回合状态机)
  ai/          AiPlayer(出牌/碰杠/报听决策) · AiValueModel(预期收付)
               AiOpponentModel(公开信息手牌采样与放炮风险) · AiMctsSearch(有界随机展望)
  online/      NetGameNode(等待房间/选座/准备/权威游戏) · LanDiscovery · OnlineDirectory
  ui/          TileView(程序化牌面) / MainMenu / Lobby / GameTable(牌局与联机事件协调) / SoundSettings
    table/     TableUiConfig(尺寸/颜色/间距/动画参数) · TableLayout(布局与背景)
               PlayerTileAreas(四家牌区) · TableActions(选牌与操作区)
               SettlementCard(结算卡片) · TableAnimationController(视觉事件队列)
               TableWidgets(统一控件样式) · TableComponent(弱引用生命周期)
               TableViewBridge(组件宿主与原 UI 接口兼容转发)
res/audio/     四个座位各32段牌名/动作语音、Ripples背景音乐、落桌音效与署名
tools/audio/   可选的素材生成工具（游戏运行不依赖）
tests/         headless 冒烟与联机测试
server/        Python房间目录 · Godot无界面房间服务器 · 部署说明
res/update/    Windows 更新替换脚本（只在已下载并校验后执行）
```

## 七、测试（headless）

一条命令跑完全部单测（任一失败则整体退出码为 1，可用于 CI）：

```
godot --headless --script res://tests/run_all.gd
```

推荐使用带实际时间限制、脚本错误检查和独立日志的入口，避免加载错误后一直等待；默认包含 29 套检查，AI 自战两套分别最多等待 10 分钟。把 Godot 路径替换成自己的路径：

```
python -X utf8 tests/run_suites.py --godot "C:/path/to/Godot.exe"
python -X utf8 tests/run_reconnect.py --godot "C:/path/to/Godot.exe"
```

第一条命令的日志保存在 `build/test_results/`，第二条验证大厅、开局和人机代打等待中的真实断线重连。联机回归也可以用 `tests/run_network.py --section lan`、`--section ready` 或 `--section online` 分别运行，避免重复执行已经通过的场景。

单独运行：

```
godot --headless --script res://tests/smoke_tiles.gd     # 牌面素材映射与手牌排序
godot --headless --script res://tests/smoke_wall.gd      # 牌墙/破墙/发牌
godot --headless --script res://tests/smoke_logic.gd     # 判胡/番型/听牌/向听
godot --headless --script res://tests/smoke_scoring.gd   # 捉鸡计分结算
godot --headless --script res://tests/settlement_card.gd # 本局分、三家收付、鸡牌归组、定向杠、结算布局与同步
godot --headless --script res://tests/smoke_ready.gd     # 报听窗口 + 报听后摸切
godot --headless --script res://tests/rules_complete.gd  # 结算/付款/翻鸡/优先级/报听/牌墙与番型
godot --headless --script res://tests/rules_update.gd    # 双冲锋归属、翻鸡循环、流局杠分、连续翻倍与暗杠报听
godot --headless --script res://tests/rules_spec.gd      # 当前规则逐项规格测试（点炮17/21、抢杠12、烧鸡、牌型、流局连庄）
godot --headless --script res://tests/scoring_audit.gd   # 独立结算审计与付款矩阵守恒
godot --headless --script res://tests/dragon_dealer.gd   # 龙七对44、结算选庄、四家换庄发牌/骰子/牌墙和同步
godot --headless --script res://tests/smoke_round.gd     # 单局集成
godot --headless --script res://tests/smoke_ai.gd        # AI 自战多局（含牌守恒）
godot --headless --script res://tests/ai_value.gd        # 预期收益与真实结算逐项核对
godot --headless --script res://tests/ai_inference.gd    # 手牌推断、公开信息隔离、收益与防守决策
godot --headless --script res://tests/ai_benchmark.gd    # 可选：与冻结的旧 AI 轮换座位对抗
godot --headless --script res://tests/shanten_cache.gd   # 向听数缓存与旧 DFS 逐项核对
godot --headless --script res://tests/smoke_ui.gd        # UI 异步闭环
godot --headless --script res://tests/smoke_audio.gd     # 音频素材/真实出牌/胡牌/同步去重/音量/后台/设置布局
godot --headless --script res://tests/sweep.gd           # 多种子扫描（胡/碰/杠/报听统计）
godot --headless --script res://tests/smoke_table_layout.gd  # 牌桌布局与溢出
godot --headless --script res://tests/table_components.gd   # 多牌桌隔离、操作提交边界、动画取消与退出释放
godot --headless --script res://tests/smoke_lan_discovery.gd # 热点单播/主动通知，广播被屏蔽及网卡缺失
godot --headless --script res://tests/smoke_lobby.gd     # 准备/AI/选座/随机庄家/横屏等待房间
godot --headless --script res://tests/smoke_update.gd    # GitHub 更新版本比较、地址/校验和平台处理
python tests/run_network.py --godot /path/to/godot      # 真实局域网、换座、延迟发牌、牌桌UI和在线服务
godot --headless --script res://tests/play_one.gd        # 完整一局逐步战报（人工观察用，不对断言负责）
# 联机（先主机，后客户端）
godot --headless res://tests/host_scene.tscn &
godot --headless res://tests/client_scene.tscn
```

所有测试通过 `tests/test_harness.gd` 收集断言并用退出码汇报结果：**全部通过返回 0，有失败返回 1**。新增测试请沿用这个写法（`call_deferred("_run")` + `t.expect(...)` + `quit(t.finish("名字"))`），不要用 `assert()`——它只在 debug 构建生效，且不会影响退出码。

## 八、规则约定 / 可调项

- 破墙「骰子-牌墙」对应按你描述的规则直译，集中在 `WallRing.compute_break()`，如与实际不符改此一处即可。
- 大对子按「对对胡（全刻/全杠）」实现；清一色「胡别人」类比小七对给 24。
- 普通平胡基础分按本局约定为 0；额外自摸、鸡分、番型和报听均通过转账结算，四家总分始终为 800。
- 大对子为四组刻子或杠加一对将，自摸每家 14，放炮者支付 14；小七对和清一色按 24 结算，龙七对按 44 替代小七对24。
- 两种冲锋鸡各有一张，鸡分按当前牌的归属计算；被碰杠的冲锋鸡降为普通鸡 2 分，杠中鸡牌再纳入该组 4 分基础杠分。
- 流局与查叫规则、每组杠 4 分见上节；结算弹窗按每家自己的视角显示三笔收付，杠组标明付款关系。鸡分倍率只出现在结算说明，四家叫牌流局后弹窗显示下局倍率。
- 联机为局域网/直连（ENet）；公网需端口映射。

## 九、牌桌 UI 可调参数

主要视觉参数集中在 [`scripts/ui/table/TableUiConfig.gd`](scripts/ui/table/TableUiConfig.gd)：`OWN_HAND_TILE_UNIT` 控制自己的手牌和摸牌（当前 2.40 倍），`OWN_PLAYER_TILE_UNIT` 控制自己的碰杠和鸡牌（1.60 倍），`PLAYER_TILE_UNIT` 控制其他三家的同类牌（1.35 倍），`TILE_UNIT` 保持弃牌牌面（1.10 倍）；牌墙数据仍参与骰子和摸牌逻辑，但牌桌不再绘制牌墙。`DISCARD_BUTTON_SIZE` 统一控制报听、碰、杠、胡等选择按钮（出牌改为点牌）；`SETTINGS_BUTTON_SIZE` 独立控制顶部设置入口（144×72），`SettingsButton.gd` 将触控范围向左、下扩大到 168×112，不增大可见按钮；碰杠牌区避开整个热区，`ACTION_HAND_GAP` 控制操作区与手牌上边的空隙。`RESULT_TILE_UNIT` 控制结算牌面和翻鸡牌；`DRAW_GAP` 是手牌与摸牌位之间的距离，`EXPOSED_HAND_GAP` 是碰杠/鸡牌与手牌的最小间隔。`TableLayout._hand_layout()` 让手牌和摸牌位整体居中，预留摸牌位避免摸打时整排晃动；`_seat_metrics()` 控制各家的手牌、弃牌区和碰杠换行区域。东西两家的弃牌区扩大容器但仍使用 `TILE_UNIT`，滚动条隐藏；`PlayerTileAreas._prepare_exposed_layouts()` 会在多组碰杠/鸡牌时向内换行并避开按钮、分数和中央区域。`GameTable` 中同名常量只保留兼容引用，调整数值请改配置文件。动画事件时序、真实桌面对照和当前 2D 限制见 [`docs/animation_review.md`](docs/animation_review.md)。

Android 固定使用横屏画布 `LANDSCAPE_SIZE`（2280×1280），Android 使用 `window/handheld/orientation=4`。窗口比例变化只缩放和留边，不切回竖屏；`_usable_rect()` 为安卓安全区域留边，切换尺寸会自动刷新牌面、弃牌区和操作按钮。布局测试覆盖 16:9、20:9、16:10、方屏和竖屏窗口的横屏画布边界；截图见 `docs/android_table_*.png` 和 `docs/android_result_*.png`。

`PlayerTileAreas._meld_tile_layout()` 同时控制牌桌和结算的杠牌排列，`_prepare_exposed_layouts()` 负责四向牌组避让；`SettlementCard._show_result()` 控制四家结算行，`_draw_result_details()`/`_draw_result_group()` 控制得分牌组。`scripts/core/ScoringEngine.gd` 中 `round_points` 是本人得分点，`pairwise[本人][对方]` 是实际收付；`group_chicken_items()` 合并同类同分牌，`_pay_kongs()` 分别处理通用鸡分和定向明杠基础4分。

运行 `tests/smoke_table_layout.gd` 可检查各座位从开局到四组碰杠的位置、放大后的牌面、鸡牌顺序与溢出布局。使用非 headless 模式还会生成 `docs/` 下的实际游戏截图，包括 `table_melds_0.png`（开局）、`table_melds_1.png`（一组碰牌）、`table_reference.png`（与参考图对应的碰→鸡→杠布局）。

## 十、UI 构成与修改指南

本项目的 UI 采用“场景只提供入口、脚本在运行时创建控件”的方式。修改界面时，优先查看对应脚本，而不是在 `.tscn` 里寻找不存在的按钮。三个入口场景只有一个根 `Control` 和一个脚本绑定：

| 界面 | 场景 | 脚本 | 主要职责 |
| --- | --- | --- | --- |
| 主菜单 | `scenes/MainMenu.tscn` | `scripts/ui/MainMenu.gd` | 单机、联机、声音、规则、更新、退出入口 |
| 联机大厅 | `scenes/Lobby.tscn` | `scripts/ui/Lobby.gd` | 局域网/在线切换、创建/搜索/加入、选座、换座、准备 |
| 牌桌 | `scenes/GameTable.tscn` | `scripts/ui/GameTable.gd` | 四方牌面、手牌、摸牌、碰杠、弃牌、操作按钮、结算 |

牌桌已采用组件组合：`GameTable.gd` 负责牌局、单机/联机事件和兼容入口，各区域持有自己的控件与显示状态。修改具体区域请进入 `scripts/ui/table/`：

| 文件 | 调整内容 |
| --- | --- |
| `TableUiConfig.gd` | 统一尺寸、字号、颜色、间距、安全边距和动画时长 |
| `TableLayout.gd` | 横屏缩放、安全区、四家坐标、手牌居中、背景与骰子 |
| `PlayerTileAreas.gd` | 手牌/摸牌、碰杠/鸡牌、弃牌、暗杠显示与牌组避让 |
| `TableActions.gd` | 点牌出牌、拖动防误触、开局输入锁、报听/碰/杠/胡按钮、操作区位置与提交 |
| `SettlementCard.gd` | 四家结算、牌组、三笔收付展示、卡片切换、下一局准备 |
| `TableAnimationController.gd` | 视觉事件去重、排队、回合重置与重连取消 |
| `TableWidgets.gd` | 共用牌、标签、容器和按钮样式创建 |

`TableComponent.gd` 用弱引用访问牌桌，退出时不会把牌桌留在内存中。`GameTable` 继承 `TableViewBridge.gd`，通过其中的属性和方法转发保留原 UI 接口，联机与测试仍按原方式调用；具体实现和状态位于上述组件，不需同时修改两个位置。`TableWidgets` 是无状态的控件工厂。规则、计分和权威提交仍由原核心与网络模块执行。

### 10.1 通用布局规则

- 三个界面都是全屏根 `Control`，脚本通过 `resized` 重新计算缩放和居中。
- 主菜单设计画布为 `MENU_SIZE = Vector2(1800, 1000)`；联机大厅为 `DESIGN = Vector2(1480, 860)`。
- 牌桌固定使用横屏设计画布 `LANDSCAPE_SIZE = Vector2(2280, 1280)`，窗口比例变化只缩放并留边，不切换为竖屏。Android 安全区域由 `GameTable._usable_rect()` 处理。
- 牌桌调色板、按钮圆角和字体入口在 `TableUiConfig.gd`，共用样式由 `TableWidgets._style()`/`_button()` 创建。主菜单和大厅仍使用各自的样式辅助函数。
- 牌面不是场景节点：`TileView` 在运行时创建，并使用 `BASE_W = 48`、`BASE_H = 64` 作为基础尺寸，再乘以 `unit`。

### 10.2 主菜单

`MainMenu.gd` 在 `content` 设计画布内创建左侧介绍区和右侧操作区。入口按钮使用 `ENTRY_BUTTON_SIZE = Vector2(760, 184)`，字号为 44；普通按钮默认约 `224×108`，字号为 28。需要调整主菜单整体大小时改 `MENU_SIZE`；调整“单机对局/联机房间”点击区域时改 `ENTRY_BUTTON_SIZE`；调整按钮位置直接改 `_ready()` 中对应的 `position`。

主菜单还会动态挂载 `SoundSettings`、`RuleGuide` 和 `UpdatePanel`。启动时 `UpdateManager.maybe_check()` 触发自动检查更新，更新面板由 `UpdatePanel.gd` 管理，不要在主菜单重复实现下载逻辑。

### 10.3 联机大厅

`Lobby.gd` 使用同一张 `1480×860` 横屏设计画布。浏览区由左侧创建面板和右侧房间列表组成；等待区由四个座位按钮、庄家意愿、准备按钮和换座请求行组成。

- 创建面板、房间列表和等待区的尺寸与位置在 `_ready()` 的 `_panel()`、`_field()`、`_button()` 调用中定义。
- 四个座位按钮的顺序是东、南、西、北，位置数组为 `locations`，当前点击区域约 `440×168`。
- 准备按钮当前约 `366×78`；`_render_waiting()` 负责同步昵称、房主、准备、断线和想当庄状态。
- `Lobby._layout()` 只负责将设计画布按窗口比例缩放居中。调整控件间距应修改设计坐标，通常不需要改缩放函数。

### 10.4 牌桌节点层级

`GameTable._build_static_ui()` 委托 `TableLayout` 创建画布，再由玩家牌区、操作区、结算和动画组件分别创建自己的节点。每个座位都有一个 `SeatRoot0..3`，座位根节点通过旋转映射到四个方向；其下的运行时容器如下：

| 变量 | 用途 | 调整入口 |
| --- | --- | --- |
| `hand_box[seat]` | 手牌，不含独立摸牌位 | `_refresh_seat()`、`_hand_layout()` |
| `draw_box[seat]` | 最右侧独立摸牌位/胡牌位 | `_hand_layout()`、`DRAW_GAP` |
| `meld_box[seat]` | 碰、明杠、暗杠、加杠 | `_meld_tile_layout()`、`_prepare_exposed_layouts()` |
| `chicken_box[seat]` | 打出的幺鸡/八筒，冲锋鸡横放 | `_exposed_groups()`、`_refresh_seat()` |
| `discard_scroll[seat]` | 普通弃牌区 | `_seat_metrics()`、`_refresh_discards()` |
| `wall_box[seat]` | 牌墙数据的旧显示容器，当前隐藏 | `_refresh_walls()` |
| `avatars/center_labels` | 风位、昵称/相对位置和当前分数 | `_refresh_seat()` |

牌桌中央的骰子、余牌和回合信息由 `_refresh_center()` 更新。牌桌不绘制牌墙，但牌墙仍由核心逻辑用于骰子、发牌和摸牌。

### 10.5 四方牌面和尺寸

四家显示先由 `TableLayout._relative_seat()` 转为“你、下家、对家、上家”，再使用 `ROTATIONS` 旋转座位根节点。`_seat_metrics()` 控制各方手牌基线、碰杠起点、弃牌区位置和容器大小；`_hand_layout()` 计算手牌与独立摸牌位的居中位置。以下常量都在 `TableUiConfig.gd`：

- `OWN_HAND_TILE_UNIT`：自己的手牌和摸牌，当前为 `2.40`。
- `OWN_PLAYER_TILE_UNIT`：自己的碰杠和鸡牌，当前为 `1.60`。
- `PLAYER_TILE_UNIT`：其他三家的手牌、碰杠和鸡牌，当前为 `1.35`。
- `TILE_UNIT`：弃牌牌面，当前为 `1.10`；放大弃牌区应改 `river_size`，不要改这个值。
- `RESULT_TILE_UNIT`：结算卡片中的牌，当前为 `1.60`。
- `TILE_GAP`、`EXPOSED_HAND_GAP`、`DRAW_GAP`：牌间距、碰杠与手牌间距、手牌与摸牌间距。

要放大自己的牌，优先只改 `OWN_HAND_TILE_UNIT`；要让所有操作按钮变大，改 `DISCARD_BUTTON_SIZE`，按钮由 `TableActions._add_action()` 统一创建。`_layout_actions()` 会把报听、碰、杠、胡、自摸等选择按钮放在摸牌位上方，并避开自己的弃牌区。`SIDE_RIVER_SIZE`/`MAIN_RIVER_SIZE` 调整弃牌容器，`RESULT_GRID_ORIGIN`/`RESULT_GRID_STRIDE`/`RESULT_ROW_SIZE` 调整结算行网格；`BUTTON_*` 常量调整按钮各状态颜色。

### 10.6 碰杠、冲锋鸡和弃牌区

`PlayerTileAreas._meld_tile_layout()` 同时服务牌桌和结算卡片。碰牌三张全部竖放且不标来源；明杠按来源横放一张（下家右横、上家左横、对家上横）；暗杠和加杠四张竖放。`_prepare_exposed_layouts()` 按实际矩形逐组寻找位置，空间不足时向内换行，并避开手牌、弃牌区、按钮、分数和中央区域。

`_refresh_discards()` 只把普通弃牌放进 `discard_scroll`；鸡牌会转入 `chicken_box`，冲锋鸡横放。东西两家弃牌区通过 `_seat_metrics().river_size` 扩大，滚动条设为 `SCROLL_MODE_SHOW_NEVER`，牌面大小仍由 `TILE_UNIT` 控制。

### 10.7 结算卡片

`SettlementCard._show_result()` 动态创建遮罩和卡片，卡片内四行按“你、上家、对家、下家”显示。每行由 `_draw_result_details()` 创建独立滚动区，`_draw_result_group()` 绘制牌组、分值和说明。鸡牌按同类型/同分值合并，杠牌集中在最后；`_result_sideways_index()` 复用玩家牌区的 `_meld_tile_layout()`，保证结算中的横牌方向与牌桌一致。

“查看结算/看牌桌”按钮位置由 `RESULT_TOGGLE_SIZE`、`_result_toggle_position()` 和 `panel_position_for_result_toggle()` 控制；下一局按钮由 `NEXT_ROUND_BUTTON_SIZE` 和 `_refresh_next_round_controls()` 控制。调整结算卡片整体大小时改 `_result_card_size()` 相关常量，同时检查每行 `ScrollContainer` 的宽高。

### 10.8 牌组件与弹窗

- `scripts/ui/TileView.gd`：单张牌的牌面、牌背、选中抬起、悬停和程序化绘制。替换牌素材或改变基础牌比例时从这里开始。
- `scripts/ui/SoundSettings.gd`：声音开关、音乐/语音/落桌音效滑块、AI 快中慢和退出房间二次确认。牌桌右上角的“设置”按钮打开它。
- `scripts/ui/RuleGuide.gd`：首次进入时的规则/教程分页。修改新手引导文字直接编辑 `PAGES`。
- `scripts/ui/UpdatePanel.gd`：版本检查、补丁下载、进度、重启和回滚，不负责游戏牌桌布局。
- `scripts/ui/TableAnimationLayer.gd`：临时牌节点与 Tween。`TableAnimationController` 管理事件队列、实际牌位、临时遮挡和取消恢复；`TableUiConfig` 中 `DICE_DURATION`/`DEAL_DURATION`/`DRAW_DURATION`/`DISCARD_DURATION`/`MELD_DURATION` 和 `ANIMATION_TILE_UNIT` 调整表现。牌局立即完成操作，视觉异步播放；重连取消旧动画，headless 跳过 Tween。

### 10.9 推荐的 UI 修改流程

1. 先改 `TableUiConfig.gd` 的一个常量，或对应组件的一处布局，避免同时改场景和运行时坐标。
2. 运行 `godot --headless --script res://tests/smoke_table_layout.gd` 检查四方牌组、横牌和溢出。
3. 运行 `godot --headless --script res://tests/smoke_ui.gd` 检查主菜单、联机入口、牌桌按钮和结算切换。
4. 有声音或弹窗改动时再运行 `smoke_audio.gd`；有大厅改动时运行 `smoke_lobby.gd`。
5. 用非 headless 运行一次，在 Windows 和 Android 横屏分别观察触控区域、文字是否被裁切、结算卡片滚动是否正常，再提交代码。

## 十一、声音与替换素材

素材说明及文件名见 `res/audio/README.md`。当前使用随工程打包的四套柔和普通话座位语音、Kevin MacLeod《Ripples》舒缓拨弦背景音乐和落桌音效，运行时全部离线播放。

- 背景音乐：`res/audio/music/table.wav`。
- 出牌语音：`res/audio/voice/wan1.wav` 至 `wan9.wav`、`tiao1.wav` 至 `tiao9.wav`、`tong1.wav` 至 `tong9.wav`。
- 碰 / 杠 / 报听 / 胡牌 / 自摸：`res/audio/voice/pong.wav`、`kong.wav`、`ready.wav`、`hu.wav`、`zimo.wav`。
- 落桌音效：`res/audio/effects/discard.wav`。

用自己的录音替换同名文件，回到 Godot 等待自动导入，然后重新运行即可。也支持同名 `.ogg` 或 `.mp3`，加载优先级为 OGG → WAV → MP3；同一名称建议只留一种格式。背景音乐会自动设置循环，牌名语音建议短于一秒以适配快档 AI。

`AudioManager.gd` 管理独立音轨、音乐压低、优先胡牌语音、动作语音保留和本地设置（`user://audio_settings.cfg`）；`RoundState.gd` 在合法出牌、碰、杠宣告、报听和胡牌时产生事件；`GameTable.gd` 在单机、主机、客户端均监听这些事件；`SoundSettings.gd` 提供开关和音量面板。联机声音使用现有可靠状态同步，每局独立编号，刷新与重连不会重复喊以前的牌。


### UI 截图检查与动效

本次逐页检查记录见 [docs/ui_review.md](docs/ui_review.md)；新增界面的统一尺寸、字体、颜色、动效和安全区规范见 [docs/ui_style_guide.md](docs/ui_style_guide.md)。主菜单、大厅、声音、规则、更新与退出弹窗共用 `UiStyle.gd` 的样式和安全区；`UiMotion.gd` 提供轻微按压、淡入与滑入，牌桌参数仍集中在 `table/TableUiConfig.gd`。牌桌支持骰子、顺时针分组发牌、摸牌、打牌、碰、明杠、暗杠、加杠、暗杠亮牌、报听、胡牌及自摸动效；最终胡牌张有呼吸高亮。动画速度在设置中选择。

动画只消费已完成的权威事件，其他人的摸牌始终显示牌背。普通快照不会打断动效，重连取消临时节点并跳过历史动作，客户端不依靠动画推进回合。`tests/ui_presentation.gd` 已加入快速 CI；`tests/capture_ui.gd` 和 `tests/capture_motion.gd` 在图形窗口中分别生成逐页截图与动效过程帧，输出在本地 `build/ui_review/`，不进入安装包。

### 开局动画与结算准备的调整入口

- `GameConfig.OPENING_DICE_SECONDS = 1.2`、`OPENING_DICE_HOLD_SECONDS = 0.5`、`OPENING_DEAL_SECONDS = 0.22`、`OPENING_DEAL_TILE_STAGGER = 0.035`、`OPENING_SORT_SECONDS = 0.34` 和 `OPENING_SORT_TILE_STAGGER = 0.012` 定义共享开局节奏。骰子、发牌和理牌不受每个客户端的动画速度影响，日常摸打仍可调快慢。
- 权威端先立即完成 52 张起手牌数据，保持 `DEALING`；UI 从空手牌开始，按三轮四张和最后单张逐组播放，全部落桌后用抛物线完成理牌。共同开局等待结束后才摸庄家的第 14 张并发出行动提示。动画回调不提交操作、不推进权威端。普通 headless 回归默认跳过等待，专用服务器保留真实等待。
- `TableActions._on_human_tile_gui()` 在短按松手时提交一次出牌，滑动超过阈值不出牌；所有提交入口都检查开局锁。原生触控和模拟鼠标不能重复提交。
- `SettlementCard` 的 `ReadinessFooter` 独立显示四人的昵称与准备状态、等待提示、大号准备/取消按钮。每个真人各自准备，人机默认准备；全部准备后仍由权威端等待 1 秒开始下一局。
- `tests/table_interaction.gd` 加入常规和 CI 快速检查；`tests/capture_table_controls.gd` 需真实窗口，保存本轮牌桌、结算、准备和骰子截图到 `build/ui_review/table_controls/`。





























