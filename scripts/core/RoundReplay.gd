extends RefCounted
## 仅权威端保存真实牌墙和操作；不进入网络快照，重放不依赖随机种子或 AI。
const LIMIT := 20
const DIRECTORY := "user://replays"
var record := {}
var playback := false
var auto_save := false
var last_path := ""
var _started_ticks := 0

func begin(round) -> void:
	if playback: return
	record = {"schema": 1, "version": str(ProjectSettings.get_setting("application/config/version", "")),
		"id": round.audio_session, "started_at": Time.get_datetime_string_from_system(true),
		"initial": round.serialize(), "wall": _wall_state(round.wall), "actions": [], "requests": [], "final": {}}
	# 报听标志不在网络协议内，需要单独保存供离线重放。
	record.announced_ready = round.players.map(func(player): return player.announced_ready)
	last_path = ""
	_started_ticks = Time.get_ticks_msec()

func action(round, kind: String, seat: int, decision: Dictionary, source: int = -1, tile: String = "") -> void:
	if playback or record.is_empty(): return
	record.actions.append({"kind": kind, "seat": seat, "decision": decision.duplicate(true),
		"source": source, "tile": tile, "stage": int(round._response_stage), "before": fingerprint(round), "elapsed_ms": Time.get_ticks_msec() - _started_ticks})

func request(seat: int, kind: String, decision: Dictionary, accepted: bool, reason: String) -> void:
	if playback or record.is_empty(): return
	record.requests.append({"seat": seat, "kind": kind, "decision": decision.duplicate(true), "accepted": accepted, "reason": reason,
		"action_index": record.actions.size(), "elapsed_ms": Time.get_ticks_msec() - _started_ticks})
	# 重复/过期网络请求不能无限扩大日志。
	if record.requests.size() > 64: record.requests.pop_front()

func update_players(round) -> void:
	if playback or record.is_empty(): return
	for seat in round.players.size():
		record.initial.players[seat].name = round.players[seat].name_label
		record.initial.players[seat].is_human = round.players[seat].is_human

func finish(round) -> void:
	if playback or record.is_empty(): return
	record.final = {"fingerprint": fingerprint(round), "result": round.last_result.duplicate(true)}
	if auto_save:
		last_path = save()

func save(path: String = "") -> String:
	if record.is_empty(): return ""
	if path == "":
		DirAccess.make_dir_recursive_absolute(DIRECTORY)
		path = DIRECTORY.path_join("round-%s-%s.json" % [str(record.started_at).replace(":", "-").replace("T", "-"), record.id])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(JSON.stringify(record))
	file.close()
	if path.begins_with(DIRECTORY + "/"):
		var files: Array = []
		for name in DirAccess.get_files_at(DIRECTORY):
			if name.begins_with("round-") and name.ends_with(".json"): files.append(name)
		files.sort()
		while files.size() > LIMIT:
			DirAccess.remove_absolute(DIRECTORY.path_join(files.pop_front()))
	last_path = path
	return path

static func _wall_state(wall: WallRing) -> Dictionary:
	return {"ring": wall._ring.duplicate(), "drawn": wall._drawn.duplicate(), "head": wall._head, "tail": wall._tail, "remaining": wall.remaining}

static func fingerprint(round) -> String:
	var state: Dictionary = round.serialize()
	# 人机同步执行与人工逐步提交的提示编号/音频会话不同，不影响规则结果。
	for key in ["awaiting", "prompt_id", "awaiting_response", "audio_session", "audio_event_id", "audio_events"]: state.erase(key)
	for player in state.players:
		player.erase("name")
		player.erase("is_human")
	for player in state.get("last_result", {}).get("players", []): player.erase("name")
	var stable := {"state": state, "wall": _wall_state(round.wall), "stage": int(round._response_stage),
		"pending": round._pending_responders.duplicate(), "pending_kong": round._pending_kong.duplicate(true),
		"kong_draw": round._kong_draw_turn, "kong_kind": int(round._kong_draw_kind), "draw_before": round._draw_remaining_before}
	# JSON 规范化整数/浮点数和字典排序，允许导出文件后再次读取。
	var normalized: Variant = JSON.parse_string(JSON.stringify(stable, "", true, true))
	return JSON.stringify(normalized, "", true, true).sha256_text()

static func load_record(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 8 * 1024 * 1024: return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}

static func replay(data: Dictionary) -> Dictionary:
	if int(data.get("schema", -1)) != 1 or not data.get("initial") is Dictionary or not data.get("wall") is Dictionary or not data.get("actions") is Array:
		return {"ok": false, "error": "不支持或不完整的对局记录", "event_index": -1}
	var initial: Dictionary = data.initial
	var wall_data: Dictionary = data.wall
	if not initial.get("players") is Array or initial.players.size() != 4 or not wall_data.get("ring") is Array or wall_data.ring.size() != 108 or not wall_data.get("drawn") is Array or wall_data.drawn.size() != 108:
		return {"ok": false, "error": "初始牌局或牌墙不完整", "event_index": -1}
	for key in ["current_turn", "round_meta", "last_discard", "awaiting", "wall"]:
		if not initial.has(key): return {"ok": false, "error": "初始牌局缺少字段：" + key, "event_index": -1}
	if initial.get("phase", "") != "playing" or not initial.round_meta is Dictionary or not initial.last_discard is Dictionary or not initial.wall is Dictionary:
		return {"ok": false, "error": "初始牌局阶段或字段格式错误", "event_index": -1}
	for key in ["head", "tail", "remaining"]:
		if not wall_data.has(key): return {"ok": false, "error": "牌墙缺少字段：" + key, "event_index": -1}
	if int(wall_data.head) not in range(108) or int(wall_data.tail) not in range(108) or int(wall_data.remaining) not in range(109):
		return {"ok": false, "error": "牌墙位置越界", "event_index": -1}
	if int(initial.current_turn) not in range(4) or int(initial.get("dealer_seat", 0)) not in range(4):
		return {"ok": false, "error": "初始座位越界", "event_index": -1}
	if not data.get("final", {}) is Dictionary or not data.get("announced_ready", [false, false, false, false]) is Array or data.get("announced_ready", [false, false, false, false]).size() != 4:
		return {"ok": false, "error": "结算或报听字段格式错误", "event_index": -1}
	for seat in 4:
		var player: Variant = initial.players[seat]
		if not player is Dictionary: return {"ok": false, "error": "玩家状态格式错误", "event_index": -1}
		for key in ["seat", "concealed", "melds", "discards", "score", "ready", "name", "is_human"]:
			if not player.has(key): return {"ok": false, "error": "玩家状态缺少字段：" + key, "event_index": -1}
		if int(player.seat) != seat or not player.concealed is Array or not player.melds is Array or not player.discards is Array:
			return {"ok": false, "error": "玩家座位或牌面格式错误", "event_index": -1}
	var round := RoundState.new()
	round._recorder.playback = true
	# JSON 的牌墙字典键为字符串；重新生成公开墙统计来自完整牌墙。
	round.apply_sync(initial)
	round.controllers = [null, null, null, null]
	round.wall = WallRing.new(wall_data.ring, round.dealer_seat)
	for index in 108: round.wall._drawn[index] = bool(wall_data.drawn[index])
	round.wall._head = int(wall_data.head)
	round.wall._tail = int(wall_data.tail)
	round.wall.remaining = int(wall_data.remaining)
	for seat in 4: round.players[seat].announced_ready = bool(data.get("announced_ready", [false, false, false, false])[seat])
	round._begin_turn()
	for index in data.actions.size():
		var event: Variant = data.actions[index]
		if not event is Dictionary or not event.get("decision") is Dictionary:
			return {"ok": false, "error": "操作记录格式错误", "event_index": index}
		if not event.has("seat") or int(event.seat) not in range(4):
			return {"ok": false, "error": "操作座位越界", "event_index": index}
		if fingerprint(round) != str(event.get("before", "")):
			return {"ok": false, "error": "操作前状态与记录不一致", "event_index": index, "round": round}
		var accepted := false
		if event.get("kind", "") == "turn":
			accepted = round.submit_turn(int(event.seat), event.decision)
		elif event.get("kind", "") == "response":
			accepted = round.submit_response(int(event.seat), str(event.get("tile", "")), event.decision)
		if not accepted:
			return {"ok": false, "error": "记录中的操作不符合当前规则", "event_index": index, "round": round}
	if not data.get("final", {}).is_empty() and fingerprint(round) != str(data.final.get("fingerprint", "")):
		return {"ok": false, "error": "最终状态或结算与记录不一致", "event_index": data.actions.size(), "round": round}
	return {"ok": true, "error": "", "event_index": data.actions.size(), "round": round}
