extends RefCounted

## 回合内音频事件的轻量状态机：编号、去重、广播与网络同步。
## 与 RoundState 解耦，RoundState 只负责把 audio_event 信号转发给 UI/网络。

signal audio_event(event: Dictionary)

const HISTORY_LIMIT := 16

var session := ""
var event_id := 0
var events: Array = []
var sync_initialized := false
var win_emitted := false

func _init() -> void:
	reset()

func reset() -> void:
	session = Crypto.new().generate_random_bytes(8).hex_encode()
	event_id = 0
	events.clear()
	win_emitted = false

func emit_action(action: String, seat: int, tile: String = "") -> void:
	event_id += 1
	var event := {"session": session, "id": event_id, "action": action, "seat": seat, "tile": tile}
	events.append(event)
	while events.size() > HISTORY_LIMIT:
		events.pop_front()
	audio_event.emit(event.duplicate(true))

func emit_win(meta: Dictionary) -> void:
	if int(meta.get("winner", -1)) < 0 or win_emitted:
		return
	win_emitted = true
	emit_action("zimo" if meta.get("self_draw", false) else "hu", int(meta.winner), str(meta.get("win_tile", "")))

## 初次加入/重连只接收当前进度，不重播此前牌名及已结束的胡牌。
func apply_sync(state: Dictionary) -> void:
	var incoming_session := str(state.get("audio_session", ""))
	var last_id := event_id if incoming_session == session else 0
	session = incoming_session
	event_id = int(state.get("audio_event_id", 0))
	events = state.get("audio_events", []).duplicate(true)
	if not sync_initialized:
		sync_initialized = true
		return
	for event in events:
		if str(event.get("session", "")) == session and int(event.get("id", 0)) > last_id:
			audio_event.emit(event.duplicate(true))
