# GitHub Actions 构建与热更新

工作流文件是 `.github/workflows/build-release.yml`。它只构建并上传 Actions artifact，不会自动创建 GitHub Release，也不会修改项目版本号。完成审核后，维护者可以把 artifact 下载后手动上传到对应 Release。

## 必需的 Secrets

正式 Android 包必须继续使用第一次发布的同一签名。仓库需要配置以下 Actions Secrets：

- `ANDROID_KEYSTORE_BASE64`：正式 `.keystore` 文件的 Base64 内容。
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码。
- `ANDROID_KEYSTORE_USER`：签名 alias。

缺少任意一个 Secret 时，Android job 会失败，不会生成可误发布的未签名包。私钥、密码和导出的 credentials 不会上传 artifact。

## 手动构建

在 GitHub 的 **Actions → Build release** 选择 **Run workflow**：

- `release_kind=full`：构建 Windows EXE、Android APK、完整发布清单，并上传当前代码的补丁基线 artifact。
- `release_kind=patch`：填写 `baseline_run_id` 和 `patch_version`（例如 `1.0.1`），工作流会下载该次完整构建保存的 `baseline` artifact，运行兼容性检查并生成 Windows/Android PCK 补丁和清单。

首次 `1.0.0` 构建使用 `full`。之后的 `1.0.x` 小版本使用 `patch`，并把首次完整构建的 Actions run id 填入 `baseline_run_id`。基线 artifact 必须长期保留，不能用新版本覆盖。工作流只允许同一主版本的补丁；引擎、Autoload、导出设置、原生插件或安装基线变化时，应构建新的完整大版本。

工作流也会在推送 `V1.0.*` 标签时运行完整构建检查，但不会替你发布 Release。发布前请核对 `update-manifest.json`、SHA-256、Android 签名和版本号，再手动上传附件。
