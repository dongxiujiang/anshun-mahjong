# 1.5.8 发布与部署记录

版本：`1.5.8`  
基线：`1.4.13-boot1`  
Android versionCode：`39`  
构建日期：2026-10-24

## 本版内容

- 碰杠/鸡牌固定从手牌左边缘向左排列；不再向手牌右侧漂移；
- 满一行后向上换行，游标回到手牌左边缘；
- 保留碰撞避让和确定性兜底；
- 明杠窗口同时开放碰牌，持有三张的玩家可碰可杠；
- 流局无论四家叫牌还是部分叫牌，下局鸡分都 ×2；
- 未叫牌明杠基础4只反向付给放杠者；暗杠/加杠反向付给每位叫牌者；
- 结算“返回座位”和“准备下一局”统一为一条准备链路，只显示一个准备按钮和真人比例；
- 通行证胡牌名称保持统一。

## 测试

```text
run_suites.py：70 / 70
rules_spec_v2：3,283 项通过
rules_update：1,067 项通过
scoring_pairwise：28,097 项通过
```

## 产物

```text
APK 94,771,934 字节
SHA-256 34a21676839fd527fcadc764ab1ec1ebd6119cc30894c2cf684325427f76a13e

EXE 120,335,600 字节
SHA-256 5492f5809b1d7017088758bc15a25222a35313cbb34a243772e2f8235cc53238

PCK 286,636 字节
SHA-256 584093789aa8babea5d05f90c52c4ee81c63e7dbc943f0f2506028c0b3b6e42c

完整PCK 11,044,576 字节
SHA-256 0798f745c937c2588300182b12f9ac9c293bb101c2d1b1cc4b737c2550c439e1
```n

## 发布

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.5.8
服务端镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-3b4c0c2
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
```n
