extends Node
## 主线程权威。网络仅转交已认证连接的操作；演出完成和时钟接口只在本机运行。

signal view_changed(connection_id: String, view: Dictionary)
signal dice_updated(state: Dictionary)
signal presentation_required(cue: Dictionary)
signal room_closed()

const Match = preload("res://src/session/MatchSession.gd")
const Room = preload("res://src/session/RoomSession.gd")
const Pace = preload("res://src/presentation/GamePace.gd")
const Clock = preload("res://src/session/TurnClock.gd")
const Scheduler = preload("res://src/ai/AiScheduler.gd")
const Dice = preload("res://src/runtime/DiceRoll.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Submitter = preload("res://src/runtime/RecordSubmitter.gd")
const OpeningDeal = preload("res://src/presentation/OpeningDeal.gd")
const ANIMATION_WAIT_MS := 10000

var clock_msec: Callable = Time.get_ticks_msec
var _session: Match
var _clock: Clock
var _worker := Scheduler.new()
var _dice: Dice
var _rng := RandomNumberGenerator.new()
var _connections := {} # connection ID → seat
var _active_mics := {} # seats whose current authenticated connection reports live capture
var _presence := {} # authenticated connection → foreground synchronization state
var _state := {}
var _instance := ""
var _mode := ""
var _first_dealer := -1
var _level := "medium"
var _next_level := "medium"
var _ai_delay := Pace.AI_WAIT_MS
var _discard_ms := Clock.DISCARD_MS
var _response_ms := Clock.RESPONSE_MS
var _external := false
var _durations := {"dealt": ceili(OpeningDeal.nominal_gate_seconds() * 1000), "turn": Pace.ACTION_MS, "response": Pace.ACTION_MS, "ready_draw": Pace.ACTION_MS}
var _prepare_at := -1
var _start_delay_ms := 0
var _require_start := false
var _first_start_requested := false
var _roll_valid := false
var _paused_at := -1
var _paused_total := 0
var _finished_while_paused := {}
var _closed := false
var _cues := {}
var _released := {}
var _submitted_jobs := {}
var _decisions := {}
var _expired := {}
var _animation_expired := {}
var _last_clock_display := {}
var _last_dice_frame := -1
var _wall_offsets := [0.0, 0.0, 0.0, 0.0]
var _last_locked_dice := {}
var _styles_by_player := {}
var _deal_styles := ["a", "a", "a", "a"]
var _submitter := Submitter.new()

func configure(room_number: String, mode: String, first_dealer: int, settings: Dictionary = {}) -> bool:
	if _session != null or room_number.is_empty() or mode not in ["solo", "lan", "online"] or first_dealer not in range(4):
		return false
	_level = str(settings.get("difficulty", "medium"))
	_next_level = _level
	_ai_delay = int(settings.get("ai_delay_ms", Pace.AI_WAIT_MS))
	_discard_ms = int(settings.get("discard_ms", Clock.DISCARD_MS))
	_response_ms = int(settings.get("response_ms", Clock.RESPONSE_MS))
	if _level not in ["low", "medium", "high"] or _ai_delay < 0 or _discard_ms <= 0 or _response_ms <= 0:
		return false
	_external = settings.get("external_presentation", mode != "solo")
	var durations: Dictionary = settings.get("presentation_ms", {})
	for key in _durations:
		if int(durations.get(key, _durations[key])) < 0:
			return false
		_durations[key] = int(durations.get(key, _durations[key]))
	_mode = mode
	_start_delay_ms = maxi(0, int(settings.get("start_delay_ms", 0)))
	_require_start = bool(settings.get("require_start", false)) and mode != "solo"
	_first_dealer = first_dealer
	_session = Match.new(room_number)
	if settings.has("owner_token_hash"):
		_session._room.reserve_owner(str(settings.owner_token_hash).hex_decode())
	_state = _session.authority_status(_now())
	_instance = _state.room.room_instance_id
	var record_url := OS.get_environment("DONGXIU_RECORD_URL") if mode == "online" else str(settings.get("record_url", ""))
	_submitter.configure(_instance, mode, record_url, str(settings.get("record_storage", "user://record-outbox-v1")))
	_clock = Clock.new(_instance)
	_rng.randomize()
	return true

func _ready() -> void:
	add_child(_submitter)
	_submitter.status_changed.connect(func(_number, _submission): _publish())
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(2, 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	_dice = Dice.new()
	viewport.add_child(_dice)
	_dice.result_ready.connect(_dice_settled)

func _now() -> int:
	return (_paused_at if _paused_at >= 0 else int(clock_msec.call())) - _paused_total

func join(player_id: String, nickname: String, connection_id: String, profile: Dictionary = {}, away: bool = false, presence_revision: int = 0, owner_token: String = "", requested_seat: int = -1) -> Dictionary:
	if _closed or _session == null:
		return {}
	var joined := _session.join(player_id, nickname, connection_id, _now(), profile, owner_token, requested_seat)
	if joined.is_empty():
		return {}
	if _require_start and _session._room.snapshot(_now()).round_number == 0:
		_session.set_ready(connection_id, true, _now())
	_bound(connection_id, joined.ticket.seat, away, presence_revision, false)
	return {"ticket": joined.ticket, "view": view_for(connection_id)}

func resume(instance_id: String, player_id: String, token: String, connection_id: String, profile: Dictionary = {}, away: bool = false, presence_revision: int = 0) -> Dictionary:
	if _closed or _session == null:
		return {}
	var view := _session.resume(instance_id, player_id, token, connection_id, _now(), profile)
	if view.is_empty():
		return {}
	if _connections.get(connection_id, -1) != view.seat:
		_bound(connection_id, view.seat, away, presence_revision, _mode != "solo" and not away)
	elif not profile.is_empty():
		_publish()
	return view_for(connection_id)

func _bound(connection_id: String, seat: int, away: bool, revision: int, needs_ack: bool) -> void:
	for old in _connections.keys():
		if _connections[old] == seat:
			_connections.erase(old)
			_presence.erase(old)
	_connections[connection_id] = seat
	_presence[connection_id] = {"away": away or needs_ack, "revision": revision, "needs_ack": needs_ack}
	if _cues.has(seat):_cues[seat].erase("received")
	if _roll_valid and _dice.phase == "rolling":
		_dice.process_mode = Node.PROCESS_MODE_INHERIT
	_active_mics.erase(seat)
	_cancel_job(seat)
	_refresh()

func disconnect_human(connection_id: String, intentional: bool = false) -> bool:
	if _closed or not _connections.has(connection_id) or not _session.disconnect_human(connection_id, _now(), intentional):
		return false
	_cancel_job(_connections[connection_id])
	_active_mics.erase(_connections[connection_id])
	_connections.erase(connection_id)
	_presence.erase(connection_id)
	if _mode == "solo":
		shutdown()
	else:
		_refresh()
	return true

func set_ready(connection_id: String, ready: bool) -> bool:
	if _closed or not _connections.has(connection_id) or not _session.set_ready(connection_id, ready, _now()):
		return false
	_refresh()
	return true

func start_first_round(connection_id: String) -> bool:
	if _closed or not _connections.has(connection_id) or _roll_valid or _first_start_requested:
		return false
	var room: Dictionary = _session._room.snapshot(_now())
	if room.round_number != 0 or room.seats[_connections[connection_id]].player_id != room.owner_player_id:
		return false
	for member in room.seats:
		if member.connected and not member.ready:
			return false
	_first_start_requested = true
	_refresh()
	return true

func move_to_empty_seat(connection_id: String, seat: int) -> bool:
	if _closed or not _connections.has(connection_id) or not _session.move_to_empty_seat(connection_id, seat, _now()):
		return false
	_active_mics.erase(_connections[connection_id])
	_connections[connection_id] = seat
	_refresh()
	return true

func set_draw_style(connection_id: String, style: String) -> bool:
	if style not in ["a", "b", "random"] or _closed or not _connections.has(connection_id):
		return false
	var own := _session.view_for(connection_id, _now())
	if own.is_empty(): return false
	_styles_by_player[own.room.seats[own.seat].player_id] = style
	return true

func set_player_profile(connection_id: String, profile: Dictionary) -> bool:
	if _closed or not _connections.has(connection_id):
		return false
	var change := _session.set_player_profile(connection_id, profile, _now())
	if change > 0:
		_publish()
	return change >= 0

func set_auto_play(connection_id: String, instance: String, number: int, enabled: bool) -> bool:
	if _closed or not _connections.has(connection_id):
		return false
	var change := _session.set_auto_play(connection_id, instance, number, enabled, _now())
	if change > 0:
		var seat: int = _connections[connection_id]
		_cancel_job(seat)
		_refresh()
	return change >= 0

func set_difficulty(connection_id: String, instance: String, level: String) -> bool:
	if _closed or instance != _instance or level not in ["low", "medium", "high"]:
		return false
	var view := _session.view_for(connection_id, _now())
	if view.is_empty() or view.room.owner_player_id != view.room.seats[view.seat].player_id:
		return false
	_next_level = level
	if view.room.phase != Room.Phase.IN_ROUND:
		_level = level
	_publish()
	return true

func set_hand_display(connection_id: String, instance: String, number: int, prompt: int, display: Dictionary) -> bool:
	if _closed or not _connections.has(connection_id):
		return false
	var change := _session.set_hand_display(connection_id, instance, number, prompt, display, _now())
	if change > 0:
		_publish()
	return change >= 0

func public_room() -> Dictionary:
	if _closed or _session == null: return {}
	var room: Dictionary = _session.authority_status(_now()).room.duplicate(true)
	_project_connection_state(room)
	return room

func set_mic_active(connection_id: String, instance: String, seat: int, active: bool) -> bool:
	if _closed or _mode not in ["lan", "online"] or instance != _instance or seat not in range(4) or authenticated_seat(connection_id) != seat:
		return false
	if active and connection_away(connection_id): return false
	if _active_mics.has(seat) != active:
		if active:
			_active_mics[seat] = true
		else:
			_active_mics.erase(seat)
		_publish()
	return true

func _project_connection_state(room: Dictionary) -> void:
	for seat in room.seats.size():
		room.seats[seat].mic_active = _active_mics.has(seat)
		room.seats[seat].away = room.seats[seat].ai_id < 0 and not room.seats[seat].connected
	for connection_id in _connections:
		room.seats[_connections[connection_id]].away = _presence[connection_id].away

func connection_away(connection_id: String) -> bool:
	return _presence.get(connection_id, {}).get("away", false)

func set_application_away(connection_id: String, instance: String, revision: int, away: bool) -> bool:
	if _closed or _mode == "solo" or instance != _instance or not _presence.has(connection_id) or revision <= int(_presence[connection_id].revision):
		return false
	_presence[connection_id] = {"away": true, "revision": revision, "needs_ack": not away}
	if away:
		_active_mics.erase(_connections[connection_id])
		_publish()
	else:
		view_changed.emit(connection_id, view_for(connection_id))
	return true

func acknowledge_foreground_view(connection_id: String, instance: String, revision: int) -> bool:
	var state: Dictionary = _presence.get(connection_id, {})
	if _closed or instance != _instance or not state.get("needs_ack", false) or state.revision != revision:
		return false
	state.away = false
	state.needs_ack = false
	_publish()
	return true

func authenticated_seat(connection_id: String) -> int:
	return int(_connections.get(connection_id, -1)) if not _closed else -1

func request_record_submission(connection_id: String, instance: String, number: int) -> bool:
	if _closed or instance != _instance or not _connections.has(connection_id) or number < 1 or number != _state.room.round_number: return false
	var own := _session.view_for(connection_id, _now())
	if own.is_empty() or (_state.phase == "settled" and int(own.get("settlement", {}).get("viewer_seat", -1)) < 0): return false
	if not _submitter.enqueue(number): return false
	if _state.phase == "settled": _submitter.complete(_session.last_completed_record())
	return true

func submit(connection_id: String, instance_id: String, number: int, prompt: int, action: String, tile_id: int = -1) -> bool:
	if _closed or _paused_at >= 0 or not _connections.has(connection_id) or not _matches(instance_id, number, prompt):
		return false
	var seat: int = _connections[connection_id]
	if connection_away(connection_id) or not _released.has(seat) or _animation_expired.has(seat) or _state.room.seats[seat].auto_play:
		return false
	var now := _now()
	var timer := _clock.timing_for(number, prompt, seat, now)
	if not timer.has("deadline_ms") or now > timer.deadline_ms:
		return false
	if not _session.submit(connection_id, instance_id, number, prompt, action, tile_id, now):
		return false
	if action == "sort" and _session.authority_status(now).prompt_id == prompt:
		_cancel_job(seat)
		_refresh()
		return true
	_accepted(number, prompt, seat)
	return true

func _matches(instance_id: String, number: int, prompt: int) -> bool:
	return not _state.is_empty() and instance_id == _instance and number == _state.room.round_number and prompt == _state.prompt_id

func _accepted(number: int, prompt: int, seat: int) -> void:
	_animation_expired.erase(seat)
	_clock.action_accepted(number, prompt, seat)
	_released.erase(seat)
	_expired.erase(seat)
	_cancel_job(seat)
	_refresh()

func _cancel_job(seat: int) -> void:
	_worker.cancel_seat(seat)
	_submitted_jobs.erase(seat)
	_decisions.erase(seat)

func view_for(connection_id: String) -> Dictionary:
	if _closed or not _connections.has(connection_id):
		return {}
	var view := _session.view_for(connection_id, _now())
	if view.is_empty():
		return {}
	var seat: int = view.seat
	_project_connection_state(view.room)
	view.presence = _presence[connection_id].duplicate()
	view.room.difficulty = _level
	view.room.next_difficulty = _next_level
	view.room.mode = _mode
	view.room.preparation_remaining_ms = maxi(0, _prepare_at - _now()) if _prepare_at >= 0 else -1
	view.room.rolling = _roll_valid
	view.room.requires_start = _require_start and view.room.round_number == 0 and not _first_start_requested
	view.paused = _paused_at >= 0
	view.record_submission = _submitter.state(int(view.room.round_number))
	if _roll_valid and _dice != null:
		view.dice = _dice.snapshot()
	else:
		view.dice = _last_locked_dice.duplicate(true)
	if view.round.is_empty() or _roll_valid:
		var empty_rows := []
		for position in 4:
			empty_rows.append({"seat": position, "hand_count": 0, "hand": [], "draw_id": -1,
				"has_draw": false, "melds": [], "discards": [], "public_order": [], "ready": false})
		view.round = {"phase": "dice" if _roll_valid else "preparing", "turn": -1, "prompt_id": -1,
			"players": empty_rows, "choices": {}, "viewer_seat": seat, "wall_remaining": 108,
			"wall_slots": range(108), "last_discard": {}, "wall_offsets": [0.0, 0.0, 0.0, 0.0],
			"dealer": (_first_dealer if view.room.round_number == 0 else view.room.next_dealer_seat) if _roll_valid else -1}
		view.erase("settlement")
		return view
	view.round.wall_offsets = _wall_offsets.duplicate()
	view.round.deal_styles = _deal_styles.duplicate()
	if _cues.has(seat):
		view.presentation = _cues[seat].duplicate()
	if not view.round.is_empty():
		var timed_out:bool=_expired.has(seat) and _now()>int(_expired[seat].deadline_ms)
		if not _released.has(seat) or timed_out or _animation_expired.has(seat):
			view.round.choices = {}
		var timer_seat: int = view.round.turn if _state.phase == "turn" and not _state.response_clock else seat
		view.clock = _clock.timing_for(view.room.round_number, view.round.prompt_id, timer_seat, _now())
		if _animation_expired.has(seat):view.clock={"phase":"waiting_animation","remaining_ms":-1,"reminder":false,"ai_deciding":true}
	return view

func center_wall(connection_id: String, wall_seat: int) -> bool:
	if _closed or wall_seat not in range(4) or not _connections.has(connection_id) or _roll_valid or _paused_at >= 0:
		return false
	var view := _session.view_for(connection_id, _now())
	if view.is_empty() or view.round.is_empty():
		return false
	for segment in Wall.SEGMENTS:
		if segment.seat != wall_seat:
			continue
		var first: int = segment.columns
		var last := -1
		for id in view.round.wall_slots:
			var local: int = int(id) - int(segment.start)
			if local >= 0 and local < int(segment.columns) * 2:
				first = mini(first, local / 2)
				last = maxi(last, local / 2)
		if last < 0:
			return false
		_wall_offsets[wall_seat] = (int(segment.columns) - 1 - first - last) / 2.0
		_publish()
		return true
	return false

func _publish() -> void:
	for connection in _connections.keys():
		var view := view_for(connection)
		if not view.is_empty():
			view_changed.emit(connection, view)

func _refresh() -> void:
	var previous := _state
	_state = _session.authority_status(_now())
	if _state.is_empty():
		shutdown()
		room_closed.emit()
		return
	_reconsider_opening()
	if _state.phase == "settled": _submitter.complete(_session.last_completed_record())
	if previous.get("room", {}).get("round_number", -1) != _state.room.round_number:
		_level = _next_level
		_wall_offsets = [0.0, 0.0, 0.0, 0.0]
		_submitter.retry_pending()
	var new_prompt: bool = previous.is_empty() or previous.room.round_number != _state.room.round_number or previous.prompt_id != _state.prompt_id
	var new_cues := []
	if new_prompt:
		for seat in 4:
			_cancel_job(seat)
		_released.clear()
		_expired.clear()
		_animation_expired.clear()
		_cues.clear()
		_last_clock_display.clear()
		var number: int = _state.room.round_number
		var prompt: int = _state.prompt_id
		if _state.phase == "settled":
			_clock.end_round(number)
		elif not _state.eligible.is_empty():
			var seats: Array[int] = []
			seats.assign(_state.eligible)
			if _state.phase in ["response", "turn"]:
				_clock.begin_prompt(number, prompt, Clock.Kind.RESPONSE if _state.response_clock else Clock.Kind.DISCARD, seats, _response_ms if _state.response_clock else _discard_ms)
			for seat in seats:
				var elapsed_draw: bool = previous.get("phase") == "ready_draw" and _state.phase == "turn" and _state.response_clock
				var duration := 0 if elapsed_draw else int(_durations[_state.phase])
				var cue := {"room_instance_id": _instance, "round_number": number, "prompt_id": prompt,
					"seat": seat, "phase": _state.phase, "duration_ms": duration, "start_ms": _now()}
				_cues[seat] = cue
				new_cues.append(cue)
	_publish()
	for cue in new_cues:
		if _matches(cue.room_instance_id, cue.round_number, cue.prompt_id) and _cues.has(cue.seat):
			if cue.duration_ms == 0:
				finish_presentation(_instance, cue.round_number, cue.prompt_id, cue.seat)
			else:
				presentation_required.emit(cue.duplicate())

func finish_presentation(instance_id: String, number: int, prompt: int, seat: int) -> bool:
	if _closed or not _matches(instance_id, number, prompt) or not _cues.has(seat):
		return false
	if _paused_at >= 0:
		_finished_while_paused[seat] = _cues[seat].duplicate()
		return true
	_cues.erase(seat)
	if _state.phase == "dealt" or _state.phase == "ready_draw":
		var ok := _session.begin_dealer_turn(instance_id, number, prompt, _now()) if _state.phase == "dealt" else _session.finish_draw_animation(instance_id, number, prompt, seat, _now())
		if ok:
			_refresh()
		return ok
	if not _clock.animation_finished(number, prompt, seat, _now()):
		return false
	_released[seat] = _now()
	_publish()
	return true

func _waits_for_receipt(seat: int) -> bool:
	if not _external or _mode == "solo":return false
	var member:Dictionary=_state.room.seats[seat]
	if member.ai_id>=0 or member.auto_play or not member.connected:return false
	for connection in _connections:
		if _connections[connection]==seat:return not connection_away(connection)
	return false

func acknowledge_presentation(connection_id: String, instance_id: String, number: int, prompt: int) -> bool:
	var seat:=authenticated_seat(connection_id)
	if seat<0 or connection_away(connection_id) or not _matches(instance_id,number,prompt) or not _cues.has(seat):return false
	var cue:Dictionary=_cues[seat]
	if not _waits_for_receipt(seat) or _now()>=int(cue.start_ms)+ANIMATION_WAIT_MS:return false
	cue.received=true
	if _now()>=int(cue.start_ms)+int(cue.duration_ms):finish_presentation(instance_id,number,prompt,seat)
	return true

func _animation_timeout(cue: Dictionary) -> void:
	if not _matches(cue.room_instance_id,cue.round_number,cue.prompt_id) or not _cues.has(cue.seat):return
	var seat:int=cue.seat
	var was_choice:bool=_state.phase in ["turn","response"]
	if was_choice:
		_animation_expired[seat]={"room_instance_id":_instance,"round_number":_state.room.round_number,
			"prompt_id":_state.prompt_id,"seat":seat,"deadline_ms":_now()}
	# 发牌／报听摸牌先完成自动阶段，再把授权限于紧接着的这一次真实选择。
	finish_presentation(cue.room_instance_id,cue.round_number,cue.prompt_id,seat)
	if not _state.eligible.has(seat) or _state.phase not in ["turn","response"]:return
	_animation_expired[seat]={"room_instance_id":_instance,"round_number":_state.room.round_number,
		"prompt_id":_state.prompt_id,"seat":seat,"deadline_ms":_now()}
	if _cues.has(seat):finish_presentation(_instance,_state.room.round_number,_state.prompt_id,seat)
	_publish()

func _reconsider_opening() -> void:
	var room: Dictionary = _state.room
	if room.phase == Room.Phase.IN_ROUND:
		_prepare_at = -1
		return
	var ready := false
	for occupant in room.seats:
		if occupant.connected:
			ready = true
			if not occupant.ready:
				ready = false
				break
	if not ready or room.owner_player_id.is_empty() or (_require_start and room.round_number == 0 and not _first_start_requested):
		_prepare_at = -1
		_roll_valid = false
	elif _prepare_at == -1 and not _roll_valid:
		_prepare_at = _now() + _start_delay_ms

func _dice_settled(_red: int, _white: int) -> void:
	if _closed:
		return
	if _roll_valid:
		_roll_valid = false
		_prepare_at = -1
		if _session.start_round(_dice, Catalog.values(_rng.randi()), _now(), _first_dealer):
			var occupants: Array = _session.authority_status(_now()).room.seats
			for seat in 4:
				var style: String = _styles_by_player.get(occupants[seat].player_id, "a")
				_deal_styles[seat] = ["a", "b"][_rng.randi_range(0, 1)] if style == "random" else style
			_last_locked_dice = _dice.snapshot()
			dice_updated.emit(_last_locked_dice.duplicate(true))
	_refresh()

func _process(_delta: float) -> void:
	if _closed or _session == null or _paused_at >= 0:
		return
	var now := _now()
	if not _session.is_open(now):
		shutdown()
		room_closed.emit()
		return
	if _prepare_at >= 0 and now >= _prepare_at and _dice.phase != "rolling" and not _connections.is_empty():
		_prepare_at = -1
		_roll_valid = _dice.roll()
		_last_dice_frame = -1
		_publish()
	if _roll_valid and _dice.phase == "rolling":
		var roll := _dice.snapshot()
		if roll.frame >= _last_dice_frame + 3 or _last_dice_frame == -1:
			_last_dice_frame = roll.frame
			dice_updated.emit(roll)
	for cue in _cues.values():
		if not _matches(cue.room_instance_id,cue.round_number,cue.prompt_id):continue
		if _waits_for_receipt(cue.seat):
			if cue.get("received",false) and now>=cue.start_ms+cue.duration_ms:
				finish_presentation(_instance,cue.round_number,cue.prompt_id,cue.seat)
			elif now>=cue.start_ms+ANIMATION_WAIT_MS:_animation_timeout(cue)
		elif (not _external or _mode!="solo") and now>=cue.start_ms+cue.duration_ms:
			finish_presentation(_instance,cue.round_number,cue.prompt_id,cue.seat)
	if _state.phase in ["turn", "response"]:
		_pump_actions(now)
	_update_display(now)

func _pump_actions(now: int) -> void:
	var number: int = _state.room.round_number
	var prompt: int = _state.prompt_id
	for intent in _clock.tick(number, prompt, now):
		_expired[intent.seat] = intent
	for seat in _released.keys():
		if not _matches(_instance, number, prompt):
			return
		var intent: Dictionary = _expired.get(seat, {})
		var late: bool = not intent.is_empty() and now > intent.deadline_ms
		if late and intent.action == "pass" and not _animation_expired.has(seat):
			if _session.expire_response_for(_instance, number, prompt, seat, now):
				_accepted(number, prompt, seat)
			continue
		var occupant: Dictionary = _state.room.seats[seat]
		if late and _submitted_jobs.get(seat) == "auto_play":
			_cancel_job(seat)
		if _submitted_jobs.has(seat):
			continue
		var job := {}
		if _animation_expired.has(seat):
			job=_session.animation_timeout_job(_animation_expired[seat],now)
		elif occupant.ai_id >= 0 or (occupant.auto_play and not late):
			job = _session.ai_job(seat, now)
		elif late:
			job = _session.discard_timeout_job(intent, now)
		if not job.is_empty() and _worker.enqueue(job, _level):
			_submitted_jobs[seat] = "animation_timeout" if job.has("animation_nonce") else ("auto_play" if occupant.auto_play and not late else "other")
	for work in _worker.poll():
		_decisions[work.job.seat] = work
	for seat in _decisions.keys():
		if not _decisions.has(seat) or not _released.has(seat) or now < _released[seat] + _ai_delay:
			continue
		var work: Dictionary = _decisions[seat]
		var job: Dictionary = work.job
		var action: Dictionary = work.decision
		_decisions.erase(seat)
		_submitted_jobs.erase(seat)
		var ok:bool
		if job.has("animation_nonce"):ok=_session.submit_animation_timeout(job,action.action,action.tile_id,now)
		else:ok=_session.submit_timeout_discard(job, action.tile_id, now) if job.has("nonce") else _session.submit_ai(job, action.action, action.tile_id, now)
		if ok:
			_accepted(job.round_number, job.prompt_id, seat)

func _update_display(now: int) -> void:
	var display := {}
	if _prepare_at >= 0:
		display["preparation"] = ceili((_prepare_at - now) / 1000.0)
	for seat in _released:
		var timer := _clock.timing_for(_state.room.round_number, _state.prompt_id, seat, now)
		if not timer.is_empty():
			display[seat] = [timer.phase, ceili(timer.remaining_ms / 1000.0), timer.reminder]
	if display != _last_clock_display:
		_last_clock_display = display
		_publish()

func set_solo_paused(paused: bool) -> bool:
	if _mode != "solo" or _closed:
		return false
	if paused == (_paused_at >= 0):
		return true
	if paused:
		_paused_at = int(clock_msec.call())
	else:
		_paused_total += int(clock_msec.call()) - _paused_at
		_paused_at = -1
	if _dice != null:
		_dice.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	if not paused:
		var finished := _finished_while_paused.values()
		_finished_while_paused.clear()
		for cue in finished:
			finish_presentation(cue.room_instance_id, cue.round_number, cue.prompt_id, cue.seat)
	_publish()
	return true

func last_completed_record() -> Dictionary:
	return _session.last_completed_record() if _session != null else {}

## 权威端全量快照：含暗手与剩余牌墙。只发给下家真人的备用副本，不进入玩家视图。
func export_authority() -> Dictionary:
	if _session == null:
		return {}
	var state := {"mode": _mode, "instance": _instance, "first_dealer": _first_dealer,
		"discard_ms": _discard_ms, "response_ms": _response_ms, "durations": _durations.duplicate(true),
		"level": _level, "next_level": _next_level, "ai_delay": _ai_delay, "external": _external,
		"session": _session.export_authority(), "clock": _clock.export_authority(),
		"dice": _dice.export_authority(), "at_ms": _now(),
		"styles_by_player": _styles_by_player.duplicate(true), "deal_styles": _deal_styles.duplicate(),
		"last_locked_dice": _last_locked_dice.duplicate(true), "prepare_at": _prepare_at, "start_delay_ms": _start_delay_ms, "roll_valid": _roll_valid,
		"require_start": _require_start, "first_start_requested": _first_start_requested,
		"rng_state": _rng.state, "cues": _cues.duplicate(true), "released": _released.duplicate(),
		"wall_offsets": _wall_offsets.duplicate(),
		"expired": _expired.duplicate(true), "animation_expired": _animation_expired.duplicate(true)}
	return state

## 备用副本升级为新权威时调用；必须在 configure() 之前、节点 _ready() 之后执行。
func restore_authority(state: Dictionary, settings: Dictionary = {}) -> bool:
	if _session != null or _dice == null or not state.get("session") is Dictionary:
		print("[restore] early reject session=", _session != null, " dice=", _dice != null)
		return false
	if not state.get("clock") is Dictionary or not state.get("dice") is Dictionary:
		print("[restore] missing clock/dice")
		return false
	_mode = str(state.get("mode", "lan"))
	_instance = str(state.get("instance", ""))
	_first_dealer = int(state.get("first_dealer", -1))
	_discard_ms = int(state.get("discard_ms", Clock.DISCARD_MS))
	_response_ms = int(state.get("response_ms", Clock.RESPONSE_MS))
	_level = str(state.get("level", "medium"))
	_next_level = str(state.get("next_level", _level))
	if _level not in ["low", "medium", "high"] or _next_level not in ["low", "medium", "high"]:
		return false
	_ai_delay = int(state.get("ai_delay", Pace.AI_WAIT_MS))
	_external = bool(state.get("external", false))
	_start_delay_ms = maxi(0, int(state.get("start_delay_ms", 0)))
	_require_start = bool(state.get("require_start", false))
	_first_start_requested = bool(state.get("first_start_requested", false))
	for key in _durations:
		_durations[key] = int(state.get("durations", {}).get(key, _durations[key]))
	if _mode not in ["solo", "lan", "online"] or _first_dealer not in range(4) or _discard_ms <= 0 or _response_ms <= 0:
		print("[restore] settings reject mode=", _mode, " dealer=", _first_dealer)
		return false
	var delta := _now() - int(state.get("at_ms", _now()))
	var restored = Match.new(str(state.session.get("room", {}).get("room_number", "0000")))
	if not restored.restore_authority(state.session, delta):
		print("[restore] session restore failed")
		return false
	_clock = Clock.new(_instance)
	if not _clock.restore_authority(state.clock):
		print("[restore] clock restore failed")
		return false
	_clock.rebase_times(delta)
	if int(state.get("prepare_at", -1)) >= 0:
		_prepare_at = int(state.prepare_at) + delta
	if not _dice.apply_authority(state.dice):
		print("[restore] dice apply failed phase=", state.dice.get("phase"))
		return false
	_roll_valid = bool(state.get("roll_valid", false))
	if _roll_valid and _dice.phase == "rolling":
		# 等待接任者绑定旧成员票据，避免骰子先停稳却无法开局。
		_dice.process_mode = Node.PROCESS_MODE_DISABLED
	_wall_offsets = state.get("wall_offsets", [0.0, 0.0, 0.0, 0.0]).duplicate()
	_styles_by_player = state.get("styles_by_player", {}).duplicate(true)
	var styles: Array = state.get("deal_styles", ["a", "a", "a", "a"])
	_deal_styles = []
	for style in styles:
		_deal_styles.append(str(style) if str(style) in ["a", "b"] else "a")
	_last_locked_dice = state.get("last_locked_dice", {}).duplicate(true)
	_cues = state.get("cues", {}).duplicate(true)
	for connection in _cues:
		_cues[connection].start_ms = int(_cues[connection].start_ms) + delta
	_released = state.get("released", {}).duplicate()
	for seat in _released:
		_released[seat] = int(_released[seat]) + delta
	_expired = state.get("expired", {}).duplicate(true)
	_animation_expired = state.get("animation_expired", {}).duplicate(true)
	for intent in _animation_expired.values():intent.deadline_ms=int(intent.deadline_ms)+delta
	for intent in _expired.values():
		intent.deadline_ms = int(intent.deadline_ms) + delta
	_submitted_jobs.clear()
	_decisions.clear()
	_last_clock_display.clear()
	var rng_value: Variant = state.get("rng_state", -1)
	if rng_value is not int:
		print("[restore] rng reject ", rng_value)
		return false
	_rng.state = int(rng_value)
	var record_url := OS.get_environment("DONGXIU_RECORD_URL") if _mode == "online" else str(settings.get("record_url", ""))
	_submitter.configure(_instance, _mode, record_url, str(settings.get("record_storage", "user://record-outbox-v1")))
	_session = restored
	_state = _session.authority_status(_now())
	_closed = false
	# 不调用 _refresh()：它的 new_prompt 分支会清掉已恢复的 cues/released/时钟起点。
	# 后续真人 resume() 会以非空 previous 状态走保留分支，仅补发当前提示。
	return true

func shutdown() -> void:
	if _closed:
		return
	_closed = true
	_worker.shutdown()
	_decisions.clear()
	_expired.clear()
	_animation_expired.clear()
	_cues.clear()
	_finished_while_paused.clear()
	_connections.clear()
	_presence.clear()
	if _dice != null:
		_dice.process_mode = Node.PROCESS_MODE_DISABLED

func _exit_tree() -> void:
	shutdown()

func directory_auth_state() -> Dictionary:
	if _closed or _mode != "online":
		return {}
	return _session.directory_auth_state(_now())
