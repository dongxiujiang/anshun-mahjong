# 1.5.7 发布与部署记录

版本：`1.5.7`  
基线：`1.4.13-boot1`  
Android versionCode：`38`  
构建日期：2026-10-24

## 本版内容

- 未叫牌杠组个人分只扣一次：杠基础 + 杠中鸡 + 翻鸡；
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
大小：94,770,446 字节
SHA-256：d2d4323cf15f1d21ec33d0f24729523ce222bef7a99408b121692a8ee9524717
versionName：1.5.7
versionCode：38
```

Windows：

```text
文件：anshun-mahjong-windows-x64.exe
大小：120,334,144 字节
SHA-256：91508556e372bb5210a50d0028aa248abb2449f383dc753ce38130499dbddd4d
```

## 热补丁

```text
anshun-mahjong-android-1.5.7.pck
anshun-mahjong-windows-1.5.7.pck
大小：276,040 字节
SHA-256：76084fa0a3422c57808c80a1d0321b6a454c2212114fbee3485189f2d533ec3b
```

完整 PCK：

```text
anshun-mahjong-full-1.5.7.pck
11,043,120 字节
SHA-256：f1e0f6a7b76c816777cd7b07efbf12fcdf3d7cc5e6fa9d92b71a546f99d100f3
```
