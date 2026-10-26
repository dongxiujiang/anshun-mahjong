# 1.5.21 发布与部署记录

版本：`1.5.21`  
Android versionCode：`52`  
构建日期：2026-10-26

## 本版内容

- 结算「返回座位」和「准备下一局」按钮统一尺寸；
- AI 推荐高亮从鸡牌/报听金框中拆成独立标记，互不清除；
- 报听金边在刷新后保持，并统一刷新四家报听框；
- 碰杠/鸡牌统一 6px 小缝，冲锋鸡与普通鸡保留 16px；
- 开局发牌速度设置快档后，单机/联机动画与首次摸牌等待时间同步缩短；
- 13 张发牌和理牌动画结束即进入摸牌，不再按旧标准时长空等。

## 测试

```text
run_suites.py：70 / 70
```

## 产物

```text
APK 94,796,334 字节
SHA-256 5127433e1c9d0094201f43b259fc97d8a2e32be7aa73c42512cfb899f538f4a3

Android 热补丁 166,872 字节（基线 1.5.20）
SHA-256 71482ca67fffbf8f5b3b58a54f6b4a3e4c77f2670ef3ca561f75e5185fc0bf6c
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.21
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.20
```
