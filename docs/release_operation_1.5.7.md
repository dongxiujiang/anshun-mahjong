# 1.5.7 发布与部署记录

版本：`1.5.7`  
基线：`1.4.13-boot1`  
Android versionCode：`38`  
构建日期：2026-10-24

## 本版内容

- 未叫牌杠组个人分只扣一次：杠基础 + 杠中鸡 + 翻鸡；`n- 清理碰杠区冲锋标记死代码；`n- 碰杠/鸡牌布局增加输入缓存，减少重复避让计算；`n- 空间不足时使用确定性紧凑兜底，不再保留上次探测坐标；`n- 补明明杠横放方向注释；
- 未叫牌杠主反向支付基础4，叫牌杠主仍能收到自己的基础分；
- 2026-10-24 12:17 快照：
  ```text
  个人分 [-22, 5, 8, 2]
  净分   [-81, 27, 39, 15]
  ```
- 两两矩阵：
  ```text
  [ 0, -27, -30, -24]
  [27,   0,  -3,   3]
  [30,   3,   0,   6]
  [24,  -3,  -6,   0]
  ```

## 测试

```text
run_suites.py：70 / 70
scoring_pairwise：28,085 项通过
```

## 完整包

Android：

```text
文件：anshun-mahjong.apk
大小：94,771,482 字节
SHA-256：31a3bb7ebd5b0bc547a40b168f6e49956111115d1780741adeea4cd93920fac4
versionName：1.5.7
versionCode：38
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,335,072 字节
SHA-256：9785586eff405558bcb36bfcfd95ea564812fcf0cc33307dea3436150a0788c5
```

## 热补丁

```text
anshun-mahjong-android-1.5.7.pck
anshun-mahjong-windows-1.5.7.pck
大小：276,968 字节
SHA-256：47778fd500186f63eee3de68b767fa519b4369898f5c6e079771cf5c5bb8e27d
```

完整 PCK：

```text
anshun-mahjong-full-1.5.7.pck
11,044,048 字节
SHA-256：8623d74e56ca8586de90c7622a3f449fa2ecbab5f20415ee796bde4e8a03be69
```


