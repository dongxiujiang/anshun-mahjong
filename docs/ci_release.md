# GitHub Actions 构建与发布

当前正式安装包版本为 1.6.19，Android 安装基线为 1.6.19-native1。导出预设仅包含 Android。

## 检查与构建

- ci.yml 在 main/master 推送、PR 和手动触发时执行规则、计分、声音、牌桌、明细和同步检查。
- build-release.yml 执行完整回归、至少 50 局 AI 自战、多进程联机和断线重连检查，通过后生成正式签名 APK 或累计 PCK 补丁。
- 图形化检查覆盖 12 FPS 客户端的开局完成确认、碰杠飞行和结算布局，截图保存在 table-ui-review 构建产物中。任意客户端未理牌完成时不得提前开始摸牌。
- Windows 任务验证热更新启动、回滚和恢复逻辑，只生成隔离测试程序。
- docker-image.yml 支持手动构建及正式版本标签，生成与提交对应的联机服务器镜像。

引擎和模板下载采用重试。测试、导出或签名验证失败都会阻止发布。日志分别保存为 quick-check-logs 和 ci-logs 构建产物，签名私钥及凭据在任务结束时清理。

## 完整安装包

在 Build release 选择 release_kind=full。构建读取工程版本、Android version/code 与 base_id，生成 APK、签名清单和 baseline.zip。首次审阅使用 publish_release=false，通过后可运行 Promote full release artifact 发布同一次构建的文件。

完整包沿用正式 APK 签名，用户可覆盖安装。新的完整包安装基线必须配套保存，不能用新基线给旧安装包制作补丁。

## 热更新

在 Build release 选择 release_kind=patch，填写高于完整安装包的版本号。

- baseline_source=release 从所选完整版本的 Release 下载 baseline.zip。当前对应标签为 V1.6.19。
- baseline_source=artifact 从完整构建的 run id 下载 baseline 构建产物。
- 工具核对引擎、启动脚本、全局类、原生依赖、工程设置和导出配置，兼容后生成 Android PCK 与签名清单。
- publish_release=true 通过检查后发布，false 保存构建产物供审阅。

基线 artifact 保留 90 天，Release 中的 baseline.zip 用于长期保存。标签触发的发布要求标签与工程版本相同。

## 服务器与自建更新源

服务端镜像按提交 SHA 标记。先在隔离端口测试，再切换目录入口。更新文件先上传并验证 SHA-256，最后切换主清单和回退清单，并保留上一版本文件用于恢复。

Android 签名由 ANDROID_KEYSTORE_BASE64、ANDROID_KEYSTORE_USER 和 ANDROID_KEYSTORE_PASSWORD 提供，更新清单必须提供 MANIFEST_SIGNING_KEY。敏感凭据只从 Actions Secrets 读取。
