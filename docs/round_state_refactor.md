# 回合状态、快照与音频的职责

`RoundState.gd` 负责发牌、回合推进、响应优先级和结束结算。
`RoundSerializer.gd` 负责生成/接收网络快照，以及按玩家座位隐藏手牌和未亮出的暗杠。
`RoundAudio.gd` 负责音频事件编号、每局会话、历史限长、胡牌语音去重与接收同步。

## 内部枚举

- `RoundState.Phase`：`IDLE`、`DEALING`、`PLAYING`、`SETTLED`。
- `RoundState.ResponseStage`：`NONE`、`WIN`、`MELD`、`ROB`。
- `RoundState.KongKind`：`NONE`、`EXPOSED`、`CONCEALED`、`ADD_KONG`。

`phase`、`_response_stage`、`_kong_draw_kind`、`_awaiting_response.stage`、
`last_discard.kong_kind` 和结算条目的 `kong_kind` 在本地均使用枚举。
碰杠面子的 `meld.kind`、玩家操作的 `action` 仍是现有数据格式，未纳入这次状态转换。

## 网络格式兼容

网络快照仍发送原有字段和字符串值：

| 字段 | 网络值 |
| --- | --- |
| `phase` | `idle` / `dealing` / `playing` / `settled` |
| `awaiting_response.stage` | 空字符串 / `win` / `meld` / `rob` |
| `last_discard.kong_kind`、结算条目的 `kong_kind` | 空字符串 / `exposed` / `concealed` / `add_kong` |

发送时转换为字符串，接收时转换回枚举；嵌套结算中的类型同样转换。
快照及接收后的数据互相隔离，隐藏牌面不会修改权威端的真实手牌。
没有完整牌墙的接收方可以使用同步的剩余数量再次生成快照，未发牌状态也支持序列化。
这不是完整的权威牌局存档，不能仅凭网络快照重建隐藏牌墙和服务器控制器。

现有 `RoundState.serialize()`、`apply_sync()`、`serialize_for_seat()` 以及
`audio_event` 信号保留。`audio_session`、`audio_event_id`、`audio_events` 通过读取接口提供，
实际音频状态由 `RoundAudio` 保存。初次同步不重播历史语音，后续仅播放新的事件。

## 验证入口

`tests/round_sync.gd` 检查旧协议互转、深拷贝、缺省字段、空闲状态及暗牌隐藏；
已加入 `tests/run_all.gd` 和 GitHub Actions 核心测试。
`smoke_audio` 覆盖出牌、碰杠、报听、胡牌和网络语音去重。
真实联机测试通过 `tests/run_network.py` 启动配对进程，重连通过 `tests/run_reconnect.py` 验证。

这次脚本重构不改变引擎、原生依赖或安装配置，发布时可沿用现有热补丁流程。
新增模块通过 `preload` 引用，不注册新的 `class_name`，因此不会改变补丁工具检查的全局类清单。
