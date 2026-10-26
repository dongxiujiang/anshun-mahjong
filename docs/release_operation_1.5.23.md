# 1.5.23 发布与部署记录

版本：`1.5.23`  
Android versionCode：`54`  
构建日期：2026-10-26

## 本版内容

- 联机开局速度改为跟随房主设置，不再固定 0.5 倍；
- 房主设置会同步到权威端，客户端与服务端共用同一开局速度；
- 联机房间 lobby 携带 opening_speed，所有客户端按同一节奏播放；
- 开局等待中移除多余的 0.25 秒收尾缓冲，理牌完成后直接进入首次摸牌；
- 单机快/正常档位仍分别生效。

## 测试

```text
run_suites.py：71 / 71
```

## 产物

```text
APK 94,804,571 字节
SHA-256 3780d60a6c692109c373b3ce6e2c31af3efa8432a1215b06e126a63c9f3ccc50

Android 热补丁 154,108 字节（基线 1.5.22）
SHA-256 0d7902d199234286b4ff42ab2fd6878deea57d0010f7cfe6f15d3eede375312e
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.23
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
服务器镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-9ecd09d
热补丁基线：1.5.22
```
