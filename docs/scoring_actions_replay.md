# 结算、合法操作与可复现对局

## 结算模块

`ScoringEngine.gd` 保留原公开接口和结算结果字段，负责流程编排。
`ChickenScoring.gd` 识别普通鸡、冲锋鸡、金鸡、翻鸡和烧鸡，并按相同单张分值合并展示条目。
`KongScoring.gd` 计算每组杠的基础分、付款人、杠内鸡/翻鸡和展示条目。
`WinScoring.gd` 处理自摸、杠开、末四张、无鸡、牌型、报听与被杀。
`PaymentLedger.gd` 记录每笔付款并计算玩家间收付款矩阵。

拆分保持转账顺序、理由、结算卡片条目和分值不变。
既有 3,792 种场景的完整结果序列 SHA-256 为：
`858bf1e71f4ea9adb47dcc51cd9e0262a2f3ab622f112976a56f35bdf61b4485`。
`tests/scoring_audit.gd` 输出该摘要，配合独立规则算例检验结果。

## 合法操作

`LegalActions.gd` 提供纯规则查询：

- `turn_options`：合法弃牌、暗杠、加杠、可报听的弃牌、自摸。
- `response_options`：当前响应阶段的胡、碰、明杠和抢杠标志。
- `valid_turn`、`valid_response`：提交数据是否符合上述清单。

`RoundState.legal_turn_options()` 缓存相同手牌和墙数量的结果，返回独立副本。
`allowed_actions()` 额外检查阶段、等待窗口和座位，带当前 `prompt_id`。
UI 与 AI 使用这些规则查询；真人、AI 和网络权威端最终执行时共用校验。
网络仍检查玩家身份和提示编号。旧控制器在杠请求中附带备用弃牌仍兼容，
同一次请求不能混合自摸、暗杠、加杠和报听等不同主动作。

## 对局记录

单机和房主/服务器每局保存初始手牌、完整牌墙及摸牌位置、骰子开牌信息、累计积分、
庄家、鸡分倍数和实际执行的操作。每个操作前保存状态摘要，结束时保存最终状态及结算。
最多额外保留 64 条请求诊断，记录非法操作、过期提示和座位身份不匹配。
记录不会加入网络快照，普通客户端不会因此收到其他人的隐藏手牌。

已结束牌局自动保存最近 20 局。未结束时可在牌桌设置点击“保存本局记录”，退出房间时也保存。
完整记录来自单机、局域网房主或云端权威服务器；普通联机客户端需取得房主的文件才能完整重放。
记录目录为 Godot 的 `user://replays`。Windows 默认位于
`%APPDATA%\Godot\app_userdata\安顺麻将·捉鸡\replays`；Android 位于应用私有数据目录。

工程内运行离线诊断（PowerShell，按实际路径替换）：

```powershell
& "C:\Users\xiu\Desktop\Godot_v4.7.2-stable_win64.exe" --headless --path "C:\Users\xiu\Desktop\Mahjong-Godot" --script res://tools/debug/replay_round.gd -- "--record=C:\你的记录目录\round-xxx.json"
```

重放使用记录的墙和操作，不依赖 AI、计时或随机数。
成功后输出积分、胜者和下局庄家；失败时报告首次不一致的操作位置。
这是离线规则诊断工具，尚未添加动画回放页面。
重放应使用生成记录时的规则代码；规则改变后会通过摘要指出差异。

## 验证与发布

新增 `legal_actions`、`round_replay` 测试已注册到全套测试与 GitHub Actions。
重放测试包含 50 局完整对局、JSON 文件往返、途中记录、非法操作及碰杠报听专项。
各新模块用 `preload` 加载，没有新增全局类注册，保留固定安装基线的热补丁兼容。
