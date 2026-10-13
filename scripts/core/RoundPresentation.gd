extends RefCounted
## 回合视觉事件的轻量状态机。逻辑已经完成后才发布事件，事件可从网络快照重放。

signal visual_event(event: Dictionary)

const HISTORY_LIMIT := 32
var session := ""
var event_id := 0
var events: Array = []
var sync_initialized := false

func _init() -> void:
	reset()

func reset() -> void:
	session = Crypto.new().generate_random_bytes(8).hex_encode()
	event_id = 0
	events.clear()
	sync_initialized = false

func emit_event(event_type: String, data: Dictionary = {}) -> void:
	event_id += 1
	var event := data.duplicate(true)
	event["session"] = session
	event["id"] = event_id
	event["type"] = event_type
	events.append(event)
	while events.size() > HISTORY_LIMIT:
		events.pop_front()
	visual_event.emit(event.duplicate(true))

func apply_sync(state: Dictionary) -> void:
	var incoming_session := str(state.get("visual_session", ""))
	var last_id := event_id if incoming_session == session else 0
	session = incoming_session
	event_id = int(state.get("visual_event_id", 0))
	events = state.get("visual_events", []).duplicate(true)
	if not sync_initialized:
		sync_initialized = true
		return
	for event in events:
		if str(event.get("session", "")) == session and int(event.get("id", 0)) > last_id:
			visual_event.emit(event.duplicate(true))
