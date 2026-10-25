# 1.5.19 发布与部署记录

版本：`1.5.19`  
Android versionCode：`50`  
构建日期：2026-10-25

## 本版内容

- AI 教学删除顶部提示文本；
- 开启后只保留推荐牌的高亮；
- 推荐高亮持续到自己弃牌时清除；
- 关闭 AI 教学立即清除高亮；
- 非自己回合打开开关不显示任何提示。

## 测试

```text
run_suites.py：70 / 70
smoke_table_layout：通过
ai_safety：通过
```

## 产物

```text
APK 94,794,534 字节
SHA-256 03e9aeedd85fc3593473bc25b0078d02a777107fa1b0bf1001c9b8f82ffab46f

Android 热补丁 72,400 字节（基线 1.5.18）
SHA-256 d1f52ea7dd1e8b8cf00dcd2de6664d887a7d62f8267134d2bd4d359689e5956d
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.19
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.18
```
