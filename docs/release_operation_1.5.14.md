# 1.5.14 发布与部署记录

版本：`1.5.14`  
Android versionCode：`45`  
构建日期：2026-10-25

## 本版内容

- 移除 Windows 导出预设、Windows EXE 与 Windows 热补丁；
- 客户端只保留 Android 版本；
- 发布清单只包含 Android APK 与 Android 热补丁；
- 移除 Windows GME/PCM 支持和相关发布文档入口；
- Android GME 语音保持不变。

## 测试

```text
run_suites.py：70 / 70
```

## 产物

```text
APK 94,794,050 字节
SHA-256 b7f068a4be75c782142b864038c255813c49403c0db37ad4d08d00e6bcda6d13
```

本版移除了 Windows 导出预设，`export` 快照发生变化，因此不提供从 1.5.9 起的增量热补丁；Android 用户安装完整 APK。

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.14
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```

