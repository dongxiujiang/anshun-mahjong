# 1.5.22 发布与部署记录

版本：`1.5.22`  
Android versionCode：`53`  
构建日期：2026-10-26

## 本版内容

- 联机麦克风旁新增「测试」按钮；
- 支持测试牌型：报听牌、碰杠牌、鸡牌；
- 发起后全房间真人投票，全部同意才执行；
- 投票通过立即重开本局，不推进庄家；
- 测试牌型只发给发起者，其他座位正常发牌；
- 测试牌型只生效一局，牌张总数仍保持 108；
- 新增 `test_patterns` 回归测试。

## 测试

```text
run_suites.py：71 / 71
```

## 产物

```text
APK 94,803,535 字节
SHA-256 e769fa777378cd7e2d2c2750362d1a3c425f14435266d5e268782fe0080bc869

Android 热补丁 178,276 字节（基线 1.5.21）
SHA-256 e109e34eac4cf2d273b9ab5df29346c38846462383fbb8fd624ba2d681e2d37e
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.22
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
服务器镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-5d56e52
热补丁基线：1.5.21
```
