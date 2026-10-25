# 1.5.18 发布与部署记录

版本：`1.5.18`  
Android versionCode：`49`  
构建日期：2026-10-25

## 本版内容

- 碰杠/鸡牌使用座位固定锚点，不再随手牌张数左右漂移；
- 恢复横向避让，纵向搜索限制在真实牌桌高度内；
- 出界判断统一使用 `table._table_bounds()` 真实绿面；
- fallback 整体压回绿面，测试不再跳过 fallback；
- 精简布局缓存 key，移除无关按钮和分数控件；
- 保持牌面尺寸、发牌/摸牌/计分/结算/对象池逻辑不变。

## 测试

```text
run_suites.py：70 / 70
smoke_table_layout：通过
```

## 产物

```text
APK 94,796,034 字节
SHA-256 b5d47bd83a1004086d0fd35baf280bf01c6737717cea0143ecb8f5ca33133855

Android 热补丁 73,072 字节（基线 1.5.17）
SHA-256 adc6f1cd968655542986bd9430302ed53ab57e5755a52434ba17a2551a5dd91f
```

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.18
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
热补丁基线：1.5.17
```
