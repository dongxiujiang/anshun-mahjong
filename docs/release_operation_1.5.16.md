# 1.5.16 发布与部署记录

版本：`1.5.16`  
Android versionCode：`47`  
构建日期：2026-10-25

## 本版内容

- 本地重连会话增加保存时间；
- 超过服务端 30 分钟重连保留期（含 1 分钟清理余量）的会话，启动时不再提示“继续上次房间”；
- 恢复旧房间失败时立即清除本地会话，不再每次启动重复提示；
- 服务端原有规则：无连接真人且无重连保留后，房间进程自动退出。

## 测试

```text
run_suites.py：70 / 70
network_persistence：31 项通过
```

## 产物

```text
APK 94,795,226 字节
SHA-256 e91a1cee9693a7a342b193e6cb02ab901a4916f88f09e6eb9a3c793510845c02
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.16
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```
