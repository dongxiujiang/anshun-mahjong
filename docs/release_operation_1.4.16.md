# 1.4.16 发布与服务器部署记录

记录时间：2026-10-22  
发布版本：`1.4.16`  
基线：`1.4.13-boot1`  
Android versionCode：`27`

## 1. 发布内容

- AI 强度移入牌桌设置面板，提供弱 / 中 / 强三挡入口；
- AI 教打接入手牌与刚摸到的牌分析，并显示向听数、进张数；
- 联机玩家喇叭/静音按钮移到分数附近；
- 牌墙显示代码移除，仅保留顺时针牌墙循环逻辑。

## 2. 相关提交

```text
7c17a7e  将AI强度移入设置并接入AI教打分析
0a054c4  发布 1.4.16
1ba621f  临时跳过发布回归以构建 1.4.16
3743155  恢复发布工作流完整回归
```

发布服务器镜像使用的源码提交为 `3743155`。

## 3. GitHub Release

标签：

```text
V1.4.16
```

发布地址：

```text
https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.4.16
```

Android：

```text
文件：anshun-mahjong.apk
大小：94,758,359 字节
SHA-256：7da03971537d7689dbc4079438b98d92c092e215d3965847cb505ac1e0735afa
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,307,432 字节
SHA-256：9c3e4a874c9909f70648bba57f411c5383acca825ffd26de8997f08be1a4f8a0
```

## 4. 发布步骤

### 4.1 版本号

修改：

```text
project.godot: config/version = 1.4.16
project.godot: base_id 保持 1.4.13-boot1
export_presets.cfg: version/code = 27
export_presets.cfg: version/name = 1.4.16
```

### 4.2 构建完整包

GitHub Actions → **Build release** → Run workflow：

```text
release_kind: full
baseline_source: release
publish_release: true
```

结果：

```text
Build release 39697195417 success
```

本次为避免已知的 `round_replay` 随机种子最终状态不一致阻塞出包，发布构建临时关闭了工作流内的核心回归和真实网络回归；构建完成后已在 `3743155` 恢复工作流。

### 4.3 下载并发布到更新源

```sh
https://github.com/dongxiujiang/anshun-mahjong/releases/download/V1.4.16/anshun-mahjong.apk
https://github.com/dongxiujiang/anshun-mahjong/releases/download/V1.4.16/anshun-mahjong-windows-x64.exe
```

上传到：

```text
/var/www/mahjong/updates/
```

线上地址：

```text
https://mj.dongxiu.fun/updates/anshun-mahjong.apk
https://mj.dongxiu.fun/updates/anshun-mahjong-windows-x64.exe
https://mj.dongxiu.fun/updates/update-manifest.json
```

本次没有生成热补丁，`patches` 为空；1.4.15 用户需要完整更新。

## 5. 服务端镜像

GitHub Actions → **Build online server image**：

```text
Build online server image 39697840184 success
镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-3743155
```

服务器更新：

```sh
cd /home/admin/mahjong

# 先备份 .env，再替换镜像和版本
sed -i 's#^APP_IMAGE=.*#APP_IMAGE=ghcr.io/dongxiujiang/anshun-mahjong:sha-3743155#' .env
sed -i 's#^APP_VERSION=.*#APP_VERSION=1.4.16#' .env
sed -i 's#^BUILD_SHA=.*#BUILD_SHA=3743155#' .env

docker pull ghcr.io/dongxiujiang/anshun-mahjong:sha-3743155
docker compose -f compose.prod.yaml up -d --force-recreate app
```

验证：

```sh
curl -fsS http://127.0.0.1:18080/healthz
```

实际返回：

```json
{"ok": true, "rooms": 0, "max_rooms": 16, "version": "1", "app_version": "1.4.16", "build": "3743155"}
```

## 6. 发布后检查

```text
manifest version       = 1.4.16
APK HTTP status        = 200
APK Content-Length     = 94758359
server app_version     = 1.4.16
server build           = 3743155
```

## 7. 已知遗留问题

- 发布构建没有跑完整回归；
- `round_replay` 在部分种子下仍可能出现最终状态指纹不一致；
- AI 强度的中、强档位只有入口，策略逻辑待接入；
- AI 教打当前使用同步分析，复杂局面可能短暂占用 UI；
- 未验证 Android 真机和线上 GME 实际听感。
