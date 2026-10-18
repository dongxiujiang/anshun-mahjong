# 更新下载线路验证

GitHub Release、CI、包签名与发布地址保持原样。客户端默认依次使用
`ghproxy.net`、`ghproxy.com`、`gh.llkk.cc`，最后使用原始 GitHub 地址。
公共线路会变化；可通过 `updates/download_proxies` 配置列表，或用
`updates/use_download_proxies=false` 关闭。默认值在 UpdateManager 中，
无需修改项目配置或重新部署发版服务。

只转发公开的 GitHub Release 文件地址。API、非 GitHub 地址、已套代理的地址
以及带查询参数的地址不拼代理。版本与文件摘要仍取自官方 HTTPS API；
有官方摘要的更新清单才走代理，并在解析后核对版本。

已知大小的游戏内下载按 4 MiB Range 分段。连接中断后保留完整片段，
换线路继续；服务器忽略 Range 返回 200 时用完整响应替换片段。
最终必须通过大小、文件格式、SHA-256 校验才保存／应用。
显式取消会删除片段；续传用于当前下载过程中的线路切换，不跨应用重启。

APK 沿用浏览器下载：HEAD 检测失败会切换线路，HEAD 不被支持时尝试
小范围 GET。浏览器打开后的下载进度不归游戏控制；再次点击下载会优先换线。

运行（用本机 Godot 路径替换 `godot`）：

```text
godot --headless --script res://tests/update_download_routes.gd
python tests/run_update_proxy.py --godot godot
python tests/run_startup_update.py --godot godot
```

代理集成测试使用本机 HTTP 服务，不依赖公共代理，不打开浏览器。
覆盖错误页、断流、断点偏移、忽略／错误 Range、文件损坏、超时、取消、
清单校验、APK 线路检测和再次点击换线；日志保存在 `build/update_proxy_fixture/`。
