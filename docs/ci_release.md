# GitHub Actions 构建与热更新

## 自动测试门禁

`.github/workflows/ci.yml` 会在 `main`/`master` 推送和 Pull Request 上运行快速检查，覆盖规则、结算、语音、合法操作、同步、重连控制、牌桌组件隔离与退出生命周期和 4 局 AI 自战，并执行 Python 导出配置测试。快速检查失败时，提交不会通过 CI。

`.github/workflows/build-release.yml` 在完整构建或 `V1.0.*` 标签构建时运行发布前回归：自动执行 `tests/run_all.gd` 注册的完整测试清单，强制进行至少 50 局真实 AI 自战，并启动多进程局域网、在线房间和断线重连测试。网络和重连回归失败时不会进入签名、导出或发布步骤。

测试日志会保存为 Actions artifact：普通提交使用 `quick-check-logs-*`，发布构建使用 `ci-logs-*`。其中包含每个 Godot 套件的标准输出和错误日志，不包含签名文件或密码。

## 云端发布前的本地检查

Windows 上可以先双击项目根目录的 `本地build-release检查.cmd`。它会使用与云端相同的 Godot 4.7.2，依次执行工程导入、Python 导出配置检查、完整 Godot 回归（AI 50 局）、网络/联机/断线重连回归，并把每一步日志保存到 `build/local-build-release/<时间>/`。任一步失败都会显示错误并以非零状态结束，此时不要运行云端 Build release。

命令行运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\release\local_build_release.ps1 -Mode Check
```

需要同时在本地导出 Windows 和 Android 完整包时运行 `-Mode Full`；这要求本机已有 Godot 导出模板、Android SDK、Java、正式签名凭据和 `apksigner`。生成的文件只放在本次日志目录，不会上传或发布：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\release\local_build_release.ps1 -Mode Full -Notes "本次发布说明"
```

生成热更新补丁时运行 `-Mode Patch -PatchVersion 1.0.5`；默认使用 `build/update_baselines/<base_id>/` 基线，也可以用 `-BaselinePath` 指定其他基线。网络环境暂时不可用时可以加 `-SkipNetwork`，但正式云端构建前应补跑完整检查。所有命令都支持 `-GodotPath` 指定本地 Godot 路径。

工作流文件是 `.github/workflows/build-release.yml`。它会先完成测试和构建，再按 `publish_release` 选项自动创建 GitHub Release 并上传附件；不开启时只上传 Actions artifact，不会修改项目版本号。首次完整构建同时保存 `baseline`，供同一安装基线的小版本热补丁使用。

## 必需的 Secrets

正式 Android 包必须继续使用第一次发布的同一签名。仓库需要配置以下 Actions Secrets：

- `ANDROID_KEYSTORE_BASE64`：正式 `.keystore` 文件的 Base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码。
- `ANDROID_KEYSTORE_USER`：签名 alias。

缺少任意一个 Secret 时，Android job 会失败，不会生成可误发布的未签名包。私钥、密码和导出的 credentials 不会上传 artifact。

## 手动构建

在 GitHub 的 **Actions → Build release** 选择 **Run workflow**：

- `release_kind=full`：构建 Windows EXE、Android APK、完整发布清单，并上传当前代码的补丁基线 artifact。只有完整构建会读取三个签名 Secret。
- `release_kind=patch`：填写 `patch_version`（例如 `1.0.5`）。现有 `V1.0.0` 玩家请选择 `baseline_source=release`、`baseline_release_tag=V1.0.0`；与某次完整构建配套的新安装包请选择 `baseline_source=artifact` 并填写 `baseline_run_id`。工作流会运行兼容性检查并生成 Windows/Android PCK 补丁和清单；补丁不重新构建或签名 APK。
- `publish_release=true`：构建通过后自动创建 `V1.0.x` Release 并上传生成的文件；`false` 只生成并保存 artifact，适合先审核。`release_notes` 可填写 Release 说明。

首次 `1.0.0` 构建使用 `full`。之后的 `1.0.x` 小版本使用 `patch`，并把对应完整构建的 Actions run id 填入 `baseline_run_id`。基线 artifact 目前保留 90 天，下载后请单独备份；不能用新版本覆盖。工作流只允许同一主版本的补丁；引擎、Autoload、导出设置、原生插件或安装基线变化时，应构建新的完整大版本。

你已经发布的 `V1.0.0` 有一份本地原始基线 `build/update_baselines/1.0.0-boot1/`。首次在 Actions 点击 `full` 只能验证当前代码的完整构建，不能把它生成的新基线直接当成旧 `V1.0.0` 玩家可用的基线，也不要自动替换已发布附件。给现有 `V1.0.0` 玩家生成小补丁时，继续使用项目中备份的原始基线和根目录的 `生成小版本更新.cmd`；Actions 基线适用于与它对应的那次完整安装包。

工作流只上传必要的安装包、PCK、清单和不含签名凭据的检查日志；临时 keystore 与 `.godot/export_credentials.cfg` 会在任务结束时删除。

## 让现有 V1.0.0 基线也能由 Actions 使用

首次需要手动把项目中的以下三个文件上传到 GitHub 的 `V1.0.0` Release，文件名必须完全一致：

- `build/update_baselines/1.0.0-boot1/baseline.json`
- `build/update_baselines/1.0.0-boot1/windows-base.pck`
- `build/update_baselines/1.0.0-boot1/android-base.pck`

它们是校验基线，不是玩家下载的安装包。上传后，运行 `patch` 时选择 `baseline_source=release`、标签 `V1.0.0`，并填写下一个未发布版本（目前应为 `1.0.5`）。先用 `publish_release=false` 验证；确认 `patch-release` artifact 正确后，再用相同参数运行一次并选择 `publish_release=true`，或直接在首次成功后使用自动发布。

工作流也会在推送 `V1.0.*` 标签时运行完整构建检查，但不会替你发布 Release。发布前请核对 `update-manifest.json`、SHA-256、Android 签名和版本号，再手动上传附件。

`ui_presentation.gd` 已加入普通提交的快速检查，验证动效事件、秘密牌过滤、快照去重、重连基线、触控热区和小屏规则面板；图形截图脚本需实际窗口运行，不放进 headless CI。
