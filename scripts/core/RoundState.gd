class_name RoundState
extends RefCounted

signal require_turn(seat)
signal require_response(seat, discarded_seat, tile, options)
signal round_finished(result)
signal state_update()
signal dealt(info)
## 视觉事件只描述已完成的逻辑结果，客户端可丢弃并从快照恢复。
signal visual_event(event: Dictionary)
signal audio_event(event: Dictionary)

const SEATS := [0, 1, 2, 3]
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const AI_CONTEXT := preload("res://scripts/ai/AiTurnContext.gd")
const AI_TIMEOUT_MS := 3000

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
enum ResponseStage { NONE, WIN, KONG, MELD, ROB }
const RESPONSE_STAGE_NAMES := {
	ResponseStage.NONE: "",
	ResponseStage.WIN: "win",
	ResponseStage.KONG: "kong",
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
var _pending_wins: Array = []
# 兼有胡/碰/杠的响应先记下放弃胡、改为碰杠的意图；等所有胡响应
# 结束后再落账，避免碰杠抢走其他玩家仍可成立的胡。
var _pending_claims: Array = []
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
var ai_response_delay_seconds := 0.0
var ai_service = null
var ai_timeouts := 0
var ai_fallbacks := 0
var ai_cancelled := 0
var ai_tasks := 0
var ai_results := 0
var ai_snapshot_max_ms := 0.0
var ai_compute_max_ms := 0.0
var ai_apply_max_ms := 0.0
var _ai_pending: Dictionary = {}
var opening_delay_seconds := 0.0
## 首帧快照也要带开局速度，避免客户端在收到 lobby 前先按默认速度播放。
var opening_speed := "standard"
var _opening_generation := 0
## 联机测试牌型：只覆盖指定座位，牌墙会先从完整牌库移除这些牌。
var test_hand_seat := -1
var test_hand: Array = []
var test_pattern := ""
var next_chicken_multiplier := 1
const PRESENTATION := preload("res://scripts/core/RoundPresentation.gd")
var _presentation := PRESENTATION.new()
var visual_event_id: int:
	get: return _presentation.event_id
var visual_events: Array:
	get: return _presentation.events
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
	_presentation.visual_event.connect(_forward_visual_event)

func _forward_audio_event(event: Dictionary) -> void:
	audio_event.emit(event)

func _forward_visual_event(event: Dictionary) -> void:
	visual_event.emit(event)

func _reset_audio_events() -> void:
	_audio.reset()

func _reset_visual_events() -> void:
	_presentation.reset()

func _emit_visual_event(event_type: String, data: Dictionary = {}) -> void:
	_presentation.emit_event(event_type, data)

func _emit_audio_event(action: String, seat: int, tile: String = "") -> void:
	_audio.emit_action(action, seat, tile)

func _reset_meta() -> void:
	round_meta = {
		"dealer_seat": dealer_seat,
		"charge_chickens": {}, "flip_tile": "", "chicken_multiplier": 1,
		# 胡牌时被胡的弃牌会从 player.discards 移除，但它仍然是
		# 出牌鸡，尤其需要保留未叫牌玩家的补付记录。
		"resolved_chicken_discards": [],
		"kong_draw_seat": -1, "last_four_self_draw_seat": -1,
		"robber_seat": -1, "burn_chicken_seat": -1, "burn_chicken_reason": "",
		"robbed_kong": false,
		"winner": -1, "winners": [], "self_draw": false, "win_tile": "", "discard_seat": -1,
	}

func build_players(human_seat: int) -> void:
	players.clear()
	for seat in SEATS:
		var player := PlayerState.new()
		player.init_seat(seat, seat == human_seat, seat == dealer_seat, ["庄家", "下家", "对家", "上家"][posmod(seat - dealer_seat, 4)])
		player.score = CFG.START_SCORE
		players.append(player)

func start_round(human_seat: int, die_override: int = -1) -> void:
	cancel_ai()
	_opening_generation += 1
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
	_reset_visual_events()
	last_result = {}
	round_meta.chicken_multiplier = clampi(next_chicken_multiplier, 1, CFG.MAX_CHICKEN_MULTIPLIER)
	next_chicken_multiplier = 1
	last_discard = {}
	_pending_kong = {}
	_pending_wins.clear()
	_pending_claims.clear()
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
	phase = Phase.DEALING
	current_turn = dealer_seat
	_emit_visual_event("dice", {"value": die, "dealer": dealer_seat})
	wall.set_head(round_meta["break"])
	phase = Phase.DEALING
	_initial_deal()
	if opening_delay_seconds > 0.0:
		state_update.emit()
		_wait_for_opening(_opening_generation)
	else:
		_finish_opening()

func _wait_for_opening(generation: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	await tree.create_timer(opening_delay_seconds).timeout
	if generation == _opening_generation and phase == Phase.DEALING:
		_finish_opening()

func _finish_opening() -> void:
	phase = Phase.PLAYING
	_recorder.begin(self)
	_begin_turn()

func cancel_opening() -> void:
	cancel_ai()
	_opening_generation += 1
	if phase == Phase.DEALING:
		phase = Phase.IDLE
		awaiting = false

func _initial_deal() -> void:
	var batches: Array = []
	for batch in 3:
		var batch_info: Array = []
		for offset in 4:
			var seat := posmod(dealer_seat + CFG.DEAL_DIRECTION * offset, 4)
			var cards: Array = []
			for index in 4:
				var card := wall.draw_head()
				players[seat].concealed.append(card)
				cards.append(card)
			batch_info.append({"seat": seat, "cards": cards})
		batches.append(batch_info)
	for offset in 4:
		var seat := posmod(dealer_seat + CFG.DEAL_DIRECTION * offset, 4)
		var card := wall.draw_head()
		players[seat].concealed.append(card)
		batches.append([{"seat": seat, "cards": [card], "dealer_extra": seat == dealer_seat}])
	var info: Array = []
	for player in players:
		info.append({"seat": player.seat, "count": player.concealed.size()})
	if test_hand_seat in SEATS and test_hand.size() == 13:
		# 测试牌型覆盖指定座位；牌墙和总牌张数保持正常。
		players[test_hand_seat].concealed = test_hand.duplicate()
	dealt.emit({"players": info, "batches": batches})
	for batch in batches:
		_emit_visual_event("deal_batch", {"deals": batch})
	# 只作用于本次发牌，下局必须没有测试手牌残留。
	test_hand_seat = -1
	test_hand.clear()

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
	# 过胡/过碰锁只持续到本人的下一次摸牌；摸牌前清除碰后禁打牌。
	_clear_draw_locks(player)
	player.just_drew = tile
	player.concealed.append(tile)
	_emit_visual_event("draw", {"seat": current_turn, "tile": tile, "kind": "head"})
	_ask_turn_actor()

func _request_async_ai_turn(actor: Object) -> bool:
	if ai_service == null or not ai_service.has_method("submit_turn"):
		return false
	var snapshot_started := Time.get_ticks_usec()
	var context = AI_CONTEXT.build(self, current_turn)
	ai_snapshot_max_ms = maxf(ai_snapshot_max_ms, float(Time.get_ticks_usec() - snapshot_started) / 1000.0)
	if context == null:
		return false
	var token: int = int(ai_service.submit_turn(context, current_turn))
	if token <= 0:
		return false
	context.task_id = token
	context.session = audio_session
	context.prompt_id = prompt_id
	ai_tasks += 1
	var now := Time.get_ticks_msec()
	_ai_pending = {
		"kind": "turn", "token": token, "seat": current_turn, "actor": actor,
		"session": audio_session, "prompt": prompt_id, "stage": _response_stage,
		"source": -1, "tile": "", "result": {},
		"requested_ms": now, "due_ms": now + int(round(ai_delay_seconds * 1000.0)),
	}
	awaiting = false
	state_update.emit()
	return true

func _request_async_ai_response(seat: int, source: int, tile: String, options: Dictionary, actor: Object) -> bool:
	if ai_service == null or not ai_service.has_method("submit_response"):
		return false
	var snapshot_started := Time.get_ticks_usec()
	var context = AI_CONTEXT.build(self, seat)
	ai_snapshot_max_ms = maxf(ai_snapshot_max_ms, float(Time.get_ticks_usec() - snapshot_started) / 1000.0)
	if context == null:
		return false
	var token: int = int(ai_service.submit_response(context, seat, source, tile, options))
	if token <= 0:
		return false
	context.task_id = token
	context.session = audio_session
	context.prompt_id = prompt_id
	ai_tasks += 1
	var now := Time.get_ticks_msec()
	_ai_pending = {
		"kind": "response", "token": token, "seat": seat, "actor": actor,
		"session": audio_session, "prompt": prompt_id, "stage": _response_stage,
		"source": source, "tile": tile, "result": {},
		"requested_ms": now, "due_ms": now + int(round(ai_response_delay_seconds * 1000.0)),
	}
	awaiting = false
	state_update.emit()
	return true

func _ask_turn_actor() -> void:
	_awaiting_response = {}
	_response_stage = ResponseStage.NONE
	# A pong/kong claim takes precedence over the rest of the discard response
	# window. Clear any remaining responders before starting the claimer's turn.
	_pending_responders.clear()
	prompt_id += 1
	var actor: Object = controllers[current_turn] if controllers.size() > current_turn else null
	if actor != null and actor.has_method("decide_turn"):
		if _request_async_ai_turn(actor):
			return
		var decision: Dictionary = actor.decide_turn(self, current_turn)
		var discarding: bool = not decision.get("self_win", false) and decision.get("kong_declares", []).is_empty() and decision.get("add_kong", []).is_empty()
		# Delay every AI discard, including the post-pong/kong discard that has
		# no fresh draw. The previous version only delayed after a draw, which
		# made claims look instant even with the slow wait selected.
		if discarding and ai_delay_seconds > 0.0:
			_queue_ai_turn(current_turn, actor, decision)
		else:
			_apply_turn_action(current_turn, decision)
	else:
		awaiting = true
		require_turn.emit(current_turn)
		state_update.emit()

func _queue_ai_turn(seat: int, actor: Object, decision: Dictionary) -> void:
	var session := audio_session
	var prompt := prompt_id
	awaiting = false
	state_update.emit()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_apply_turn_action(seat, decision)
		return
	await tree.create_timer(ai_delay_seconds).timeout
	if audio_session != session or phase != Phase.PLAYING or current_turn != seat or not _awaiting_response.is_empty() or prompt_id != prompt or controllers[seat] != actor:
		return
	_apply_turn_action(seat, decision)

func set_ai_service(service) -> void:
	cancel_ai()
	ai_service = service

func cancel_ai() -> void:
	if _ai_pending.is_empty():
		return
	var token := int(_ai_pending.get("token", 0))
	if ai_service != null and ai_service.has_method("cancel"):
		ai_service.cancel(token)
	ai_cancelled += 1
	_ai_pending = {}

func poll_ai() -> void:
	if _ai_pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	var pending: Dictionary = _ai_pending
	if pending.get("result", {}).is_empty() and ai_service != null:
		var result: Dictionary = ai_service.take_result(int(pending.get("token", 0)))
		if not result.is_empty():
			pending["result"] = result
			var decision: Dictionary = result.get("decision", {})
			if str(pending.get("kind", "")) == "turn":
				var discarding: bool = not decision.get("self_win", false) \
					and decision.get("kong_declares", []).is_empty() \
					and decision.get("add_kong", []).is_empty()
				if not discarding:
					pending["due_ms"] = now
			elif str(decision.get("action", "pass")) == "pass":
				pending["due_ms"] = now
			_ai_pending = pending
	var result_now: Dictionary = pending.get("result", {})
	if result_now.is_empty():
		if now - int(pending.get("requested_ms", now)) >= AI_TIMEOUT_MS:
			_ai_timeout(pending)
		return
	if now < int(pending.get("due_ms", now)):
		return
	if not _ai_pending_valid(pending):
		cancel_ai()
		return
	_ai_pending = {}
	ai_results += 1
	ai_compute_max_ms = maxf(ai_compute_max_ms, float(result_now.get("duration_ms", 0.0)))
	var apply_started := Time.get_ticks_usec()
	var decision: Dictionary = result_now.get("decision", {})
	if str(pending.get("kind", "")) == "turn":
		_apply_turn_action(int(pending.get("seat", current_turn)), decision)
	else:
		_process_response(int(pending.get("seat", 0)), int(pending.get("source", -1)),
			str(pending.get("tile", "")), decision)
	ai_apply_max_ms = maxf(ai_apply_max_ms, float(Time.get_ticks_usec() - apply_started) / 1000.0)

func _ai_pending_valid(pending: Dictionary) -> bool:
	if phase != Phase.PLAYING or audio_session != str(pending.get("session", "")):
		return false
	if prompt_id != int(pending.get("prompt", -1)):
		return false
	var seat := int(pending.get("seat", -1))
	if seat < 0 or seat >= controllers.size() or controllers[seat] != pending.get("actor"):
		return false
	if str(pending.get("kind", "")) == "turn":
		return current_turn == seat and not awaiting and _awaiting_response.is_empty() and _pending_responders.is_empty()
	return _response_stage == int(pending.get("stage", ResponseStage.NONE)) \
		and not _pending_responders.is_empty() and int(_pending_responders[0]) == seat

func _ai_timeout(pending: Dictionary) -> void:
	ai_timeouts += 1
	if ai_service != null and ai_service.has_method("cancel"):
		ai_service.cancel(int(pending.get("token", 0)))
	_ai_pending = {}
	if not _ai_pending_valid(pending):
		return
	var seat := int(pending.get("seat", -1))
	if str(pending.get("kind", "")) == "turn":
		var options := legal_turn_options(seat)
		var fallback: Dictionary = {}
		if options.self_win:
			fallback = {"self_win": true}
		elif players[seat].ready and players[seat].just_drew != "":
			fallback = {"discard": players[seat].just_drew}
		elif not options.discards.is_empty():
			fallback = {"discard": options.discards[0]}
		if fallback.is_empty():
			return
		ai_fallbacks += 1
		_apply_turn_action(seat, fallback)
	else:
		ai_fallbacks += 1
		_process_response(seat, int(pending.get("source", -1)), str(pending.get("tile", "")), {"action": "pass"})

func restore_human_control(seat: int) -> void:
	# Only the restored seat's pending task belongs to this player. Another
	# seat's AI may be thinking while a different player reconnects; cancelling
	# it would leave that AI seat without a task forever.
	if int(_ai_pending.get("seat", -1)) == seat:
		cancel_ai()
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
	if not ACTIONS.validate_turn_submission(self, seat, decision):
		var window_ok: bool = phase == Phase.PLAYING and awaiting and _awaiting_response.is_empty() and seat == current_turn
		_recorder.request(seat, "turn", decision, false, "操作不符合当前允许清单" if window_ok else "不属于当前操作窗口")
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
	var key := var_to_bytes([seat, player.concealed, player.melds, player.just_drew, player.ready, player.first_turn_done, player.forbidden_discard_tile, _wall_count()])
	if key != _legal_turn_key:
		_legal_turn_key = key
		_legal_turn_cache = ACTIONS.turn_options(self, seat)
	return _legal_turn_cache.duplicate(true)

func legal_response_options(seat: int, source: int, tile: String, stage: ResponseStage) -> Dictionary:
	return ACTIONS.response_options(self, seat, source, tile, stage)

func allowed_actions(seat: int) -> Dictionary:
	return ACTIONS.allowed_actions(self, seat)

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
	var discard_index := int(decision.get("discard_index", -1))
	if decision.get("ready", false):
		player.ready = true
		player.announced_ready = true
		_emit_audio_event("ready", seat)
		_emit_visual_event("ready", {"seat": seat})
	_discard(seat, discard, discard_index)

func _discard(seat: int, tile: String, discard_index: int = -1) -> void:
	var player: PlayerState = players[seat]
	if not player.concealed.has(tile):
		return
	# New clients submit the exact concealed-array index.  Keep the old tile-only
	# path for older network peers and AI controllers.
	# The drawn tile is represented in the same concealed array as the hand.
	# When an older client submits only a tile name, prefer the newest matching
	# entity so a duplicate hand tile cannot steal the draw animation.
	var drawn_tile := player.just_drew
	var drawn_source_index := -1
	if drawn_tile != "":
		for index in range(player.concealed.size() - 1, -1, -1):
			if str(player.concealed[index]) == drawn_tile:
				drawn_source_index = index
				break
	var source_index := drawn_source_index if tile == drawn_tile and drawn_source_index >= 0 else player.concealed.find(tile)
	if discard_index >= 0 and discard_index < player.concealed.size() and str(player.concealed[discard_index]) == tile:
		source_index = discard_index
	if source_index < 0:
		return
	var discard_from_draw := drawn_source_index >= 0 and source_index == drawn_source_index
	var hand_before_cards: Array = []
	var hand_before_indices: Array = []
	for index in player.concealed.size():
		if index == drawn_source_index: continue
		hand_before_cards.append(str(player.concealed[index]))
		hand_before_indices.append(index)
	var discard_hand_index := -1
	if not discard_from_draw:
		var discard_occurrence := 0
		for index in hand_before_indices.size():
			if int(hand_before_indices[index]) == source_index: break
			if str(hand_before_cards[index]) == tile: discard_occurrence += 1
		discard_hand_index = _sorted_occurrence_index(Tiles.sort_hand(hand_before_cards), tile, discard_occurrence + 1)
	# Once the discarded entity is removed, this is the index that the drawn
	# entity will receive in the sorted hand row.  -1 means the drawn tile itself
	# was discarded and therefore has no insertion target.
	var drawn_index_after := -1
	var drawn_hand_index := -1
	var hand_slot_map: Dictionary = {}
	if not discard_from_draw and drawn_source_index >= 0:
		drawn_index_after = drawn_source_index - (1 if source_index < drawn_source_index else 0)
	player.concealed.remove_at(source_index)
	if drawn_index_after >= 0 and drawn_index_after < player.concealed.size():
		# Build the sorted row that remains after the discard, keeping each old
		# concealed index so the UI can animate the exact physical tile.
		var remaining_entries: Array = []
		for index in hand_before_indices.size():
			if int(hand_before_indices[index]) == source_index: continue
			remaining_entries.append({"tile": str(hand_before_cards[index]), "old_index": int(hand_before_indices[index])})
		var sorted_remaining: Array = Tiles.sort_hand(remaining_entries.map(func(entry): return str(entry.tile)))
		var sorted_entries: Array = []
		var used_entries: Dictionary = {}
		for value_variant in sorted_remaining:
			var value := str(value_variant)
			for entry_index in remaining_entries.size():
				if used_entries.has(entry_index) or str(remaining_entries[entry_index].tile) != value: continue
				used_entries[entry_index] = true
				sorted_entries.append(remaining_entries[entry_index])
				break
		# Keep the old discard hole when the drawn value still fits between its
		# neighboring values.  Otherwise move the row to the lower-bound slot;
		# this is what makes a drawn 6 enter before an existing 6 after a 3 is
		# discarded, while a drawn 1 can directly replace a discarded 2.
		var valid_discard_slot := discard_hand_index >= 0 and discard_hand_index <= sorted_entries.size()
		var fits_before := valid_discard_slot and (discard_hand_index <= 0 or Tiles.value_index(drawn_tile) >= Tiles.value_index(str(sorted_entries[discard_hand_index - 1].tile)))
		var fits_after := valid_discard_slot and (discard_hand_index >= sorted_entries.size() or Tiles.value_index(drawn_tile) <= Tiles.value_index(str(sorted_entries[discard_hand_index].tile)))
		if fits_before and fits_after:
			drawn_hand_index = discard_hand_index
		else:
			drawn_hand_index = sorted_entries.size()
			for slot in sorted_entries.size():
				if Tiles.value_index(drawn_tile) <= Tiles.value_index(str(sorted_entries[slot].tile)):
					drawn_hand_index = slot
					break
		sorted_entries.insert(drawn_hand_index, {"tile": drawn_tile, "old_index": drawn_source_index})
		for slot in sorted_entries.size():
			hand_slot_map[int(sorted_entries[slot].old_index)] = slot
	player.discards.append(tile)
	player.discard_history.append(tile)
	player.discard_ids.append(player.discard_count)
	player.discard_count += 1
	player.just_drew = ""
	player.first_turn_done = true
	var after_kong := _kong_draw_turn and _kong_draw_kind != KongKind.NONE
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
	_emit_visual_event("discard", {"seat": seat, "tile": tile, "discard_index": source_index,
		"discard_id": player.discard_count - 1, "charge": Tiles.is_chicken(tile) and is_charge_discard(seat, player.discards.size() - 1),
		"discard_from_draw": discard_from_draw, "draw_tile": drawn_tile,
		"drawn_source_index": drawn_source_index, "drawn_index_after": drawn_index_after,
		"drawn_hand_index": drawn_hand_index, "discard_hand_index": discard_hand_index,
		"hand_row_count": hand_before_cards.size(), "hand_slot_map": hand_slot_map})
	for index in player.melds.size():
		var meld: Dictionary = player.melds[index]
		if meld.get("concealed", false) and player.discard_count == int(meld.get("after_discard", 0)) + 2:
			_emit_visual_event("meld_reveal", {"seat": seat, "tile": meld.tile, "index": index})
	_emit_audio_event("discard", seat, tile)
	state_update.emit()
	_after_discard()

func _sorted_occurrence_index(sorted_cards: Array, tile: String, occurrence: int) -> int:
	if occurrence <= 0: return -1
	var seen := 0
	for index in sorted_cards.size():
		if str(sorted_cards[index]) != tile: continue
		seen += 1
		if seen == occurrence: return index
	return -1

func _after_discard() -> void:
	_response_stage = ResponseStage.WIN
	_pending_claims.clear()
	_pending_responders = _seat_order(int(last_discard.seat))
	_ask_next_responder(last_discard.seat, last_discard.tile)

func _seat_order(source: int) -> Array:
	return [posmod(source + CFG.TURN_DIRECTION, 4), posmod(source + CFG.TURN_DIRECTION * 2, 4), posmod(source + CFG.TURN_DIRECTION * 3, 4)]

func _clear_draw_locks(player: PlayerState) -> void:
	player.passed_win_until_draw = false
	player.passed_pong_tiles.clear()
	player.forbidden_discard_tile = ""

## Returns the seat represented by the turn light for presentation only.
## During a discard-response window the light stays on the theoretical next
## discarder. It must never be used for permissions, AI decisions, or drawing.
func presentation_turn_seat() -> int:
	if phase != Phase.PLAYING:
		return -1
	if not _awaiting_response.is_empty() or _response_stage != ResponseStage.NONE:
		var source := int(last_discard.get("seat", -1))
		return posmod(source + CFG.TURN_DIRECTION, 4) if source >= 0 else -1
	return current_turn

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
			if not _pending_wins.is_empty():
				_awaiting_response = {}
				_response_stage = ResponseStage.NONE
				_pending_claims.clear()
				_finish_discard_wins(source, tile)
				return
			if not _pending_claims.is_empty():
				_execute_deferred_claim(source, tile)
				return
			# 胡优先于杠/碰：先单独开放一轮杠响应，杠家全部过牌后
			# 才进入碰牌阶段，避免先轮到的碰家抢走后面玩家的杠。
			var kong_available := false
			for candidate in _seat_order(source):
				if legal_response_options(candidate, source, tile, ResponseStage.KONG).can_kong:
					kong_available = true
					break
			_response_stage = ResponseStage.KONG if kong_available else ResponseStage.MELD
			_pending_responders = _seat_order(source)
			_ask_next_responder(source, tile)
		elif _response_stage == ResponseStage.KONG:
			# 所有杠响应结束；重新开放碰/杠窗口，让刚才选择过牌的
			# 玩家仍可按普通规则碰牌。
			_response_stage = ResponseStage.MELD
			_pending_responders = _seat_order(source)
			_ask_next_responder(source, tile)
		elif _response_stage == ResponseStage.ROB:
			if bool(_pending_kong.get("robbed", false)):
				_finish_rob_kong_wins(source, tile)
			else:
				_complete_add_kong()
		else:
			_awaiting_response = {}
			_response_stage = ResponseStage.NONE
			current_turn = posmod(source + CFG.TURN_DIRECTION, 4)
			if not _pending_wins.is_empty():
				_finish_discard_wins(source, tile)
				return
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
		if _request_async_ai_response(seat, source, tile, options, actor):
			return
		_queue_ai_response(seat, source, tile, options, actor)
	else:
		prompt_id += 1
		awaiting = true
		_awaiting_response = {"seat": seat, "disc_seat": source, "tile": tile, "options": options, "stage": _response_stage}
		require_response.emit(seat, source, tile, options)
		state_update.emit()

func _queue_ai_response(seat: int, source: int, tile: String, options: Dictionary, actor: Object) -> void:
	# A brief fixed claim beat; never waits for AI turn speed or tile animation.
	var decision: Dictionary = actor.decide_response(self, seat, source, tile, options)
	if decision.get("action", "pass") == "pass" or ai_response_delay_seconds <= 0.0:
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
	await tree.create_timer(ai_response_delay_seconds).timeout
	if audio_session != session or phase != Phase.PLAYING or _pending_responders.is_empty() or _pending_responders[0] != seat or _response_stage != stage or prompt_id != prompt or controllers[seat] != actor:
		return
	_process_response(seat, source, tile, decision)

func submit_response(seat: int, tile: String, decision: Dictionary) -> bool:
	if not ACTIONS.validate_response_submission(self, seat, tile, decision):
		var window_ok: bool = phase == Phase.PLAYING and awaiting and _awaiting_response.get("seat", -1) == seat and _awaiting_response.get("tile", "") == tile
		_recorder.request(seat, "response", decision, false, "操作不符合当前允许清单" if window_ok else "响应座位或牌面已过期")
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
			if not bool(_pending_kong.get("robbed", false)):
				player.concealed.erase(tile)
				player.just_drew = ""
				_pending_kong["robbed"] = true
			round_meta.robber_seat = seat
			round_meta.burn_chicken_seat = source
			round_meta.burn_chicken_reason = "robbed_added_kong"
			_pending_wins.append({"seat": seat, "source": source, "tile": tile})
			if not _pending_responders.is_empty() and _pending_responders[0] == seat:
				_pending_responders.pop_front()
			_ask_next_responder(source, tile)
		else:
			if ACTIONS.is_post_kong_discard(last_discard):
				round_meta.robber_seat = seat
				round_meta.burn_chicken_seat = source
				round_meta.burn_chicken_reason = "after_kong_discard"
			# 同一张牌允许多家同胡；等响应窗口结束后统一落账。
			_pending_wins.append({"seat": seat, "source": source, "tile": tile})
			if not _pending_responders.is_empty() and _pending_responders[0] == seat:
				_pending_responders.pop_front()
			_ask_next_responder(source, tile)
		return
	if not _pending_responders.is_empty() and _pending_responders[0] == seat:
		_pending_responders.pop_front()
	var player: PlayerState = players[seat]
	if _response_stage == ResponseStage.WIN and action in ["pong", "kong"]:
		# 放弃胡，先记录碰/杠意图；其他胡家的响应结束后再决定能否落账。
		_pending_claims.append({"seat": seat, "source": source, "tile": tile, "action": action})
		player.passed_win_until_draw = true
		_ask_next_responder(source, tile)
		return
	if action == "pass":
		if _response_stage in [ResponseStage.WIN, ResponseStage.ROB]:
			player.passed_win_until_draw = true
		elif _response_stage == ResponseStage.MELD and options.can_pong and not player.passed_pong_tiles.has(tile):
			player.passed_pong_tiles.append(tile)
	if action == "kong" and options.can_kong:
		var source_discard_id: int = _discard_id_for_tile(source, tile)
		var hand_indices := _visual_hand_indices(player.concealed, tile, 3)
		_remove_n(player.concealed, tile, 3)
		player.melds.append({"kind": "kong", "tile": tile, "robbed": false, "from_seat": source, "after_discard": player.discard_count})
		_remove_from_discards(source, tile, seat, "meld", player.melds.size() - 1)
		current_turn = seat
		_kong_draw_kind = KongKind.EXPOSED
		_emit_audio_event("kong", seat)
		_emit_visual_event("meld", {"seat": seat, "source": source, "source_discard_id": source_discard_id, "hand_indices": hand_indices, "tile": tile, "kind": "kong", "index": player.melds.size() - 1})
		_state_after_kong_draw()
		return
	if action == "pong" and options.can_pong:
		# Choosing pong when exposed kong was available forfeits add-kong for
		# this tile for the rest of the round.
		if options.can_kong and not player.add_kong_locked_tiles.has(tile):
			player.add_kong_locked_tiles.append(tile)
		var source_discard_id: int = _discard_id_for_tile(source, tile)
		var hand_indices := _visual_hand_indices(player.concealed, tile, 2)
		_remove_n(player.concealed, tile, 2)
		player.melds.append({"kind": "pung", "tile": tile, "robbed": false, "from_seat": source, "after_discard": player.discard_count})
		_remove_from_discards(source, tile, seat, "meld", player.melds.size() - 1)
		player.just_drew = ""
		player.forbidden_discard_tile = tile
		current_turn = seat
		_kong_draw_turn = false
		_emit_visual_event("meld", {"seat": seat, "source": source, "source_discard_id": source_discard_id, "hand_indices": hand_indices, "tile": tile, "kind": "pung", "index": player.melds.size() - 1})
		_emit_audio_event("pong", seat)
		_ask_turn_actor()
		return
	_ask_next_responder(source, tile)

func _execute_deferred_claim(source: int, tile: String) -> void:
	if str(last_discard.get("tile", "")) != tile or int(last_discard.get("seat", -1)) != source:
		_pending_claims.clear()
		_ask_next_responder(source, tile)
		return
	var claims := _pending_claims.duplicate(true)
	claims.sort_custom(func(a, b):
		var ak := 1 if str(a.get("action", "")) == "kong" else 0
		var bk := 1 if str(b.get("action", "")) == "kong" else 0
		if ak != bk: return ak > bk
		return _seat_order(source).find(int(a.seat)) < _seat_order(source).find(int(b.seat)))
	for raw in claims:
		var claim: Dictionary = raw
		var seat := int(claim.get("seat", -1))
		if seat < 0 or seat >= players.size(): continue
		var action := str(claim.get("action", ""))
		var claim_stage := ResponseStage.KONG if action == "kong" else ResponseStage.MELD
		var options := legal_response_options(seat, source, tile, claim_stage)
		if (action == "kong" and not options.can_kong) or (action == "pong" and not options.can_pong):
			continue
		var player: PlayerState = players[seat]
		_pending_claims.clear()
		_pending_responders.clear()
		_awaiting_response = {}
		_response_stage = ResponseStage.NONE
		awaiting = false
		var source_discard_id := _discard_id_for_tile(source, tile)
		if action == "kong":
			var hand_indices := _visual_hand_indices(player.concealed, tile, 3)
			_remove_n(player.concealed, tile, 3)
			player.melds.append({"kind": "kong", "tile": tile, "robbed": false, "from_seat": source, "after_discard": player.discard_count})
			_remove_from_discards(source, tile, seat, "meld", player.melds.size() - 1)
			current_turn = seat
			_kong_draw_kind = KongKind.EXPOSED
			_emit_audio_event("kong", seat)
			_emit_visual_event("meld", {"seat": seat, "source": source, "source_discard_id": source_discard_id,
				"hand_indices": hand_indices, "tile": tile, "kind": "kong", "index": player.melds.size() - 1})
			_state_after_kong_draw()
		else:
			if options.can_kong and not player.add_kong_locked_tiles.has(tile):
				player.add_kong_locked_tiles.append(tile)
			var hand_indices := _visual_hand_indices(player.concealed, tile, 2)
			_remove_n(player.concealed, tile, 2)
			player.melds.append({"kind": "pung", "tile": tile, "robbed": false, "from_seat": source, "after_discard": player.discard_count})
			_remove_from_discards(source, tile, seat, "meld", player.melds.size() - 1)
			player.just_drew = ""
			player.forbidden_discard_tile = tile
			current_turn = seat
			_kong_draw_turn = false
			_emit_visual_event("meld", {"seat": seat, "source": source, "source_discard_id": source_discard_id,
				"hand_indices": hand_indices, "tile": tile, "kind": "pung", "index": player.melds.size() - 1})
			_emit_audio_event("pong", seat)
			_ask_turn_actor()
		return
	_pending_claims.clear()
	_ask_next_responder(source, tile)

func _finish_discard_wins(source: int, tile: String) -> void:
	if _pending_wins.is_empty():
		return
	_pending_wins.sort_custom(func(a, b): return _seat_order(source).find(int(a.seat)) < _seat_order(source).find(int(b.seat)))
	var winners: Array = []
	for entry in _pending_wins:
		var seat := int(entry.get("seat", -1))
		if seat < 0 or seat >= players.size():
			continue
		winners.append(seat)
	# 牌只从弃牌者记录移除一次，每位胡牌者各收到一张逻辑胡牌牌。
	_remove_from_discards(source, tile, winners[0], "hand")
	for seat in winners:
		players[seat].concealed.append(tile)
		players[seat].just_drew = tile
	round_meta.winners = winners.duplicate()
	round_meta.winner = winners[0]
	round_meta.self_draw = false
	round_meta.discard_seat = source
	round_meta.win_tile = tile
	_pending_wins.clear()
	_finish()

func _finish_rob_kong_wins(source: int, tile: String) -> void:
	var winners: Array = []
	for entry in _pending_wins:
		var seat := int(entry.get("seat", -1))
		if seat < 0 or seat >= players.size():
			continue
		winners.append(seat)
	for seat in winners:
		players[seat].concealed.append(tile)
		players[seat].just_drew = tile
	round_meta.winners = winners.duplicate()
	round_meta.winner = winners[0]
	round_meta.self_draw = false
	round_meta.robbed_kong = true
	round_meta.burn_chicken_seat = source
	round_meta.burn_chicken_reason = "robbed_added_kong"
	round_meta.discard_seat = source
	round_meta.win_tile = tile
	_pending_wins.clear()
	_pending_kong = {}
	_finish()

func _state_after_kong_draw() -> void:
	_draw_remaining_before = wall.remaining
	var tile := wall.draw_tail()
	if tile == "":
		_penzu()
		return
	var player: PlayerState = players[current_turn]
	_clear_draw_locks(player)
	player.just_drew = tile
	player.concealed.append(tile)
	_emit_visual_event("draw", {"seat": current_turn, "tile": tile, "kind": "tail"})
	_kong_draw_turn = true
	_ask_turn_actor()

func _do_concealed_kong(seat: int, tile: String, player: PlayerState) -> void:
	if player.ready or Tiles.count(player.concealed, tile) < 4 or _wall_count() < 1:
		return
	var hand_indices := _visual_hand_indices(player.concealed, tile, 4)
	_remove_n(player.concealed, tile, 4)
	player.melds.append({"kind": "kong", "tile": tile, "robbed": false, "concealed": true, "after_discard": player.discard_count})
	current_turn = seat
	_kong_draw_kind = KongKind.CONCEALED
	_emit_visual_event("meld", {"seat": seat, "tile": "", "hand_indices": hand_indices, "kind": "concealed", "index": player.melds.size() - 1})
	# 只喊“杠”，公共声音事件不能泄露暗杠的牌。
	_emit_audio_event("kong", seat)
	_state_after_kong_draw()

func _do_add_kong(seat: int, tile: String) -> bool:
	var player: PlayerState = players[seat]
	if player.ready or player.just_drew != tile or player.add_kong_locked_tiles.has(tile) \
		or not player.concealed.has(tile) or _wall_count() < 1:
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
	var hand_indices := _visual_hand_indices(player.concealed, tile, 1)
	player.concealed.erase(tile)
	player.melds[_pending_kong.index].kind = "add_kong"
	player.melds[_pending_kong.index]["after_discard"] = player.discard_count
	_emit_visual_event("meld", {"seat": seat, "tile": tile, "hand_indices": hand_indices, "kind": "add_kong", "index": int(_pending_kong.index)})
	_pending_kong = {}
	_awaiting_response = {}
	current_turn = seat
	_kong_draw_kind = KongKind.ADD_KONG
	_state_after_kong_draw()

func _do_self_win(seat: int) -> void:
	round_meta.winner = seat
	round_meta.winners = [seat]
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
	round_meta.winners = [seat]
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
		var was_charge := is_charge_discard(seat, index)
		# 被胡的弃牌会进入赢家的逻辑手牌，不能再从出牌鸡结算中消失。
		# 碰/杠时鸡牌转入面子，仍由面子所有者计分，因此只记录 hand。
		if location == "hand" and Tiles.is_chicken(tile):
			var resolved: Array = round_meta.get("resolved_chicken_discards", [])
			resolved.append({"owner": seat, "tile": tile, "charge": was_charge,
				"discard_id": player.discard_ids[index] if index < player.discard_ids.size() else -1})
			round_meta["resolved_chicken_discards"] = resolved
		if was_charge:
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

func _discard_id_for_tile(seat: int, tile: String) -> int:
	if seat < 0 or seat >= players.size():
		return -1
	var player: PlayerState = players[seat]
	var index: int = player.discards.rfind(tile)
	if index < 0:
		return -1
	return int(player.discard_ids[index]) if index < player.discard_ids.size() else index

func _penzu() -> void:
	round_meta.winner = -1
	round_meta.winners = []
	_finish()

func _finish() -> void:
	cancel_ai()
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
	if not is_zero_approx(_last_total):
		# assert() is stripped from release builds; keep the invariant visible in
		# production logs and expose the imbalance to callers instead of silently
		# accepting a broken ledger.
		push_error("Settlement must preserve the four players' total score: %.6f" % _last_total)
		round_meta.ledger_error = _last_total
	last_result = build_result()
	if round_meta.has("ledger_error"):
		last_result["ledger_error"] = _last_total
	_recorder.finish(self)
	if int(round_meta.winner) >= 0:
		_emit_visual_event("win", {"seat": int(round_meta.winner), "winners": round_meta.get("winners", [int(round_meta.winner)]).duplicate(), "tile": str(round_meta.get("win_tile", "")), "self_draw": bool(round_meta.get("self_draw", false))})
	_audio.emit_win(round_meta)
	round_finished.emit(last_result)
	state_update.emit()

func _choose_next_dealer(called: Array) -> int:
	var winner := int(round_meta.get("winner", -1))
	if winner >= 0:
		# 多赢家规则经用户确认：本局净得分最高的赢家做庄，并列随机。
		var winners: Array = round_meta.get("winners", []).duplicate()
		if winners.is_empty():
			winners.append(winner)
		var best: Array = []
		var highest := -INF
		for seat in winners:
			var delta := float(_last_deltas[int(seat)])
			if delta > highest:
				highest = delta
				best = [int(seat)]
			elif is_equal_approx(delta, highest):
				best.append(int(seat))
		return best[0] if best.size() == 1 else best[_rng.randi_range(0, best.size() - 1)]
	var candidates: Array = []
	var lowest := INF
	for seat in SEATS:
		if called[seat]:
			continue
		var delta := float(_last_deltas[seat])
		if delta < lowest:
			lowest = delta
			candidates = [seat]
		elif is_equal_approx(delta, lowest):
			candidates.append(seat)
	if candidates.is_empty():
		return dealer_seat
	return candidates[_rng.randi_range(0, candidates.size() - 1)]

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
	cancel_ai()
	SERIALIZER.apply_sync(self, state)

func serialize_for_seat(seat: int) -> Dictionary:
	return SERIALIZER.serialize_for_seat(self, seat)

func mask_for_seat(base_state: Dictionary, seat: int) -> Dictionary:
	return SERIALIZER.mask_for_seat(base_state, self, seat)

func export_replay(path: String = "") -> String:
	return _recorder.save(path)

func replay_record() -> Dictionary:
	return _recorder.record.duplicate(true)

# Presentation metadata only: positions of consumed entities, never hidden values.
func _visual_hand_indices(cards: Array, tile: String, count: int) -> Array:
	var indices: Array = []
	for index in cards.size():
		if cards[index] == tile:
			indices.append(index)
			if indices.size() == count: break
	return indices

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
