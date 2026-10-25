# 1.5.20 发布与部署记录

版本：`1.5.20`  
Android versionCode：`51`  
构建日期：2026-10-25

## 本版内容

- 结算记分标注向桌心收拢，并避开碰杠/鸡牌；
- 普通鸡、碰、杠行间无额外间距，仅冲锋鸡与普通鸡保留分隔；
- 修正三张八筒（1 冲锋 + 2 普通）显示成“八筒-2分”的文字错误，实际仍显示真实合计；
- AI 教学推荐高亮在摸牌刷新后保持，弃牌/选择后才清除；
- 可碰/杠/胡时对应按钮高亮；
- 设置新增“开局发牌”速度：快 / 正常，快档为当前标准时长的一倍。

## 测试

```text
run_suites.py：70 / 70
```

## 产物

```text
APK 94,795,666 字节
SHA-256 aacce67e8a6030d0fabb37b65c0a45906334376af88b8aea461eee3c58e04fe2

Android 热补丁 148,684 字节（基线 1.5.19）
SHA-256 a4aa602daa53be660cc96559f6172aa24b9fb52a3d6315149716afe991c6339a
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.20
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.19
```
