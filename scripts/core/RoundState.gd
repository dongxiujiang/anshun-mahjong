class_name RoundState
extends RefCounted

signal require_turn(seat)
signal require_response(seat, discarded_seat, tile, options)
signal round_finished(result)
signal state_update()
signal dealt(info)
signal audio_event(event: Dictionary)

const SEATS := [0, 1, 2, 3]
const CFG := preload("res://scripts/autoload/GameConfig.gd")

## 回合阶段状态枚举，替代魔法字符串；网络协议仍用字符串，在序列化边界转换。
enum Phase { IDLE, DEALING, PLAYING, SETTLED }

const PHASE_NAMES := {Phase.IDLE: "idle", Phase.DEALING: "dealing", Phase.PLAYING: "playing", Phase.SETTLED: "settled"}

static func _phase_name(value: int) -> String:
	return PHASE_NAMES.get(value, "idle")

static func _phase_from_name(name: String) -> int:
	for key in PHASE_NAMES:
		if PHASE_NAMES[key] == name:
			return int(key)
	return Phase.IDLE

## Player response stage state (win/meld/rob); string form preserved at the network boundary.
enum ResponseStage { NONE, WIN, MELD, ROB }
const RESPONSE_STAGE_NAMES := {
	ResponseStage.NONE: "",
	ResponseStage.WIN: "win",
	ResponseStage.MELD: "meld",
	ResponseStage.ROB: "rob",
}

static func _response_stage_name(value: int) -> String:
	return RESPONSE_STAGE_NAMES.get(value, "")

static func _response_stage_from_name(name: String) -> int:
	for key in RESPONSE_STAGE_NAMES:
		if RESPONSE_STAGE_NAMES[key] == name:
			return int(key)
	return ResponseStage.NONE

## Kong source kind; serialized to last_discard.kong_kind as a string for protocol compatibility.
enum KongKind { NONE, EXPOSED, CONCEALED, ADD_KONG }
const KONG_KIND_NAMES := {
	KongKind.NONE: "",
	KongKind.EXPOSED: "exposed",
	KongKind.CONCEALED: "concealed",
	KongKind.ADD_KONG: "add_kong",
}

static func _kong_kind_name(value: int) -> String:
	return KONG_KIND_NAMES.get(value, "")

static func _kong_kind_from_name(name: String) -> int:
	for key in KONG_KIND_NAMES:
		if KONG_KIND_NAMES[key] == name:
			return int(key)
	return KongKind.NONE

var players: Array = []
var controllers: Array = []
var wall: WallRing
var current_turn := 0
var dealer_seat := 0
var next_dealer_seat := 0
var awaiting := false
var phase: Phase = Phase.IDLE
var last_result := {}
var last_discard := {}
var round_meta := {}
var wall_remain := {}
var wall_stacks := {}
var prompt_id := 0
var _rng := RandomNumberGenerator.new()
var _turn_count := 0
var _steps := 0
var _pending_responders: Array = []
var _awaiting_response := {}
var _response_stage: ResponseStage = ResponseStage.NONE
var _pending_kong := {}
var _last_deltas: Array = [0.0, 0.0, 0.0, 0.0]
var _last_lines: Array = []
var _last_total := 0.0
var _last_points: Array = []
var _last_round_points: Array = [0.0, 0.0, 0.0, 0.0]
var _last_pairwise: Array = []
var _last_transfers: Array = []
var _last_items: Array = [[], [], [], []]
var _last_status: Array = ["", "", "", ""]
var _draw_remaining_before := 108
var _kong_draw_turn := false
var _kong_draw_kind: KongKind = KongKind.NONE
var ai_delay_seconds := 0.0
var next_chicken_multiplier := 1
const ACTIONS := preload("res://scripts/core/LegalActions.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
var _recorder := REPLAY.new()
var _legal_turn_key := PackedByteArray()
var _legal_turn_cache := {}
const AUDIO := preload("res://scripts/core/RoundAudio.gd")
const SERIALIZER := preload("res://scripts/core/RoundSerializer.gd")
const AUDIO_HISTORY_LIMIT := AUDIO.HISTORY_LIMIT
var _audio := AUDIO.new()
# 保留现有读取接口，事件的存储和同步由 RoundAudio 负责。
var audio_session: String:
	get: return _audio.session
var audio_event_id: int:
	get: return _audio.event_id
var audio_events: Array:
	get: return _audio.events

func _init() -> void:
	_reset_meta()
	_audio.audio_event.connect(_forward_audio_event)

func _forward_audio_event(event: Dictionary) -> void:
	audio_event.emit(event)

func _reset_audio_events() -> void:
	_audio.reset()

func _emit_audio_event(action: String, seat: int, tile: String = "") -> void:
	_audio.emit_action(action, seat, tile)

func _reset_meta() -> void:
	round_meta = {
		"dealer_seat": dealer_seat,
		"charge_chickens": {}, "flip_tile": "", "chicken_multiplier": 1,
		"kong_draw_seat": -1, "last_four_self_draw_seat": -1,
		"robber_seat": -1, "burn_chicken_seat": -1, "burn_chicken_reason": "",
		"winner": -1, "self_draw": false, "win_tile": "", "discard_seat": -1,
	}

func build_players(human_seat: int) -> void:
	players.clear()
	for seat in SEATS:
		var player := PlayerState.new()
		player.init_seat(seat, seat == human_seat, seat == dealer_seat, ["庄家", "下家", "对家", "上家"][posmod(seat - dealer_seat, 4)])
		player.score = CFG.START_SCORE
		players.append(player)

func start_round(human_seat: int, die_override: int = -1) -> void:
	if _recorder.auto_save and not _recorder.record.is_empty(): _recorder.save()
	var scores: Array = []
	for player in players:
		scores.append(player.score)
	dealer_seat = posmod(next_dealer_seat, 4)
	build_players(human_seat)
	if scores.size() == 4:
		apply_scores(scores)
	_reset_meta()
	_reset_audio_events()
	last_result = {}
	round_meta.chicken_multiplier = clampi(next_chicken_multiplier, 1, CFG.MAX_CHICKEN_MULTIPLIER)
	next_chicken_multiplier = 1
	last_discard = {}
	_pending_kong = {}
	_awaiting_response = {}
	_response_stage = ResponseStage.NONE
	_pending_responders.clear()
	_steps = 0
	_turn_count = 0
	awaiting = false
	_kong_draw_turn = false
	_kong_draw_kind = KongKind.NONE
	var built := WallBuilder.setup(_rng, dealer_seat)
	wall = WallRing.new(built.ring, dealer_seat)
	var die := die_override if die_override >= 1 and die_override <= 6 else _rng.randi_range(1, 6)
	round_meta["die"] = die
	round_meta["break"] = WallRing.compute_break(die, dealer_seat)
	wall.set_head(round_meta["break"])
	phase = Phase.DEALING
	_initial_deal()
	phase = Phase.PLAYING
	current_turn = dealer_seat
	_recorder.begin(self)
	_begin_turn()

func _initial_deal() -> void:
	for batch in 3:
		for offset in 4:
			var seat := posmod(dealer_seat + offset, 4)
			for index in 4:
				players[seat].concealed.append(wall.draw_head())
	for offset in 4:
		var seat := posmod(dealer_seat + offset, 4)
		players[seat].concealed.append(wall.draw_head())
	var info: Array = []
	for player in players:
		info.append({"seat": player.seat, "count": player.concealed.size()})
	dealt.emit(info)

func _begin_turn() -> void:
	if phase != Phase.PLAYING:
		return
	_steps += 1
	if _steps > 3000:
		_penzu()
		return
	_kong_draw_turn = false
	_draw_remaining_before = wall.remaining
	var tile := wall.draw_head()
	if tile == "":
		_penzu()
		return
	var player: PlayerState = players[current_turn]
	player.just_drew = tile
	player.concealed.append(tile)
	_ask_turn_actor()

func _ask_turn_actor() -> void:
	_awaiting_response = {}
	_response_stage = ResponseStage.NONE
	prompt_id += 1
	var actor: Object = controllers[current_turn] if controllers.size() > current_turn else null
	if actor != null and actor.has_method("decide_turn"):
		if ai_delay_seconds > 0.0:
			_queue_ai_turn(current_turn, actor)
		else:
			_apply_turn_action(current_turn, actor.decide_turn(self, current_turn))
	else:
		awaiting = true
		require_turn.emit(current_turn)
		state_update.emit()

func _queue_ai_turn(seat: int, actor: Object) -> void:
	var session := audio_session
	var prompt := prompt_id
	awaiting = false
	state_update.emit()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_apply_turn_action(seat, actor.decide_turn(self, seat))
		return
	await tree.create_timer(ai_delay_seconds).timeout
	if audio_session != session or phase != Phase.PLAYING or current_turn != seat or not _awaiting_response.is_empty() or prompt_id != prompt or controllers[seat] != actor:
		return
	_apply_turn_action(seat, actor.decide_turn(self, seat))

func restore_human_control(seat: int) -> void:
	controllers[seat] = null
	if phase != Phase.PLAYING or awaiting:
		return
	# Reissue an AI prompt immediately; the old timer is invalidated by its controller/prompt guards.
	if _response_stage == ResponseStage.NONE:
		if current_turn == seat: _ask_turn_actor()
	elif not _pending_responders.is_empty() and _pending_responders[0] == seat:
		var source: Dictionary = _pending_kong if _response_stage == ResponseStage.ROB else last_discard
		_ask_next_responder(int(source.seat), str(source.tile))

func submit_turn(seat: int, decision: Dictionary) -> bool:
	if phase != Phase.PLAYING or not awaiting or not _awaiting_response.is_empty() or seat != current_turn:
		_recorder.request(seat, "turn", decision, false, "不属于当前操作窗口")
		return false
	if not _valid_turn(seat, decision):
		_recorder.request(seat, "turn", decision, false, "操作不符合当前允许清单")
		return false
	_recorder.request(seat, "turn", decision, true, "")
	awaiting = false
	_apply_turn_action(seat, decision)
	return true

func _valid_turn(seat: int, decision: Dictionary) -> bool:
	return seat >= 0 and seat < players.size() and ACTIONS.valid_turn(legal_turn_options(seat), players[seat], decision)

func legal_turn_options(seat: int) -> Dictionary:
	if seat < 0 or seat >= players.size(): return ACTIONS.turn_options(self, seat)
	var player: PlayerState = players[seat]
	var key := var_to_bytes([seat, player.concealed, player.melds, player.just_drew, player.ready, player.first_turn_done, _wall_count()])
	if key != _legal_turn_key:
		_legal_turn_key = key
		_legal_turn_cache = ACTIONS.turn_options(self, seat)
	return _legal_turn_cache.duplicate(true)

func legal_response_options(seat: int, source: int, tile: String, stage: ResponseStage) -> Dictionary:
	return ACTIONS.response_options(self, seat, source, tile, stage)

func allowed_actions(seat: int) -> Dictionary:
	# 提示身份由权威端管理；不属于当前操作窗口时返回空清单。
	if phase != Phase.PLAYING or not awaiting: return {}
	if not _awaiting_response.is_empty():
		if int(_awaiting_response.get("seat", -1)) != seat: return {}
		return {"kind": "response", "prompt_id": prompt_id, "options": legal_response_options(seat, int(_awaiting_response.disc_seat), str(_awaiting_response.tile), int(_awaiting_response.get("stage", _response_stage)))}
	if current_turn != seat: return {}
	return {"kind": "turn", "prompt_id": prompt_id, "options": legal_turn_options(seat)}

func _apply_turn_action(seat: int, decision: Dictionary) -> void:
	if not _valid_turn(seat, decision):
		var options := legal_turn_options(seat)
		if options.discards.is_empty(): return
		decision = {"discard": options.discards[0]}
	_recorder.action(self, "turn", seat, decision)
	var player: PlayerState = players[seat]
	if decision.get("self_win", false):
		_do_self_win(seat)
		return
	if not decision.get("kong_declares", []).is_empty():
		_do_concealed_kong(seat, str(decision.kong_declares[0]), player)
		return
	if not decision.get("add_kong", []).is_empty():
		_do_add_kong(seat, str(decision.add_kong[0]))
		return
	var discard: String = player.just_drew if player.ready else decision.get("discard", "")
	if decision.get("ready", false):
		player.ready = true
		player.announced_ready = true
		_emit_audio_event("ready", seat)
	_discard(seat, discard)

func _discard(seat: int, tile: String) -> void:
	var player: PlayerState = players[seat]
	if not player.concealed.has(tile):
		return
	player.concealed.erase(tile)
	player.discards.append(tile)
	player.discard_history.append(tile)
	player.discard_ids.append(player.discard_count)
	player.discard_count += 1
	player.just_drew = ""
	player.first_turn_done = true
	var after_kong := _kong_draw_turn and _kong_draw_kind in [KongKind.CONCEALED, KongKind.ADD_KONG]
	last_discard = {
		"seat": seat,
		"tile": tile,
		"after_kong": after_kong,
		"kong_kind": _kong_draw_kind if after_kong else KongKind.NONE,
	}
	_kong_draw_turn = false
	_kong_draw_kind = KongKind.NONE
	if Tiles.is_chicken(tile) and not has_charge(tile):
		round_meta.charge_chickens[tile] = {"owner": seat, "location": "discard", "discard_id": player.discard_count - 1}
		_refresh_charge_flags()
	_emit_audio_event("discard", seat, tile)
	state_update.emit()
	_after_discard()

func _after_discard() -> void:
	_response_stage = ResponseStage.WIN
	_pending_responders = _seat_order(int(last_discard.seat))
	_ask_next_responder(last_discard.seat, last_discard.tile)

func _seat_order(source: int) -> Array:
	return [(source + 1) % 4, (source + 2) % 4, (source + 3) % 4]

func _response_options(seat: int, tile: String) -> Dictionary:
	var source := int(_pending_kong.get("seat", -1)) if _response_stage == ResponseStage.ROB else int(last_discard.get("seat", -1))
	return legal_response_options(seat, source, tile, _response_stage)

func has_self_kong(seat: int) -> bool:
	return seat >= 0 and seat < players.size() and ACTIONS.has_self_kong(players[seat])

func can_win_on_discard(seat: int, source: int, tile: String, stage: ResponseStage = ResponseStage.NONE) -> bool:
	return ACTIONS.can_win_on_discard(self, seat, source, tile, stage)

func _ask_next_responder(source: int, tile: String) -> void:
	if phase != Phase.PLAYING:
		return
	if _pending_responders.is_empty():
		if _response_stage == ResponseStage.WIN:
			_response_stage = ResponseStage.MELD
			_pending_responders = _seat_order(source)
			_ask_next_responder(source, tile)
		elif _response_stage == ResponseStage.ROB:
			_complete_add_kong()
		else:
			_awaiting_response = {}
			_response_stage = ResponseStage.NONE
			current_turn = (source + 1) % 4
			_begin_turn()
		return
	var seat: int = _pending_responders[0]
	var options := _response_options(seat, tile)
	if not options.can_win and not options.can_pong and not options.can_kong:
		_pending_responders.pop_front()
		_ask_next_responder(source, tile)
		return
	var actor: Object = controllers[seat] if controllers.size() > seat else null
	if actor != null and actor.has_method("decide_response"):
		if ai_delay_seconds > 0.0:
			_queue_ai_response(seat, source, tile, options, actor)
		else:
			_process_response(seat, source, tile, actor.decide_response(self, seat, source, tile, options))
	else:
		prompt_id += 1
		awaiting = true
		_awaiting_response = {"seat": seat, "disc_seat": source, "tile": tile, "options": options, "stage": _response_stage}
		require_response.emit(seat, source, tile, options)
		state_update.emit()

func _queue_ai_response(seat: int, source: int, tile: String, options: Dictionary, actor: Object) -> void:
	# 人机选择“过”不串行等待1/2/3秒，只为实际碰杠胡保留动作延迟。
	var decision: Dictionary = actor.decide_response(self, seat, source, tile, options)
	if decision.get("action", "pass") == "pass":
		_process_response(seat, source, tile, decision)
		return
	var session := audio_session
	var stage := _response_stage
	var prompt := prompt_id
	awaiting = false
	state_update.emit()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_process_response(seat, source, tile, decision)
		return
	await tree.create_timer(ai_delay_seconds).timeout
	if audio_session != session or phase != Phase.PLAYING or _pending_responders.is_empty() or _pending_responders[0] != seat or _response_stage != stage or prompt_id != prompt or controllers[seat] != actor:
		return
	_process_response(seat, source, tile, decision)

func submit_response(seat: int, tile: String, decision: Dictionary) -> bool:
	if phase != Phase.PLAYING or not awaiting or _awaiting_response.get("seat", -1) != seat or _awaiting_response.get("tile", "") != tile:
		_recorder.request(seat, "response", decision, false, "响应座位或牌面已过期")
		return false
	var options := _response_options(seat, tile)
	if not ACTIONS.valid_response(options, decision):
		_recorder.request(seat, "response", decision, false, "操作不符合当前允许清单")
		return false
	_recorder.request(seat, "response", decision, true, "")
	var source: int = _awaiting_response.disc_seat
	awaiting = false
	_awaiting_response = {}
	_process_response(seat, source, tile, decision)
	return true

func _process_response(seat: int, source: int, tile: String, decision: Dictionary) -> void:
	var options := _response_options(seat, tile)
	if not ACTIONS.valid_response(options, decision):
		decision = {"action": "pass"}
	var action: String = decision.get("action", "pass")
	_recorder.action(self, "response", seat, decision, source, tile)
	if action == "win" and options.can_win:
		if _response_stage == ResponseStage.ROB:
			var player: PlayerState = players[source]
			player.concealed.erase(tile)
			player.just_drew = ""
			round_meta.robber_seat = seat
			round_meta.burn_chicken_seat = source
			_pending_kong = {}
			_discard_win(seat, source, tile, true)
		else:
			if bool(last_discard.get("after_kong", false)):
				round_meta.robber_seat = seat
				round_meta.burn_chicken_seat = source
				round_meta.burn_chicken_reason = "after_kong_discard"
			_discard_win(seat, source, tile)
		return
	if not _pending_responders.is_empty() and _pending_responders[0] == seat:
		_pending_responders.pop_front()
	var player: PlayerState = players[seat]
	if action == "kong" and options.can_kong:
		_remove_n(player.concealed, tile, 3)
		player.melds.append({"kind": "kong", "tile": tile, "robbed": false, "from_seat": source, "after_discard": player.discard_count})
		_remove_from_discards(source, tile, seat, "meld", player.melds.size() - 1)
		current_turn = seat
		_kong_draw_kind = KongKind.EXPOSED
		_emit_audio_event("kong", seat)
		_state_after_kong_draw()
		return
	if action == "pong" and options.can_pong:
		_remove_n(player.concealed, tile, 2)
		player.melds.append({"kind": "pung", "tile": tile, "robbed": false, "from_seat": source, "after_discard": player.discard_count})
		_remove_from_discards(source, tile, seat, "meld", player.melds.size() - 1)
		player.just_drew = ""
		current_turn = seat
		_kong_draw_turn = false
		_emit_audio_event("pong", seat)
		_ask_turn_actor()
		return
	_ask_next_responder(source, tile)

func _state_after_kong_draw() -> void:
	_draw_remaining_before = wall.remaining
	var tile := wall.draw_tail()
	if tile == "":
		_penzu()
		return
	var player: PlayerState = players[current_turn]
	player.just_drew = tile
	player.concealed.append(tile)
	_kong_draw_turn = true
	_ask_turn_actor()

func _do_concealed_kong(seat: int, tile: String, player: PlayerState) -> void:
	if player.ready or Tiles.count(player.concealed, tile) < 4 or _wall_count() < 1:
		return
	_remove_n(player.concealed, tile, 4)
	player.melds.append({"kind": "kong", "tile": tile, "robbed": false, "concealed": true, "after_discard": player.discard_count})
	current_turn = seat
	_kong_draw_kind = KongKind.CONCEALED
	# 只喊“杠”，公共声音事件不能泄露暗杠的牌。
	_emit_audio_event("kong", seat)
	_state_after_kong_draw()

func _do_add_kong(seat: int, tile: String) -> bool:
	var player: PlayerState = players[seat]
	if player.ready or not player.concealed.has(tile) or _wall_count() < 1:
		return false
	for index in player.melds.size():
		if player.melds[index].kind == "pung" and player.melds[index].tile == tile:
			_pending_kong = {"seat": seat, "tile": tile, "index": index}
			_response_stage = ResponseStage.ROB
			_pending_responders = _seat_order(seat)
			# 加杠宣告时喊一次，被抢时接胡牌语音，完成时不再重喊。
			_emit_audio_event("kong", seat)
			_ask_next_responder(seat, tile)
			return true
	return false

func _complete_add_kong() -> void:
	var seat: int = _pending_kong.seat
	var tile: String = _pending_kong.tile
	var player: PlayerState = players[seat]
	player.concealed.erase(tile)
	player.melds[_pending_kong.index].kind = "add_kong"
	_pending_kong = {}
	_awaiting_response = {}
	current_turn = seat
	_kong_draw_kind = KongKind.ADD_KONG
	_state_after_kong_draw()

func _do_self_win(seat: int) -> void:
	round_meta.winner = seat
	round_meta.self_draw = true
	round_meta.win_tile = str(players[seat].just_drew)
	# 胡牌后传入实际胡牌张，供清单吊牌型精确判定。
	if _kong_draw_turn:
		round_meta.kong_draw_seat = seat
	if _draw_remaining_before <= 4:
		round_meta.last_four_self_draw_seat = seat
	_finish()

func _discard_win(seat: int, source: int, tile: String = "", robbed: bool = false) -> void:
	round_meta.winner = seat
	round_meta.self_draw = false
	round_meta.discard_seat = source
	var win_tile := tile if tile != "" else str(last_discard.get("tile", ""))
	round_meta.win_tile = win_tile
	if not robbed:
		_remove_from_discards(source, win_tile, seat, "hand")
	players[seat].concealed.append(win_tile)
	# 胡牌那张固定停在摸牌位：牌桌上单独显示，不并回手牌排序里。
	players[seat].just_drew = win_tile
	_finish()

func has_charge(tile: String) -> bool:
	return round_meta.get("charge_chickens", {}).has(tile)

func is_charge_discard(seat: int, index: int) -> bool:
	var player: PlayerState = players[seat]
	var tile: String = player.discards[index]
	var charge: Dictionary = round_meta.get("charge_chickens", {}).get(tile, {})
	if charge.get("owner", -1) != seat or charge.get("location", "") != "discard":
		return false
	var discard_id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
	return discard_id == charge.get("discard_id", -1)

func is_charge_meld(seat: int, index: int) -> bool:
	var charge: Dictionary = round_meta.get("charge_chickens", {}).get(players[seat].melds[index].tile, {})
	return charge.get("owner", -1) == seat and charge.get("location", "") == "meld" and charge.get("meld_index", -1) == index

func is_meld_revealed(seat: int, index: int) -> bool:
	var player: PlayerState = players[seat]
	var meld: Dictionary = player.melds[index]
	if not meld.get("concealed", false) or phase == Phase.SETTLED:
		return true
	# 暗杠补牌后的本轮出牌仍反扣，下一轮本人出牌后才全部翻开。
	# 使用累计出牌次数，碰杠移走弃牌不会让已亮出的暗杠重新扣回。
	return player.discard_count >= int(meld.get("after_discard", 0)) + 2

func _refresh_charge_flags() -> void:
	for player in players:
		player.charge_chicken = false
	for charge in round_meta.get("charge_chickens", {}).values():
		var owner: int = charge.get("owner", -1)
		if owner >= 0 and owner < players.size():
			players[owner].charge_chicken = true

func _remove_from_discards(seat: int, tile: String, receiver: int = -1, location: String = "none", meld_index: int = -1) -> void:
	var player: PlayerState = players[seat]
	var discards: Array = player.discards
	var index := discards.rfind(tile)
	if index >= 0:
		if is_charge_discard(seat, index):
			var charge: Dictionary = round_meta.charge_chickens[tile]
			charge.owner = receiver
			charge.location = location
			charge.meld_index = meld_index
			# 冲锋鸡被碰/杠后归碰杠者所有；其首张奖励降为每张2分，
			# 明杠另由放出该牌的玩家支付本组固定4分。
		discards.remove_at(index)
		if index < player.discard_ids.size():
			player.discard_ids.remove_at(index)
		var history_index := player.discard_history.rfind(tile)
		if history_index >= 0:
			player.discard_history.remove_at(history_index)
		_refresh_charge_flags()

func _penzu() -> void:
	round_meta.winner = -1
	_finish()

func _finish() -> void:
	# 已完成的结算只能入账一次；重复结束通知不能再次加减四家的分数。
	if phase == Phase.SETTLED and not last_result.is_empty():
		return
	phase = Phase.SETTLED
	awaiting = false
	_awaiting_response = {}
	round_meta.flip_tile = wall.peek_head() if wall != null and round_meta.winner >= 0 else ""
	var scored := ScoringEngine.settle(self)
	_last_deltas = scored.deltas
	_last_lines = scored.lines
	_last_points = scored.points
	_last_round_points = scored.round_points
	_last_pairwise = scored.pairwise
	_last_transfers = scored.transfers
	_last_items = scored.get("items", [[], [], [], []])
	_last_status = scored.get("status", ["", "", "", ""])
	next_chicken_multiplier = int(scored.next_chicken_multiplier)
	next_dealer_seat = _choose_next_dealer(scored.called)
	round_meta.next_dealer_seat = next_dealer_seat
	round_meta.all_called_draw = scored.all_called_draw
	round_meta.next_chicken_multiplier = next_chicken_multiplier
	_last_total = 0.0
	for seat in SEATS:
		players[seat].score += scored.deltas[seat]
		_last_total += scored.deltas[seat]
	assert(is_zero_approx(_last_total), "Settlement must preserve the four players' total score")
	last_result = build_result()
	_recorder.finish(self)
	_audio.emit_win(round_meta)
	round_finished.emit(last_result)
	state_update.emit()

func _choose_next_dealer(called: Array) -> int:
	var winner := int(round_meta.get("winner", -1))
	if winner >= 0:
		if round_meta.get("self_draw", false):
			return winner
		var source := int(round_meta.get("discard_seat", -1))
		return source if source in SEATS else winner
	# 多人未叫时，从本局庄家开始顺时针取第一位；全员叫牌则连庄。
	for offset in 4:
		var seat := posmod(dealer_seat + offset, 4)
		if not called[seat]:
			return seat
	return dealer_seat

func build_result() -> Dictionary:
	var result := {
		"round_meta": round_meta.duplicate(true), "scores": [], "players": [],
		"deltas": _last_deltas, "lines": _last_lines, "points": _last_points,
		"round_points": _last_round_points, "pairwise": _last_pairwise,
		"items": _last_items, "status": _last_status,
		"transfers": _last_transfers, "total_delta": _last_total,
		"flip_tile": round_meta.get("flip_tile", ""),
		"next_chicken_multiplier": next_chicken_multiplier,
		"dealer_seat": dealer_seat, "next_dealer_seat": next_dealer_seat,
	}
	for player in players:
		result.players.append({"seat": player.seat, "concealed": player.concealed.duplicate(),
			"melds": player.melds.duplicate(true), "discards": player.discards.duplicate(),
			"ready": player.ready, "name": player.name_label, "score": player.score})
		result.scores.append(player.score)
	return result

func _hand_is_win(player: PlayerState) -> bool:
	return RuleEngine.analyze(player.concealed, player.melds).win

func can_declare_ready(seat: int) -> bool:
	return seat >= 0 and seat < players.size() and ACTIONS.ready_window(players[seat])

func _wall_count() -> int:
	if wall != null:
		return wall.remaining
	var count := 0
	for seat in SEATS:
		count += int(wall_remain.get(seat, 0))
	return count

# 公开接口保留，网络快照和牌面隐藏交给独立模块。
func serialize() -> Dictionary:
	return SERIALIZER.serialize(self)

func apply_sync(state: Dictionary) -> void:
	SERIALIZER.apply_sync(self, state)

func serialize_for_seat(seat: int) -> Dictionary:
	return SERIALIZER.serialize_for_seat(self, seat)

func export_replay(path: String = "") -> String:
	return _recorder.save(path)

func replay_record() -> Dictionary:
	return _recorder.record.duplicate(true)

func _remove_n(cards: Array, tile: String, count: int) -> void:
	for index in count:
		cards.erase(tile)

func apply_scores(scores: Array) -> void:
	for seat in SEATS:
		players[seat].score = float(scores[seat])

## 用固定种子（测试/复盘用）。正式对局请用 randomize_seed()。
func set_rng_seed(seed_value: int) -> void:
	_rng.seed = seed_value

## 用系统熵重新随机化种子。洗牌不可预测，客户端无法反推牌墙。
func randomize_seed() -> void:
	_rng.randomize()
