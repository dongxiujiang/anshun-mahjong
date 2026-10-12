# 正式安装包与更新发布教程

本次正式版本：**1.0.0**。发布仓库：[dongxiujiang/anshun-mahjong](https://github.com/dongxiujiang/anshun-mahjong)。图标已改为提供的图片，完整安装包包含两级更新功能。

## 一、替换已发布 V1.0.0 的附件

你已经发布了 [V1.0.0](https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.0.0)。旧附件的包内版本与清单仍是 1.2.0，现在本地文件已统一为 1.0.0。请按以下步骤修正现有 Release：

1. 打开 `build/releases/v1.0.0/`，这里是新文件；保留旧文件夹作备份。
2. 打开上面的 V1.0.0 发布页面，点击编辑按钮 **Edit**。保留标签 `V1.0.0`，标题可填 `安顺麻将 1.0.0 正式版`。
3. 删除旧的四个附件，重新上传下表同名的四个新文件。只替换附件，保留现有 Release 和标签。
4. 将新文件夹中 `发布说明.md` 的正文复制到说明框，保存 **Update release**，确保设为最新正式版本。
5. 四个附件全部替换完成后再通知玩家下载。`发布说明.md` 和 `发布教程.md` 无须作为附件上传。

已安装旧附件的玩家，需手动安装新完整版本一次。旧包内版本为 1.2.0，游戏不会自动降级到 1.0.0。安卓本次内部版本码已从 4 递增至 5，沿用同一正式签名，可以覆盖原正式版；无需卸载。Windows 可运行新安装向导覆盖安装。旧调试签名版本仍需先卸载，卸载会清除应用数据。

本地输出目录小写 `v1.0.0` 只是文件夹名称；GitHub 标签和下载地址必须为大写 `V1.0.0`。

需要替换的四个文件：

| 文件 | 用途 |
| --- | --- |
| `anshun-mahjong-setup-1.0.0.exe` | Windows 安装向导 |
| `anshun-mahjong-windows-x64.exe` | Windows 免安装主程序及游戏内完整更新 |
| `anshun-mahjong.apk` | Android 正式签名安装包 |
| `update-manifest.json` | 版本、下载地址和校验信息 |

标签和下载地址的大小写必须一致，附件名称与清单必须一致。Windows 主程序不能用安装向导替代。不要勾选 Pre-release，也不要只保存 Draft。

## 二、以后发布小版本：不重新安装

适用于已有脚本逻辑、UI、牌面、音频等兼容改动。

1. 修改代码或资源并完成测试。**不要改 `project.godot` 的安装基线版本、基线 ID、Autoload 或导出配置。**
2. 在项目根目录双击 **`生成小版本更新.cmd`**。
3. 输入新的版本号。第一次填 `1.0.1`，之后依次 `1.0.2`、`1.0.3`，不能重复已发布的版本。
4. 输入更新说明。工具会验证兼容性、生成累计补丁，完成后打开输出目录。
5. 新建 GitHub Release，标签与刚输入的版本一致，例如 `V1.0.1`。
6. 上传输出目录的这三个文件：

   - `update-manifest.json`
   - `anshun-mahjong-windows-1.0.1.pck`
   - `anshun-mahjong-android-1.0.1.pck`

7. 等待上传完成，不勾 Pre-release，设为最新并正式发布。
8. 在已安装的 `1.0.0` 游戏里点「检查更新」→「下载小版本补丁」→退出房间和对局→「重启应用生效」。无需安装 EXE/APK。

每次补丁都相对最初完整版本生成，玩家可以从 `1.0.0` 直接更新到 `1.0.3`。生成兼容检查失败时请看提示，不能把不兼容变化强行作为补丁发布。小版本发布不会修改安装包中的安卓版本码。

命令行也可执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\update\prepare_patch.ps1 -Version 1.0.1 -Notes "优化结算界面"
```

## 三、以后发布大版本：更新完整应用

引擎、图标、权限、启动引导、全局类注册、原生插件、导出配置变化，应发大版本。以 `2.0.0` 为例：

1. `project.godot`：把 `config/version` 改为 `2.0.0`，`updates` 的 `base_id` 改为新的唯一 ID，如 `2.0.0-boot1`。
2. `export_presets.cfg`：Windows 文件/产品版本改为 `2.0.0.0`；Android 的 `version/name` 改为 `2.0.0`，`version/code` 从本次的 `5` 递增为 `6`。保留正式签名密钥。
3. 用 Godot 导出 Windows 与 Android 的 **Release** 完整包。不要选 Debug。
4. 相同代码状态保存新的补丁基线，使用新目录，不能覆盖 `1.0.0-boot1`。
5. 用 `tools/update/prepare_release.py` 生成完整发布清单。
6. 如需 Windows 安装向导，用 NSIS 编译 `tools/release/setup.nsi`，传入 `/DReleaseVersion=2.0.0`。安装脚本还需要该版本目录中的 `用户说明.txt`。
7. 创建 `V2.0.0` 正式 Release，上传完整主程序、APK、清单和可选安装向导。旧安装版会显示完整应用更新，Android 由系统确认覆盖安装。

具体命令、补丁边界与故障恢复见 [updates.md](updates.md)。本机的 Python 可使用 `C:/Users/xiu/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`；Godot 为 `C:/Users/xiu/Desktop/Godot_v4.7.2-stable_win64.exe`。

## 四、必须保留的文件

- **热更新基线**：`build/update_baselines/1.0.0-boot1/`，包含两端基线 PCK、`baseline.json`。请单独备份；这是每次生成小补丁的依据。
- **安卓正式签名**：`C:/Users/xiu/.codex/mahjong-signing/`，包含密钥和本地凭据。完整备份到私人存储，不能上传到 GitHub 或发给玩家。后续 APK 必须继续使用此密钥。
- **项目源代码**：保留首次发布的代码状态，方便复现完整安装包。发布附件不要求公开签名凭据或开发工具。

本次只准备本地修正文件，未替换你已发布的 GitHub 附件。安卓签名、包内容已验证；当前没有连接手机，仍建议在手机实际安装、联机和重启更新后再面向所有玩家推广。
