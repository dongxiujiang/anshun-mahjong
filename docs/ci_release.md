# GitHub Actions 构建与热更新

工作流文件是 `.github/workflows/build-release.yml`。它只构建并上传 Actions artifact，不会自动创建 GitHub Release，也不会修改项目版本号。完成审核后，维护者可以把 artifact 下载后手动上传到对应 Release。首次完整构建同时保存 `baseline`，供同一安装基线的小版本热补丁使用。

## 必需的 Secrets

正式 Android 包必须继续使用第一次发布的同一签名。仓库需要配置以下 Actions Secrets：

- `ANDROID_KEYSTORE_BASE64`：正式 `.keystore` 文件的 Base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码。
- `ANDROID_KEYSTORE_USER`：签名 alias。

缺少任意一个 Secret 时，Android job 会失败，不会生成可误发布的未签名包。私钥、密码和导出的 credentials 不会上传 artifact。

## 手动构建

在 GitHub 的 **Actions → Build release** 选择 **Run workflow**：

- `release_kind=full`：构建 Windows EXE、Android APK、完整发布清单，并上传当前代码的补丁基线 artifact。只有完整构建会读取三个签名 Secret。
- `release_kind=patch`：填写 `baseline_run_id` 和 `patch_version`（例如 `1.0.1`），工作流会下载该次完整构建保存的 `baseline` artifact，运行兼容性检查并生成 Windows/Android PCK 补丁和清单；补丁不重新构建或签名 APK。

首次 `1.0.0` 构建使用 `full`。之后的 `1.0.x` 小版本使用 `patch`，并把对应完整构建的 Actions run id 填入 `baseline_run_id`。基线 artifact 目前保留 90 天，下载后请单独备份；不能用新版本覆盖。工作流只允许同一主版本的补丁；引擎、Autoload、导出设置、原生插件或安装基线变化时，应构建新的完整大版本。

你已经发布的 `V1.0.0` 有一份本地原始基线 `build/update_baselines/1.0.0-boot1/`。首次在 Actions 点击 `full` 只能验证当前代码的完整构建，不能把它生成的新基线直接当成旧 `V1.0.0` 玩家可用的基线，也不要自动替换已发布附件。给现有 `V1.0.0` 玩家生成小补丁时，继续使用项目中备份的原始基线和根目录的 `生成小版本更新.cmd`；Actions 基线适用于与它对应的那次完整安装包。

工作流只上传必要的安装包、PCK、清单和不含签名凭据的检查日志；临时 keystore 与 `.godot/export_credentials.cfg` 会在任务结束时删除。

工作流也会在推送 `V1.0.*` 标签时运行完整构建检查，但不会替你发布 Release。发布前请核对 `update-manifest.json`、SHA-256、Android 签名和版本号，再手动上传附件。
