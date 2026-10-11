# 正式安装包与更新发布教程

本次正式版本：**1.2.0**。发布仓库：[dongxiujiang/anshun-mahjong](https://github.com/dongxiujiang/anshun-mahjong)。图标已改为提供的图片，完整安装包包含两级更新功能。

## 一、首次发布正式安装包

1. 打开项目目录中的 `build/releases/v1.2.0/`。
2. 浏览器登录你的 GitHub，打开 [新建 Release 页面](https://github.com/dongxiujiang/anshun-mahjong/releases/new)。
3. 在 **Choose a tag** 输入 `v1.2.0`，选择创建这个标签。Release 标题填写 `安顺麻将 1.2.0 正式版`。
4. 将本地 `发布说明.md` 的内容复制到说明框。
5. 将下面四个文件拖到上传区域，等待每个文件上传完成：

   | 文件 | 用途 |
   | --- | --- |
   | `anshun-mahjong-setup-1.2.0.exe` | Windows 安装向导，安装后有桌面快捷方式 |
   | `anshun-mahjong-windows-x64.exe` | Windows 免安装主程序，游戏内完整更新也使用这个文件 |
   | `anshun-mahjong.apk` | Android 正式签名安装包 |
   | `update-manifest.json` | 游戏读取的版本、下载地址和校验信息 |

6. **不要勾选 Pre-release**；选择设为最新 Release（Make latest），点击 **Publish release**。不要只保存 Draft。
7. 打开 [Releases 页面](https://github.com/dongxiujiang/anshun-mahjong/releases)，确认四个附件均能下载。
8. 玩家首次安装这次的完整版本。之后在主菜单「检查更新」即可发现后续更新。

**不能改上传附件的名字，也不能把 `v1.2.0` 换成别的版本号。** 清单中的下载地址已经指向这些文件名和标签。Windows 主程序不能用安装向导替代，否则自动替换后无法直接启动游戏。

APK 使用新的正式发布密钥。已经安装旧调试版的手机，首次改用正式版需要卸载旧版，旧版设置与数据会随卸载清除。后续正式 APK 使用同一发布密钥，可以覆盖安装。Windows 安装版与免安装版都保留游戏内更新能力。

## 二、以后发布小版本：不重新安装

适用于已有脚本逻辑、UI、牌面、音频等兼容改动。

1. 修改代码或资源并完成测试。**不要改 `project.godot` 的安装基线版本、基线 ID、Autoload 或导出配置。**
2. 在项目根目录双击 **`生成小版本更新.cmd`**。
3. 输入新的版本号。第一次填 `1.2.1`，之后依次 `1.2.2`、`1.2.3`，不能重复已发布的版本。
4. 输入更新说明。工具会验证兼容性、生成累计补丁，完成后打开输出目录。
5. 新建 GitHub Release，标签与刚输入的版本一致，例如 `v1.2.1`。
6. 上传输出目录的这三个文件：

   - `update-manifest.json`
   - `anshun-mahjong-windows-1.2.1.pck`
   - `anshun-mahjong-android-1.2.1.pck`

7. 等待上传完成，不勾 Pre-release，设为最新并正式发布。
8. 在已安装的 `1.2.0` 游戏里点「检查更新」→「下载小版本补丁」→退出房间和对局→「重启应用生效」。无需安装 EXE/APK。

每次补丁都相对最初完整版本生成，玩家可以从 `1.2.0` 直接更新到 `1.2.3`。生成兼容检查失败时请看提示，不能把不兼容变化强行作为补丁发布。小版本发布不会修改安装包中的安卓版本码。

命令行也可执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update\prepare_patch.ps1 -Version 1.2.1 -Notes "优化结算界面"
```

## 三、以后发布大版本：更新完整应用

引擎、图标、权限、启动引导、全局类注册、原生插件、导出配置变化，应发大版本。以 `2.0.0` 为例：

1. `project.godot`：把 `config/version` 改为 `2.0.0`，`updates` 的 `base_id` 改为新的唯一 ID，如 `2.0.0-boot1`。
2. `export_presets.cfg`：Windows 文件/产品版本改为 `2.0.0.0`；Android 的 `version/name` 改为 `2.0.0`，`version/code` 从本次的 `4` 递增为 `5`。保留正式签名密钥。
3. 用 Godot 导出 Windows 与 Android 的 **Release** 完整包。不要选 Debug。
4. 相同代码状态保存新的补丁基线，使用新目录，不能覆盖 `1.2.0-boot1`。
5. 用 `tools/update/prepare_release.py` 生成完整发布清单。
6. 如需 Windows 安装向导，用 NSIS 编译 `tools/release/setup.nsi`，传入 `/DReleaseVersion=2.0.0`。安装脚本还需要该版本目录中的 `用户说明.txt`。
7. 创建 `v2.0.0` 正式 Release，上传完整主程序、APK、清单和可选安装向导。旧安装版会显示完整应用更新，Android 由系统确认覆盖安装。

具体命令、补丁边界与故障恢复见 [updates.md](updates.md)。本机的 Python 可使用 `C:/Users/xiu/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`；Godot 为 `C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe`。

## 四、必须保留的文件

- **热更新基线**：`build/update_baselines/1.2.0-boot1/`，包含两端基线 PCK、`baseline.json`。请单独备份；这是每次生成小补丁的依据。
- **安卓正式签名**：`C:/Users/xiu/.codex/mahjong-signing/`，包含密钥和本地凭据。完整备份到私人存储，不能上传到 GitHub 或发给玩家。后续 APK 必须继续使用此密钥。
- **项目源代码**：保留首次发布的代码状态，方便复现完整安装包。发布附件不要求公开签名凭据或开发工具。

本次只准备本地文件，未上传或发布到 GitHub。安卓签名、包内容已验证；当前没有连接手机，仍建议在手机实际安装、联机和重启更新后再面向所有玩家推广。
