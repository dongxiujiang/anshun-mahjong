# 1.5.25 发布与部署记录

版本：`1.5.25`  
Android versionCode：`56`  
构建日期：2026-10-26

## 本版内容

- 正式包不再显示联机「测试牌型」按钮；
- 只有开启 debug 的测试环境才显示测试按钮和投票卡片；
- 保留 1.5.24 的联机速度、测试牌型和杀报结算修复。

## 测试

```text
run_suites.py：71 / 71
smoke_table_layout：通过
```

## 产物

```text
APK 94,806,935 字节
SHA-256 fec655b21138ab70f8c25a4e5433a48ad26ce3a4b615e36d2d9ccafeddbF2300

Android 热补丁 79,176 字节（基线 1.5.24）
SHA-256 68e64ae623972b6eb844b32f276a92456553aa6c4b000c98dd442fe6772649ac
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.25
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.24
```
