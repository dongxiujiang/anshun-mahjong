extends RefCounted
## 单机与在线权威端共用。网络层只分发连接视图。

const Room = preload("res://src/session/RoomSession.gd")
const Round = preload("res://src/domain/Round.gd")
const Dice = preload("res://src/runtime/DiceRoll.gd")
const Score = preload("res://src/anshun/scoring/ScoringEngine.gd")
const Protocol = preload("res://src/domain/Protocol.gd")
const Dealer = preload("res://src/anshun/DealerSelection.gd")
const Record = preload("res://src/session/RoundRecord.gd")
const HandDisplay = preload("res://src/presentation/SharedHandDisplay.gd")

var _room: Room
var _round: Round
var _display: HandDisplay
var _control_revision := [0, 0, 0, 0]
var _number := 0
var _instance := ""
var _carry := 1
var _used_rolls := {}
var _last_settlement := {}
var _record: Record
var _last_record := {} # 全牌墙与指令只保留在权威端，禁止加入连接视图。
var _pending_timeout := {} # 权威端签发的一次弃牌工作；不传给任何客户端。
var _animation_jobs := {} # 动画超时按座位签发，仅授权当前提示的一次合法判断。
var _rng := RandomNumberGenerator.new()

func _init(room_number: String) -> void:
	_room = Room.new(room_number)
	_instance = _room.snapshot(0).get("room_instance_id", "")
	_rng.randomize()

func join(player_id: String, nickname: String, connection_id: String, now_ms: int, profile: Dictionary = {}, owner_token: String = "", requested_seat: int = -1) -> Dictionary:
	var ticket := _room.join(player_id, nickname, connection_id, now_ms, profile, owner_token, requested_seat)
	if ticket.is_empty():
		return {}
	_control_revision[ticket.seat] += 1
	if _display != null:
		_display.clear_gesture(ticket.seat)
	return {"ticket": ticket, "view": view_for(connection_id, now_ms)}

func resume(instance_id: String, player_id: String, token: String, connection_id: String, now_ms: int, profile: Dictionary = {}) -> Dictionary:
	var previous_seat := _room.seat_for_connection(connection_id, now_ms)
	var restored := _room.resume(instance_id, player_id, token, connection_id, now_ms, profile)
	if restored.is_empty():
		return {}
	if previous_seat != restored.seat:
		_control_revision[restored.seat] += 1
		if _display != null:
			_display.clear_gesture(restored.seat)
	return view_for(connection_id, now_ms)

func set_player_profile(connection_id: String, profile: Dictionary, now_ms: int) -> int:
	return _room.set_player_profile(connection_id, profile, now_ms)

func set_auto_play(connection_id: String, instance: String, number: int, enabled: bool, now_ms: int) -> int:
	var changed := _room.set_auto_play(connection_id, instance, number, enabled, now_ms)
	if changed > 0:
		var seat := _room.seat_for_connection(connection_id, now_ms)
		_control_revision[seat] += 1
	return changed

func disconnect_human(connection_id: String, now_ms: int, intentional: bool = false) -> bool:
	var seat := _room.seat_for_connection(connection_id, now_ms)
	if seat < 0:
		return false
	var changed := _room.leave_human(connection_id, now_ms) if intentional else _room.disconnect_human(connection_id, now_ms)
	if not changed:
		return false
	_control_revision[seat] += 1
	if _display != null:
		_display.clear_gesture(seat)
	return true

func view_for(connection_id: String, now_ms: int) -> Dictionary:
	var seat := _room.seat_for_connection(connection_id, now_ms)
	if seat < 0:
		return {}
	var view := {"seat": seat, "room": _room.snapshot(now_ms), "round": {}}
	view.room.merge({"variant_id": Protocol.VARIANT_ID, "rules_version": Protocol.RULES_VERSION,
		"protocol_version": Protocol.PROTOCOL_VERSION, "record_version": Protocol.RECORD_VERSION})
	if _round != null:
		view.round = _round.snapshot_for(seat)
		_display.project(_round, view.round)
	if not _last_settlement.is_empty() and _last_settlement.round_number == _number:
		view.settlement = _last_settlement.duplicate(true)
		# 账本列和其 next_dealer_seat 始终使用终局时的座位；准备阶段的实时庄位以 room 为准。
		# 准备期新加入者未参加本局，没有对应的个人结算行。
		view.settlement.viewer_seat = -1
		var player_id: String = view.room.seats[seat].player_id
		for old_seat in _last_settlement.seats.size():
			if _last_settlement.seats[old_seat].player_id == player_id:
				view.settlement.viewer_seat = old_seat
				break
	return view

func set_ready(connection_id: String, ready: bool, now_ms: int) -> bool:
	return _room.set_ready(connection_id, ready, now_ms)

func set_hand_display(connection_id: String, instance: String, number: int, prompt: int, display: Dictionary, now_ms: int) -> int:
	var seat := _room.seat_for_connection(connection_id, now_ms)
	if seat < 0 or not _live(instance, number, prompt, now_ms):
		return -1
	return _display.accept(seat, display)

func move_to_empty_seat(connection_id: String, destination: int, now_ms: int) -> bool:
	var seat := _room.seat_for_connection(connection_id, now_ms)
	if seat < 0 or not _room.move_to_empty_seat(connection_id, destination, now_ms):
		return false
	_control_revision[seat] += 1
	_control_revision[destination] += 1
	return true

## 仅接受当前权威投掷的最终结果。洗牌、首次庄位均由权威调用方提供。
func start_round(dice: Dice, shuffled_values: Array, now_ms: int, first_dealer: int = -1) -> bool:
	var room := _room.snapshot(now_ms)
	if room.is_empty() or room.phase == Room.Phase.IN_ROUND or not is_instance_valid(dice) or not dice.authoritative or dice.phase != "settled":
		return false
	var roll := dice.record_snapshot()
	var dice_node := dice.get_instance_id()
	if roll.result.size() != 2 or roll.roll_id <= int(_used_rolls.get(dice_node, 0)):
		return false
	var dealer: int = first_dealer if room.phase == Room.Phase.FIRST_PREPARATION else room.next_dealer_seat
	var candidate := Round.new()
	if not candidate.start(dealer, int(roll.result[0]), int(roll.result[1]), shuffled_values, _carry):
		return false
	if not _room.start_round(now_ms, dealer):
		return false
	_used_rolls[dice_node] = roll.roll_id
	_number = room.round_number + 1
	_round = candidate
	_display = HandDisplay.new()
	_sync_display()
	_record = Record.new(_number, dealer, _carry, shuffled_values, roll)
	return true

## 回调携带建立动画时的房间、本局和提示，重连或迟到的旧动画不会推进新局。
func begin_dealer_turn(instance_id: String, number: int, prompt: int, now_ms: int) -> bool:
	if not _live(instance_id, number, prompt, now_ms) or not _round.begin_dealer_turn():
		return false
	_record.append({"type": "begin_dealer_turn", "prompt_id": prompt})
	_sync_display()
	return true

func finish_draw_animation(instance_id: String, number: int, prompt: int, seat: int, now_ms: int) -> bool:
	if not _live(instance_id, number, prompt, now_ms) or not _round.finish_draw_animation(seat, prompt):
		return false
	_record.append({"type": "finish_draw_animation", "seat": seat, "prompt_id": prompt})
	_sync_display()
	_settle_if_finished(now_ms)
	return true

## 只处理外层时钟已经确认超时的这一家。同窗其他玩家可继续选择。
func expire_response_for(instance_id: String, number: int, prompt: int, seat: int, now_ms: int) -> bool:
	if not _live(instance_id, number, prompt, now_ms):
		return false
	return _apply(seat, prompt, "pass", -1, now_ms, true)

func submit(connection_id: String, instance_id: String, number: int, prompt: int, action: String, tile_id: int, now_ms: int) -> bool:
	var seat := _room.seat_for_connection(connection_id, now_ms)
	if seat < 0 or not _live(instance_id, number, prompt, now_ms):
		return false
	if _room.snapshot(now_ms).seats[seat].auto_play:
		return false
	return _apply(seat, prompt, action, tile_id, now_ms)

func _live(instance_id: String, number: int, prompt: int, now_ms: int) -> bool:
	return instance_id == _instance and number == _number and _round != null and _round.phase != "settled" and _round.prompt_id == prompt and _room.is_open(now_ms)

## 纯 AI 与真人授权共用相同的本家可见信息，座位身份不变。
func ai_job(seat: int, now_ms: int) -> Dictionary:
	if seat not in range(4) or _round == null or _round.choices(seat).is_empty():
		return {}
	var room := _room.snapshot(now_ms)
	if room.is_empty() or (room.seats[seat].ai_id < 0 and not room.seats[seat].auto_play):
		return {}
	var view := _round.snapshot_for(seat)
	return {"room_instance_id": _instance, "round_number": _number, "prompt_id": _round.prompt_id,
		"seat": seat, "control_revision": _control_revision[seat], "view": view}

func submit_ai(job: Dictionary, action: String, tile_id: int, now_ms: int) -> bool:
	var seat := int(job.get("seat", -1))
	var prompt := int(job.get("prompt_id", -1))
	if seat not in range(4) or _control_revision[seat] != job.get("control_revision", -1):
		return false
	if not _live(job.get("room_instance_id", ""), int(job.get("round_number", -1)), prompt, now_ms):
		return false
	var occupant: Dictionary = _room.snapshot(now_ms).seats[seat]
	if occupant.ai_id < 0 and not occupant.auto_play:
		return false
	return _apply(seat, prompt, action, tile_id, now_ms)

## 外层权威已经裁定本次超时后才调用。真人在线、暂时离线走同一张代打。
func discard_timeout_job(intent: Dictionary, now_ms: int) -> Dictionary:
	if intent.get("action") != "ai_discard" or typeof(intent.get("deadline_ms")) != TYPE_INT or intent.deadline_ms < 0 or now_ms < intent.deadline_ms:
		return {}
	var seat := int(intent.get("seat", -1))
	var prompt := int(intent.get("prompt_id", -1))
	if seat not in range(4) or not _live(intent.get("room_instance_id", ""), int(intent.get("round_number", -1)), prompt, now_ms):
		return {}
	if _round.phase != "turn" or _round.turn != seat or _room.snapshot(now_ms).seats[seat].ai_id >= 0:
		return {}
	var options := _round.choices(seat)
	if not options.get("actions", []).has("discard"):
		return {}
	var scope := {"room_instance_id": _instance, "round_number": _number, "prompt_id": prompt,
		"seat": seat, "control_revision": _control_revision[seat]}
	if _pending_timeout.get("scope") != scope:
		_pending_timeout = {"scope": scope, "nonce": Crypto.new().generate_random_bytes(16).hex_encode()}
	var job := scope.duplicate()
	job.nonce = _pending_timeout.nonce
	job.view = _round.snapshot_for(seat)
	job.view.choices = {"actions": ["discard"], "discard_ids": options.discard_ids, "prompt_id": prompt}
	return job

func submit_timeout_discard(job: Dictionary, tile_id: int, now_ms: int) -> bool:
	if _pending_timeout.is_empty() or job.get("nonce") != _pending_timeout.nonce:
		return false
	var scope: Dictionary = _pending_timeout.scope
	for key in scope:
		if job.get(key) != scope[key]:
			return false
	if _control_revision[scope.seat] != scope.control_revision or not _live(scope.room_instance_id, scope.round_number, scope.prompt_id, now_ms):
		return false
	return _apply(scope.seat, scope.prompt_id, "discard", tile_id, now_ms, true)

func animation_timeout_job(intent: Dictionary, now_ms: int) -> Dictionary:
	var seat := int(intent.get("seat", -1))
	if seat not in range(4) or now_ms < int(intent.get("deadline_ms", 9223372036854775807)):
		return {}
	if not _live(intent.get("room_instance_id", ""), int(intent.get("round_number", -1)), int(intent.get("prompt_id", -1)), now_ms):
		return {}
	var view := _round.snapshot_for(seat)
	if view.choices.is_empty():return {}
	var scope := {"room_instance_id":_instance,"round_number":_number,"prompt_id":_round.prompt_id,
		"seat":seat,"control_revision":_control_revision[seat]}
	if _animation_jobs.get(seat,{}).get("scope") != scope:
		_animation_jobs[seat]={"scope":scope,"nonce":Crypto.new().generate_random_bytes(16).hex_encode()}
	var job:=scope.duplicate()
	job.animation_nonce=_animation_jobs[seat].nonce
	job.view=view
	return job

func submit_animation_timeout(job: Dictionary, action: String, tile_id: int, now_ms: int) -> bool:
	var seat:=int(job.get("seat",-1))
	var issued:Dictionary=_animation_jobs.get(seat,{})
	if issued.is_empty() or job.get("animation_nonce")!=issued.nonce:return false
	for key in issued.scope:
		if job.get(key)!=issued.scope[key]:return false
	if _control_revision[seat]!=job.control_revision or not _live(job.room_instance_id,job.round_number,job.prompt_id,now_ms):return false
	return _apply(seat,job.prompt_id,action,tile_id,now_ms)

func _apply(seat: int, prompt: int, action: String, tile_id: int, now_ms: int, timed_out: bool = false) -> bool:
	if not _round.submit(seat, prompt, action, tile_id):
		return false
	_sync_display()
	_pending_timeout = {}
	_animation_jobs.erase(seat)
	if _round.prompt_id != prompt:_animation_jobs.clear()
	_record.append({"type": "timeout" if timed_out else "submit", "seat": seat, "prompt_id": prompt,
		"action": action, "tile_id": tile_id})
	_settle_if_finished(now_ms)
	return true

func _settle_if_finished(now_ms: int) -> void:
	if _round.phase != "settled" or _last_settlement.get("round_number", -1) == _number:
		return
	var facts := _round.settlement_facts()
	var scored := Score.settle(facts)
	var deltas: Array[int] = []
	# 帐本以整数分计；类型转换不可把新出现的非整数悄悄截断。
	for value in scored.deltas:
		if value != int(value):
			push_error("Fractional score in an integer-point room")
			return
		deltas.append(int(value))
	var dealer := next_dealer(scored, facts.round_meta.dealer_seat, _rng)
	if not _room.finish_round(_number, deltas, dealer, now_ms):
		push_error("A completed round could not commit its ledger to its room")
		return
	_carry = scored.next_chicken_multiplier
	var room := _room.snapshot(now_ms)
	_last_settlement = {"round_number": _number, "next_dealer_seat": dealer,
		"scores": room.seats.map(func(occupant): return occupant.score),
		"seats": room.seats,
		"players": facts.players, "round_meta": facts.round_meta, "last_discard": facts.last_discard,
		"ledger": scored}
	_last_record = _record.finish(facts, scored, dealer)
	_record = null

## 只供权威端本地保存或后续经授权上传；进行中的牌局没有可导出的牌谱。
func last_completed_record() -> Dictionary:
	return _last_record.duplicate(true)

## 本地权威调度器使用。不含手牌或牌墙，响应资格列表仍只限权威端。
func authority_status(now_ms: int) -> Dictionary:
	var room := _room.snapshot(now_ms)
	if room.is_empty():
		return {}
	var state := {"room": room, "phase": "idle", "turn": -1, "prompt_id": -1,
		"eligible": [], "response_clock": false}
	if _round != null:
		state.phase = _round.phase
		state.turn = _round.turn
		state.prompt_id = _round.prompt_id
		state.response_clock = _round.phase == "response" or (_round.phase == "turn" and _round.players[_round.turn].ready)
		if _round.phase in ["dealt", "ready_draw"]:
			state.eligible = [_round.turn]
		else:
			for seat in 4:
				if not _round.choices(seat).is_empty():
					state.eligible.append(seat)
	return state

func is_open(now_ms: int) -> bool:
	return _room.is_open(now_ms)

## 胡家净得分最高或未叫者净得分最低为候选；同分才抽签，全叫流局连庄。
static func next_dealer(scored: Dictionary, current: int, rng: RandomNumberGenerator) -> int:
	var candidates := Dealer.candidates(scored, current)
	return candidates[0] if candidates.size() == 1 else candidates[rng.randi_range(0, candidates.size() - 1)]

func directory_auth_state(now_ms: int) -> Dictionary:
	return _room.directory_auth_state(now_ms)


## 权威端全量导出：含暗手、剩余牌墙、账本与成员票据。仅经备用链路，不进入玩家视图。
func export_authority() -> Dictionary:
	var state := {"room": _room.export_authority(), "number": _number, "instance": _instance,
		"carry": _carry, "used_rolls": _used_rolls.duplicate(), "last_settlement": _last_settlement.duplicate(true),
		"last_record": _last_record.duplicate(true),
		"pending_timeout": _pending_timeout.duplicate(true), "animation_jobs": _animation_jobs.duplicate(true), "control_revision": _control_revision.duplicate(),
		"rng_state": _rng.state, "round": null, "display": null, "record": null}
	if _round != null:
		state.round = _round.export_authority()
	if _display != null:
		state.display = _display.export_authority()
	if _record != null:
		state.record = _record.export_authority()
	return state


static func _restore_rng_state(rng: RandomNumberGenerator, state_value: Variant) -> bool:
	if state_value is not int:
		return false
	rng.state = int(state_value)
	return true


func restore_authority(state: Dictionary, delta_ms: int = 0) -> bool:
	if not state.get("room") is Dictionary or not _room.restore_authority(state.room):
		return false
	_room.rebase_close_at(delta_ms)
	if not state.get("instance") is String or str(state.instance) != str(state.room.get("room_instance_id", "")):
		return false
	_instance = str(state.instance)
	_number = int(state.get("number", 0))
	_carry = int(state.get("carry", 1))
	if _carry not in [1, 2]:
		return false
	_used_rolls = state.get("used_rolls", {}).duplicate()
	_last_settlement = state.get("last_settlement", {}).duplicate(true)
	_last_record = state.get("last_record", {}).duplicate(true)
	_pending_timeout = state.get("pending_timeout", {}).duplicate(true)
	_animation_jobs = state.get("animation_jobs", {}).duplicate(true)
	var revisions: Array = state.get("control_revision", [0, 0, 0, 0])
	if not revisions is Array or revisions.size() != 4:
		return false
	_control_revision = []
	for value in revisions:
		_control_revision.append(int(value))
	if not _restore_rng_state(_rng, state.get("rng_state", -1)):
		return false
	_round = null
	if state.get("round") is Dictionary:
		var restored_round = Round.new()
		if not restored_round.restore_authority(state.round):
			return false
		_round = restored_round
	_display = HandDisplay.new()
	if state.get("display") is Dictionary and not _display.restore_authority(state.display):
		return false
	_record = null
	if state.get("record") is Dictionary:
		var restored_record = Record.new(1, 0, 1, ["wan1"], {})
		if not restored_record.restore_authority(state.record):
			return false
		_record = restored_record
	return true

func _sync_display() -> void:
	var preferences := []
	for seat in 4:
		preferences.append(_room.hand_preferences(seat))
	_display.sync(_round, preferences)
