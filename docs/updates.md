# 两级更新：自建源与 GitHub Releases

新完整 APK 默认使用自建 HTTPS 更新源，GitHub Releases 只作为旧版/备用发布渠道，不再作为手机端首选检查地址。完整的服务端从零部署、完整包与热补丁发布流程见 [deploy_release_update.md](deploy_release_update.md)；本次实操命令见 [self_hosted_update_operation.md](self_hosted_update_operation.md)。

## 自建 HTTPS 更新源（新完整 APK）

新 APK 在 `project.godot` 中内置：

```ini
[updates]
manifest_url=""
manifest_urls=[
"https://mj.dongxiu.fun/updates/update-manifest.json",
"https://mj.dongxiu.fun/updates/update-manifest-fallback.json"
]
```

两份清单内容相同，前者失败时客户端自动尝试后者；两者都指向同一个自建域名，不使用 GitHub 或 Gitee。

`manifest_urls` 为空时才走旧的 `manifest_url` / GitHub Releases 逻辑，因此新 APK 的检查更新不会先访问 `api.github.com`。

### 1.1.9 及更早版本

旧版更新器仍然请求 GitHub API。因为热更新的第一步就是读取清单，旧版无法通过热更新把自己切换到自建源；必须先安装一次新完整 APK，之后才能走自建源热更新。

### 发布补丁

先生成补丁目录（沿用现有基线流程）：

```powershell
python tools/update/prepare_hot_update.py patch `
  --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe" `
  --baseline build/update_baselines/1.0.0-boot1 `
  --version 1.1.10 --notes "优化手机端热更新"
```

然后把补丁推到指定域名：

```powershell
python tools/update/publish_self_hosted.py `
  --release build/releases/v1.1.10 `
  --domain mj.dongxiu.fun `
  --ssh admin@47.108.185.96 `
  --remote-dir /var/www/mahjong/updates
```

脚本会：

- 把清单里的 GitHub 下载地址改写成 `https://<域名>/updates/<文件名>`；
- 生成 `update-manifest.json` 和 `update-manifest-fallback.json`；
- 把 PCK/APK 和两份清单先上传为临时文件，再原子替换到服务器目录。

不指定 `--ssh` 时只在本地生成暂存目录：

```text
build/self-hosted/<域名>/
```

可以先用 `--dry-run` 查看命令，不上传。

### 服务器目录

Nginx 需要把 `/updates/` 映射到实际目录，完整配置见 [README](../README.md) 的 Docker 部署 3.1.6：

```nginx
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
```

首次准备：

```sh
sudo mkdir -p /var/www/mahjong/updates
sudo chown admin:admin /var/www/mahjong/updates
```

发布后验证：

```sh
curl -fsS https://mj.dongxiu.fun/updates/update-manifest.json
curl -fsS https://mj.dongxiu.fun/updates/update-manifest-fallback.json
```

### 完整 APK

新完整 APK 必须包含上面的 `manifest_urls`，并沿用正式签名、递增 Android `version/code`。1.1.9 用户安装这一次完整包后，后续小版本才从 `mj.dongxiu.fun` 热更新。

## 玩家体验

- 小版本：游戏内下载脚本、界面、牌面、音乐和语音补丁，退出房间和对局后点「重启应用生效」。Windows 和 Android 均不需要重新安装。
- 大版本：Windows 下载校验后替换完整 EXE，保留旧程序备份；Android 下载完整 APK，由系统确认覆盖安装，必须保持相同签名。
- 小版本失败：下载校验失败继续运行当前版；新补丁未正常进入主菜单时，下一次启动自动恢复旧版，启动看门狗也会在 20 秒后尝试重启回退。
- 已运行成功的补丁仍可点「恢复上一小版本」手动回退。保留当前与上一成功补丁，清理更早的补丁。
- 已保存的声音、网络设置保留。当前对局和会话分数不跨重启保存，需先结束对局。

**已安装的旧包需要先更新一次完整应用，获得 PatchBoot 启动器，后续才能用小版本热更新。1.0.0 正式安装包已生成于 `build/releases/v1.0.0/`，对应已发布的 `V1.0.0` 标签，重新上传修正后的四个附件。图形界面操作教程见 [publishing.md](publishing.md)。**

## 版本与兼容范围

主版本号不同，例如 `1.x.x → 2.0.0`，走完整应用更新。同一主版本号的小版本，只有安装基线 ID、基线版本、Godot 引擎版本与平台一致才加载补丁；不兼容时前往完整安装包发布页。

当前安装版本 `1.0.0`，基线 ID 为 `1.0.0-boot1`。GitHub 标签前缀配置为 `updates/tag_prefix="V"`，发布标签用 `V1.0.0`，清单 version 用数字 `1.0.0`；更新检查兼容 v/V，下载地址保持标签的实际大小写。安装基线版本保持不变，小版本实际版本从已启用的补丁元数据读取，例如 `1.0.2`。小版本发布工具的 `--version` 指定有效游戏版本，无须修改安卓版本码。

可热更新：已有脚本逻辑、场景、UI、音效和纹理，以及通过路径加载的新普通资源。

以下变化需完整更新：引擎、原生插件、安卓权限、启动配置、Autoload 注册、PatchBoot 本身、全局 `class_name` 注册/继承/UID、导出格式或平台设置。发布工具会拒绝这些不兼容变化。删除安装基线已有文件也需大版本；普通补丁请保留旧文件。

每次大版本修改主版本号、`updates/base_id`、Windows 文件版本及 Android 的 `version/name` / 递增 `version/code`，建立新的独立基线。不要覆盖旧基线目录。

## 第一次安装：保存基线

同一次工程状态先完成测试，再保存平台基线，并导出完整 EXE/APK。基线必须与安装包的代码、资源和导出选项一致，永久保存 `baseline.json` 与两个 PCK。这些基线文件用于开发者生成差分补丁，无须上传给玩家。

```powershell
python tools/update/prepare_hot_update.py baseline --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe" --output build/update_baselines/1.0.0-boot1
```

基线输出：`windows-base.pck`、`android-base.pck`、`baseline.json`。导出完整 EXE/APK 后运行：

```powershell
python tools/update/prepare_release.py
```

将 `build/releases/v1.0.0/` 中的 `update-manifest.json`、`anshun-mahjong-windows-x64.exe`、`anshun-mahjong.apk` 上传到正式、非 Draft、非 Pre-release 的 `V1.0.0` Release。工具只准备本地文件，不上传、不发布。务必使用从相同代码导出的安装包。

## 小版本发布

改游戏代码或资源后，完成测试，导出累计差分补丁：

```powershell
python tools/update/prepare_hot_update.py patch --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe" --baseline build/update_baselines/1.0.0-boot1 --version 1.0.2 --notes "优化手牌与结算界面"
```

将 `build/releases/v1.0.2/` 中的以下三个文件上传到正式 `V1.0.2` Release：

- `update-manifest.json`
- `anshun-mahjong-windows-1.0.2.pck`
- `anshun-mahjong-android-1.0.2.pck`

网址、SHA-256、大小与兼容信息自动生成。两个平台独立导出，避免 Windows/Android 导入纹理不兼容。补丁始终相对完整安装基线生成，玩家可从 `1.0.0` 直接到 `1.0.2`，不用先装 `1.0.1`。

小版本发布默认只携带补丁；首次安装或不兼容安装者可前往清单中的 `installation_url` 下载基线完整版本，再下载最新小补丁。需要为新玩家提供最新完整包时，可导出同版本完整包，并把两个文件及其 SHA-256、大小、下载 URL 补入清单的 `packages` 字段。

## 清单示例

```json
{
  "schema": 2,
  "version": "1.0.2",
  "notes": "优化牌桌布局",
  "release_url": "https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.0.2",
  "installation_url": "https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.0.0",
  "packages": {},
  "patches": {
    "windows": {
      "url": "https://github.com/dongxiujiang/anshun-mahjong/releases/download/V1.0.2/anshun-mahjong-windows-1.0.2.pck",
      "sha256": "由发布工具生成的64位摘要",
      "size": 123456,
      "platform": "windows",
      "base_id": "1.0.0-boot1",
      "base_version": "1.0.0",
      "engine": "4.7.2"
    }
  }
}
```

游戏先读 Releases latest API，再下载该 Release 的 `update-manifest.json`，检查版本与发布标签是否一致。摘要来自清单，清单走 HTTPS；GitHub 资产提供摘要时额外验证清单。代码补丁必须有 SHA-256 和大小，不满足则拒绝下载。未发布正式 Release 显示“暂未发布正式更新”。旧版无清单的完整 EXE/APK Release 仍兼容。

`updates/manifest_url` 可直接指定 HTTPS 静态 JSON，用于其他公开托管来源，默认留空使用 GitHub。HTTP 仅允许工程测试的本机回环地址，安装版不允许。

## 启动与存储

`PatchBoot.gd` 是第一个 Autoload，必须在 `_init()` 挂载 PCK，其他 Autoload 与主菜单才能加载新脚本；在 `_ready()` 挂载会太晚。新补丁下载后不会在当前对局替换缓存，重启才生效。

状态与补丁在 `user://updates/patch-state.json` 和 `user://updates/packs/`，原子保存状态并保留写入中断时的备份。试运行补丁进入主菜单、解析核心游戏脚本并检查必需 Autoload 后才确认成功。失败回退不修改 EXE/APK。

## 验证

```powershell
godot --headless --path . --script res://tests/smoke_update.gd
godot --headless --path . --script res://tests/smoke_hot_update.gd
python tests/run_update.py --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe"
python tests/run_hot_update.py --godot "C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe"
godot --headless --path . --script res://tests/run_all.gd
```

集成测试只替换 `build/` 中的临时程序、使用独立测试应用数据目录。已覆盖真实 HTTP 清单与 PCK 下载、校验失败、取消、Windows 替换/回退、首次 Autoload 与已有全局类的编译脚本更新、跨小版本更新、试运行失败回退、状态写入中断恢复。安卓补丁分支与平台导出已验证；安卓实际设备重启和安装仍需真机验证。
