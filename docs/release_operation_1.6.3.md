# 1.6.3 发布与部署记录

版本：`1.6.3`  
Android versionCode：`64`  
构建日期：2026-10-29

## 内容

- 对应结算规则提交 `db8e4b8`；
- 修复 1.6.2 导出被实验性 GDExtension 配置打断、贴图/字体/音频缺失的问题；
- 1.6.2 安装包不完整，请使用 1.6.3。

## 测试

```text
run_suites.py：71 / 71
```
## 产物

```text
APK 96,485,988 字节
SHA-256 0166105fbaad34ec9f17b1b34ec2e19a3eb9e6e69913cc083cab9feff624af1b
```

## 修复说明

1.6.2 的导出被 `native/onnx_high/high_onnx.gdextension` 打断，缺少贴图、字体和音频资源，已废弃。1.6.3 已排除实验性扩展目录并恢复完整资源。
## 部署

```text
GitHub Release：https://github.com/dongxiujiang/anshun-mahjong/releases/tag/V1.6.3
自建清单：https://mj.dongxiu.fun/updates/update-manifest.json
服务器镜像：ghcr.io/dongxiujiang/anshun-mahjong:sha-ce56564
```

1.6.2 的 GitHub Release 和 tag 已删除，避免继续下载坏包。
