# 自建热更新实操教程（Nginx + 自建源）

本文记录一次实际发布流程：从 GitHub Actions 完整包，到 `mj.dongxiu.fun/updates/` 上线，再到 1.1.9 安装过渡包。

通用规则和从零部署见 [deploy_release_update.md](deploy_release_update.md)。

## 0. 本次目标与结果

目标：

- 服务端已更新到新镜像；
- 新完整 APK 内置自建更新源；
- 1.1.9 用户安装一次完整 APK；
- 以后只发 PCK 热补丁；
- 更新文件不依赖 GitHub API。

本次结果：

```text
主清单：https://mj.dongxiu.fun/updates/update-manifest.json        200
回退：  https://mj.dongxiu.fun/updates/update-manifest-fallback.json 200
APK：   https://mj.dongxiu.fun/updates/anshun-mahjong.apk           200，65,537,498 字节
SHA-256：60bfe0a767c0cfaa474d1dba55ff031d7cb5cdd6a87d8438e9e610c79d296a59
```

## 1. 获取完整包

### 1.1 不要直接下 222MB Actions artifact

`full-release-*` 通常包含 Windows EXE、Android APK 和清单，体积约 200MB 以上；Actions artifact 下载慢，且不能直接使用 `ghproxy`。

如果只需要 Android APK，用仓库里的：

```text
Actions → Promote full release artifact → Run workflow
```

填写：

```text
run_id = 39136889832
artifact_name = full-release-39136889832
baseline_artifact = baseline
tag = V1.0.0-bridge-39136889832
```

它会在 GitHub 内部下载 artifact，并发布成 Release 资产：

```text
anshun-mahjong.apk
update-manifest.json
baseline.zip
```

然后从 Release 下载：

```text
https://github.com/dongxiujiang/anshun-mahjong/releases/download/<tag>/anshun-mahjong.apk
https://github.com/dongxiujiang/anshun-mahjong/releases/download/<tag>/baseline.zip
```

国内加速：

```text
https://ghproxy.net/https://github.com/dongxiujiang/anshun-mahjong/releases/download/<tag>/anshun-mahjong.apk
```

### 1.2 解压后的目录

本次解压到：

```text
C:\Users\xiu\Desktop\version\
  anshun-mahjong.apk
  update-manifest.json
  baseline.zip
  baseline-artifact\
    baseline.json
    android-base.pck
    windows-base.pck
```

`baseline-artifact` 已经是完整基线，不需要再解压 `baseline.zip`。

## 2. 配置 SSH 免密

发布脚本会多次调用 `ssh`/`scp`，必须免密。

### 2.1 本机生成密钥

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\mahjong_deploy" -C "mahjong-deploy"
Get-Content "$env:USERPROFILE\.ssh\mahjong_deploy.pub"
```

复制输出的整行公钥。

### 2.2 在服务器添加公钥

通过阿里云 Workbench 登录。如果当前是 `root`：

```sh
sudo -u admin mkdir -p /home/admin/.ssh
echo '把公钥整行粘贴到这里' | sudo tee -a /home/admin/.ssh/authorized_keys

sudo chown -R admin:admin /home/admin/.ssh
sudo chmod 700 /home/admin/.ssh
sudo chmod 600 /home/admin/.ssh/authorized_keys
```

如果 Workbench 当前就是 `admin`：

```sh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo '把公钥整行粘贴到这里' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

不要覆盖已有的 `authorized_keys`，用追加。

### 2.3 本机配置

```powershell
notepad "$env:USERPROFILE\.ssh\config"
```

```text
Host 47.108.185.96
    HostName 47.108.185.96
    User admin
    IdentityFile C:/Users/xiu/.ssh/mahjong_deploy
    IdentitiesOnly yes
```

测试：

```powershell
ssh admin@47.108.185.96 "echo config-ok"
```

输出 `config-ok` 才算成功。若仍提示密码，`config` 没保存或路径不对：

```powershell
ssh -G admin@47.108.185.96 | Select-String identityfile
```

### 2.4 常见 SSH 问题

| 现象 | 处理 |
|---|---|
| `Permission denied (publickey,password)` | 先用 `-i` 测试密钥；再修 `config` |
| 一直要求密码 | `config` 没保存，或 `IdentityFile` 路径错 |
| 公钥添加后仍失败 | `/home/admin` 权限、`.ssh` 700、`authorized_keys` 600 |
| Workbench 是 root | 写到 `/home/admin/.ssh`，并 chown 给 admin |

## 3. 准备 release 目录

### 3.1 只保留 Android

清单里的 `packages.windows` 指向 122MB EXE。只发 Android 时把它删掉：

```powershell
$src = "C:\Users\xiu\Desktop\version"
$out = "C:\Users\xiu\Desktop\Mahjong-Godot\build\releases\v1.0.0"

New-Item -ItemType Directory -Force $out | Out-Null
Copy-Item "$src\anshun-mahjong.apk" $out -Force

$j = Get-Content "$src\update-manifest.json" -Raw | ConvertFrom-Json
$j.packages.PSObject.Properties.Remove("windows")
$j | ConvertTo-Json -Depth 10 | Set-Content "$out\update-manifest.json" -Encoding UTF8
```

检查：

```powershell
Get-Content "$out\update-manifest.json"
```

应该只剩：

```json
"packages": {
  "android": {
    "url": "...anshun-mahjong.apk",
    "size": 65537498
  }
}
```

如果 Windows 也要自建更新，不要删 `windows`，并且必须把 `anshun-mahjong-windows-x64.exe` 放进同一个 release 目录。

### 3.2 清理多余 EXE

完整包目录里可能还留有：

```text
anshun-mahjong-setup-1.0.0.exe
anshun-mahjong-windows-x64.exe
```

移动端不需要，先删掉，避免脚本把 100MB 多文件一起上传：

```powershell
Remove-Item "$out\*.exe" -Force
Remove-Item "C:\Users\xiu\Desktop\Mahjong-Godot\build\self-hosted" -Recurse -Force -ErrorAction SilentlyContinue
```

最终目录只保留：

```text
build\releases\v1.0.0\
  anshun-mahjong.apk
  update-manifest.json
```

### 3.3 保存 baseline

```powershell
$baseline = "C:\Users\xiu\Desktop\Mahjong-Godot\build\update_baselines\1.0.0-boot1"
New-Item -ItemType Directory -Force $baseline | Out-Null
Copy-Item "C:\Users\xiu\Desktop\version\baseline-artifact\*" $baseline -Recurse -Force
```

检查：

```powershell
Get-Content "$baseline\baseline.json" | Select-Object -First 5
```

应看到：

```json
"base_version": "1.0.0",
"base_id": "1.0.0-boot1"
```

以后打补丁使用这个目录。

## 4. Nginx /updates

如果尚未配置，创建 snippet：

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

不要覆盖 Certbot 的 SSL 配置。

## 5. 发布

先 dry-run 看资源列表：

```powershell
cd C:\Users\xiu\Desktop\Mahjong-Godot

& "C:\Users\xiu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" `
  tools\update\publish_self_hosted.py `
  --release "C:\Users\xiu\Desktop\Mahjong-Godot\build\releases\v1.0.0" `
  --domain mj.dongxiu.fun --dry-run
```

正式发布：

```powershell
& "C:\Users\xiu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" `
  tools\update\publish_self_hosted.py `
  --release "C:\Users\xiu\Desktop\Mahjong-Godot\build\releases\v1.0.0" `
  --domain mj.dongxiu.fun `
  --ssh admin@47.108.185.96 `
  --remote-dir /var/www/mahjong/updates
```

如果 `python` 已在 PATH，可直接用 `python` 替换路径。

成功输出类似：

```text
本地暂存: ...\build\self-hosted\mj.dongxiu.fun
清单: https://mj.dongxiu.fun/updates/update-manifest.json
回退: https://mj.dongxiu.fun/updates/update-manifest-fallback.json
资源: https://mj.dongxiu.fun/updates/anshun-mahjong.apk
已推送 3 个文件到 admin@47.108.185.96:/var/www/mahjong/updates
```

## 6. 验证

Windows PowerShell 使用 `curl.exe`：

```powershell
curl.exe -fsS https://mj.dongxiu.fun/updates/update-manifest.json
curl.exe -I https://mj.dongxiu.fun/updates/update-manifest-fallback.json
curl.exe -I https://mj.dongxiu.fun/updates/anshun-mahjong.apk
```

期望：

- 清单返回 200；
- 回退清单返回 200；
- APK 返回 200，`Content-Type: application/vnd.android.package-archive`；
- APK `Content-Length` 与清单 `size` 一致；
- SHA-256 与清单一致。

清单中的 Android URL 应是：

```json
"url": "https://mj.dongxiu.fun/updates/anshun-mahjong.apk"
```

## 7. 安装到 1.1.9

APK 下载：

```text
https://mj.dongxiu.fun/updates/anshun-mahjong.apk
```

安装前检查已安装版本：

```sh
adb shell dumpsys package com.anshun.mahjong | grep versionCode
```

当前完整包是：

```text
version/code = 5
version/name = 1.0.0
```

如果手机 1.1.9 的 versionCode 大于 5，会报：

```text
INSTALL_FAILED_VERSION_DOWNGRADE
```

处理：

1. 修改 `export_presets.cfg` 的 `version/code`，大于手机现有值；
2. 提交并重新打 `full`；
3. 重新发布 APK。

安装成功后：

- 更新源会读取 `https://mj.dongxiu.fun/updates/update-manifest.json`；
- 后续补丁只下载 PCK；
- 当前清单版本 1.0.0，后续发布 1.1.x 补丁后会提示更新。

## 8. 后续小版本

生成补丁：

```powershell
python tools\update\prepare_hot_update.py patch `
  --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe" `
  --baseline "C:\Users\xiu\Desktop\Mahjong-Godot\build\update_baselines\1.0.0-boot1" `
  --version 1.1.10 `
  --notes "优化结算显示"
```

把完整 APK 放进补丁目录是可选的：

```powershell
Copy-Item "C:\Users\xiu\Desktop\version\anshun-mahjong.apk" `
  "C:\Users\xiu\Desktop\Mahjong-Godot\build\releases\v1.1.10\anshun-mahjong.apk" -Force
```

发布补丁：

```powershell
& "C:\Users\xiu\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" `
  tools\update\publish_self_hosted.py `
  --release "C:\Users\xiu\Desktop\Mahjong-Godot\build\releases\v1.1.10" `
  --domain mj.dongxiu.fun `
  --ssh admin@47.108.185.96 `
  --remote-dir /var/www/mahjong/updates
```

注意：

- 补丁清单版本必须高于客户端当前版本；
- 不要把 full 1.0.0 的清单覆盖到已经发布的 1.1.x 清单上；
- 保留上一份 PCK 和清单用于回滚；
- 服务端镜像只在服务端代码变化时重建。

## 9. 排障

| 现象 | 原因 | 处理 |
|---|---|---|
| `python` 不是命令 | Python 不在 PATH | 用上面的绝对路径 |
| SSH 要求密码 | `~/.ssh/config` 未保存 | 检查 `ssh -G` 的 `identityfile` |
| `Permission denied (publickey,password)` | 公钥未加到 admin | 通过 Workbench 写入 `/home/admin/.ssh/authorized_keys` |
| 发布脚本上传了 EXE | release 目录有旧 EXE | 删除 `*.exe`，清空 `build/self-hosted` |
| `/updates/` 404 | Nginx include 未生效 | `nginx -T \| grep updates`，重载 |
| `/updates/` 403 | 目录/文件权限不对 | 目录 755，文件 644 |
| APK 装不上 | versionCode 降级或签名不同 | 提高 code，沿用正式签名 |
| 客户端显示已是最新 | 清单 version 不高于当前版本 | 发布更高版本补丁，确认清单已替换 |
| 下载校验失败 | 文件不完整或清单 SHA 不匹配 | 重新上传并核对 SHA-256 |

## 10. 本次完成状态

- 服务端 app 已更新并健康；
- Nginx `/updates/` 已配置；
- 主清单、回退清单、APK 均返回 200；
- APK SHA-256 与清单一致；
- baseline 已保存；
- 待完成：1.1.9 安装完整 APK，确认 versionCode 和在线对局。
