extends RefCounted
## Room-scoped timer state. The authority supplies monotonic milliseconds.

enum Kind { DISCARD, RESPONSE }

const DISCARD_MS := 10000
const RESPONSE_MS := 5000
const GRACE_MS := 5000
const REMINDER_MS := 3000

var _room_instance_id: String
var _round_number := 0
var _prompt_id := -1
var _prompt_active := false
var _round_ended := false
var _kind := Kind.DISCARD
var _duration_ms := 0
var _timers := {}


func _init(room_instance_id: String) -> void:
	_room_instance_id = room_instance_id


func begin_prompt(round_number: int, prompt_id: int, kind: Kind, seats: Array[int], duration_ms: int = -1) -> bool:
	if _room_instance_id.is_empty() or round_number < 1 or round_number < _round_number or prompt_id < 0:
		return false
	if round_number == _round_number and (_round_ended or prompt_id <= _prompt_id):
		return false
	if kind not in [Kind.DISCARD, Kind.RESPONSE] or duration_ms == 0 or duration_ms < -1:
		return false
	if seats.is_empty() or (kind == Kind.DISCARD and seats.size() != 1):
		return false
	var timers := {}
	for seat in seats:
		if seat < 0 or seat >= 4 or timers.has(seat):
			return false
		timers[seat] = {"timeout_issued": false}
	_round_number = round_number
	_prompt_id = prompt_id
	_prompt_active = true
	_round_ended = false
	_kind = kind
	_duration_ms = duration_ms
	if _duration_ms == -1:
		_duration_ms = DISCARD_MS if _kind == Kind.DISCARD else RESPONSE_MS
	_timers = timers
	return true


# The authority calls this when the relevant animation ends and this seat can act.
func animation_finished(round_number: int, prompt_id: int, seat: int, now_ms: int) -> bool:
	if not _matches_prompt(round_number, prompt_id) or not _timers.has(seat) or now_ms < 0:
		return false
	var timer: Dictionary = _timers[seat]
	if timer.has("start_ms"):
		return false
	timer.start_ms = now_ms
	return true


func timing_for(round_number: int, prompt_id: int, seat: int, now_ms: int) -> Dictionary:
	if not _matches_prompt(round_number, prompt_id) or not _timers.has(seat):
		return {}
	var timer: Dictionary = _timers[seat]
	if not timer.has("start_ms") or now_ms < int(timer.start_ms):
		return {"phase": "waiting_animation", "remaining_ms": -1, "reminder": false}
	var start_ms: int = timer.start_ms
	var main_end_ms := start_ms + _duration_ms
	var deadline_ms := _deadline_ms(start_ms)
	var phase := "countdown"
	var remaining_ms := main_end_ms - now_ms
	if now_ms >= deadline_ms:
		phase = "timeout"
		remaining_ms = 0
	elif now_ms >= main_end_ms:
		phase = "grace"
		remaining_ms = deadline_ms - now_ms
	return {
		"phase": phase,
		"remaining_ms": remaining_ms,
		"duration_ms": GRACE_MS if phase == "grace" else _duration_ms,
		"kind": "discard" if _kind == Kind.DISCARD else "response",
		"reminder": now_ms >= main_end_ms - REMINDER_MS and (_kind == Kind.DISCARD or now_ms < deadline_ms),
		"deadline_ms": deadline_ms,
	}


# A due intent leaves acceptance and deadline arbitration to the authority.
func tick(round_number: int, prompt_id: int, now_ms: int) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	if not _matches_prompt(round_number, prompt_id):
		return intents
	for seat in _timers:
		var timer: Dictionary = _timers[seat]
		if not timer.has("start_ms") or timer.timeout_issued:
			continue
		var deadline_ms := _deadline_ms(timer.start_ms)
		if now_ms < deadline_ms:
			continue
		timer.timeout_issued = true
		intents.append({
			"room_instance_id": _room_instance_id,
			"round_number": round_number,
			"prompt_id": prompt_id,
			"seat": seat,
			"action": "ai_discard" if _kind == Kind.DISCARD else "pass",
			"deadline_ms": deadline_ms,
		})
	return intents


func action_accepted(round_number: int, prompt_id: int, seat: int) -> bool:
	return _matches_prompt(round_number, prompt_id) and _timers.erase(seat)


func clear_prompt(round_number: int, prompt_id: int) -> bool:
	if not _matches_prompt(round_number, prompt_id):
		return false
	_prompt_active = false
	_timers.clear()
	return true


func end_round(round_number: int) -> bool:
	if round_number < 1 or round_number < _round_number or (round_number == _round_number and _round_ended):
		return false
	_round_number = round_number
	_round_ended = true
	_prompt_active = false
	_timers.clear()
	return true


func _matches_prompt(round_number: int, prompt_id: int) -> bool:
	return _prompt_active and round_number == _round_number and prompt_id == _prompt_id


func export_authority() -> Dictionary:
	return {"round_number": _round_number, "prompt_id": _prompt_id, "prompt_active": _prompt_active,
		"round_ended": _round_ended, "kind": _kind, "duration_ms": _duration_ms,
		"timers": _timers.duplicate(true), "start_by_presence": true}


func restore_authority(state: Dictionary) -> bool:
	if not state.get("timers") is Dictionary:
		return false
	_round_number = int(state.get("round_number", 0))
	_prompt_id = int(state.get("prompt_id", -1))
	_prompt_active = bool(state.get("prompt_active", false))
	_round_ended = bool(state.get("round_ended", false))
	_kind = int(state.get("kind", Kind.DISCARD))
	_duration_ms = int(state.get("duration_ms", 0))
	_timers = state.timers.duplicate(true)
	if not state.get("start_by_presence", false):
		for timer in _timers.values():
			if timer.get("start_ms") == -1:
				timer.erase("start_ms")
	return true


# 接管后单调时钟原点不同：把旧权威端已存的绝对时间整体平移到现在时钟。
func rebase_times(delta_ms: int) -> void:
	for seat in _timers:
		var timer: Dictionary = _timers[seat]
		if timer.has("start_ms"):
			timer.start_ms = int(timer.start_ms) + delta_ms


func _deadline_ms(start_ms: int) -> int:
	return start_ms + _duration_ms + (GRACE_MS if _kind == Kind.DISCARD else 0)
