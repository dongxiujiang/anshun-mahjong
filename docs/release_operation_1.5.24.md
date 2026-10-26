# 1.5.24 发布与部署记录

版本：`1.5.24`  
Android versionCode：`55`  
构建日期：2026-10-26

## 本版内容

- 联机创建房间时房主直接携带开局速度，服务器第一次发牌即按该速度；
- 后续房主切换速度通过房间 lobby 同步，下一局生效；
- 测试牌型提案改走可靠 lobby 通道，发起者也必须点同意；
- 报听后下一局自动清除待确认金边；
- 报听者被未报听玩家自摸时：付完整牌型分 + 杀报24 + 鸡分/杠分，不再重复加自摸4；
- AI 教学推荐牌和推荐按钮使用蓝色粗边框；
- 保留此前的固定锚点、统一间距、结算标注避让等修复。

## 测试

```text
run_suites.py：71 / 71
远端单人在线测试：通过
```

## 产物

```text
APK 94,806,927 字节
SHA-256 6e2d91c5d3ae816e817bd9ae86f78d64def3db14d400a9d1904cbe4373cd09d7

Android 热补丁 202,364 字节（基线 1.5.23）
SHA-256 5f8f6e5d9c9af870cfd7f598fd8e0abad3ede34a3e10027882d6c3822104178d
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.24
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
服务器镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-53e6d67
热补丁基线：1.5.23
```
