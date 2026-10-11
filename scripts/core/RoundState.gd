class_name RoundState
extends RefCounted

signal require_turn(seat)
signal require_response(seat, discarded_seat, tile, options)
signal round_finished(result)
signal state_update()
signal dealt(info)

const SEATS := [0, 1, 2, 3]
const CFG := preload("res://scripts/autoload/GameConfig.gd")
var players: Array = []
var controllers: Array = []
var wall: WallRing
var current_turn := 0
var awaiting := false
var phase := "idle"
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
var _response_stage := ""
var _pending_kong := {}
var _last_deltas: Array = [0.0, 0.0, 0.0, 0.0]
var _last_lines: Array = []
var _last_total := 0.0
var _last_points: Array = []
var _last_transfers: Array = []
var _draw_remaining_before := 108
var _kong_draw_turn := false
var ai_delay_seconds := 0.0
var next_chicken_multiplier := 1

func _init() -> void:
	_reset_meta()

func _reset_meta() -> void:
	round_meta = {
		"charge_chickens": {}, "flip_tile": "", "chicken_multiplier": 1,
		"kong_draw_seat": -1, "last_four_self_draw_seat": -1,
		"robber_seat": -1, "burn_chicken_seat": -1,
		"winner": -1, "self_draw": false,
	}

func build_players(human_seat: int) -> void:
	players.clear()
	for seat in SEATS:
		var player := PlayerState.new()
		player.init_seat(seat, seat == human_seat, seat == 0, ["庄家", "下家", "对家", "上家"][seat])
		player.score = CFG.START_SCORE
		players.append(player)

func start_round(human_seat: int, die_override: int = -1) -> void:
	var scores: Array = []
	for player in players:
		scores.append(player.score)
	build_players(human_seat)
	if scores.size() == 4:
		apply_scores(scores)
	_reset_meta()
	last_result = {}
	round_meta.chicken_multiplier = clampi(next_chicken_multiplier, 1, CFG.MAX_CHICKEN_MULTIPLIER)
	next_chicken_multiplier = 1
	last_discard = {}
	_pending_kong = {}
	_awaiting_response = {}
	_response_stage = ""
	_pending_responders.clear()
	_steps = 0
	_turn_count = 0
	awaiting = false
	_kong_draw_turn = false
	var built := WallBuilder.setup(_rng)
	wall = WallRing.new(built.ring)
	var die := die_override if die_override >= 1 and die_override <= 6 else _rng.randi_range(1, 6)
	round_meta["die"] = die
	round_meta["break"] = WallRing.compute_break(die)
	wall.set_head(round_meta["break"])
	phase = "dealing"
	_initial_deal()
	phase = "playing"
	current_turn = 0
	_begin_turn()

func _initial_deal() -> void:
	for batch in 3:
		for seat in SEATS:
			for index in 4:
				players[seat].concealed.append(wall.draw_head())
	for seat in SEATS:
		players[seat].concealed.append(wall.draw_head())
	var info: Array = []
	for player in players:
		info.append({"seat": player.seat, "count": player.concealed.size()})
	dealt.emit(info)

func _begin_turn() -> void:
	if phase != "playing":
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
	_response_stage = ""
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
	awaiting = false
	state_update.emit()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_apply_turn_action(seat, actor.decide_turn(self, seat))
		return
	await tree.create_timer(ai_delay_seconds).timeout
	if phase != "playing" or current_turn != seat or not _awaiting_response.is_empty():
		return
	_apply_turn_action(seat, actor.decide_turn(self, seat))

func submit_turn(seat: int, decision: Dictionary) -> bool:
	if phase != "playing" or not awaiting or not _awaiting_response.is_empty() or seat != current_turn:
		return false
	if not _valid_turn(seat, decision):
		return false
	awaiting = false
	_apply_turn_action(seat, decision)
	return true

func _valid_turn(seat: int, decision: Dictionary) -> bool:
	var player: PlayerState = players[seat]
	if decision.get("self_win", false):
		return player.just_drew != "" and _hand_is_win(player)
	if not player.ready and _wall_count() > 0:
		for tile in decision.get("kong_declares", []):
			if Tiles.count(player.concealed, tile) >= 4:
				return true
		for tile in decision.get("add_kong", []):
			for meld in player.melds:
				if meld.kind == "pung" and meld.tile == tile and player.concealed.has(tile):
					return true
	var discard: String = player.just_drew if player.ready else decision.get("discard", "")
	if not player.concealed.has(discard):
		return false
	if decision.get("ready", false):
		var after := player.concealed.duplicate()
		after.erase(discard)
		return can_declare_ready(seat) and RuleEngine.is_tenpai(after, player.melds)
	return true

func _apply_turn_action(seat: int, decision: Dictionary) -> void:
	var player: PlayerState = players[seat]
	if decision.get("self_win", false) and player.just_drew != "" and _hand_is_win(player):
		_do_self_win(seat)
		return
	if not player.ready and _wall_count() > 0:
		for tile in decision.get("kong_declares", []):
			if Tiles.count(player.concealed, tile) >= 4:
				_do_concealed_kong(seat, tile, player)
				return
		for tile in decision.get("add_kong", []):
			for meld in player.melds:
				if meld.kind == "pung" and meld.tile == tile and player.concealed.has(tile):
					_do_add_kong(seat, tile)
					return
	var discard: String = player.just_drew if player.ready else decision.get("discard", "")
	if not player.concealed.has(discard):
		discard = player.just_drew if player.concealed.has(player.just_drew) else str(player.concealed[0])
	if decision.get("ready", false) and can_declare_ready(seat):
		var after := player.concealed.duplicate()
		after.erase(discard)
		if RuleEngine.is_tenpai(after, player.melds):
			player.ready = true
			player.announced_ready = true
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
	_kong_draw_turn = false
	last_discard = {"seat": seat, "tile": tile}
	if Tiles.is_chicken(tile) and not has_charge(tile):
		round_meta.charge_chickens[tile] = {"owner": seat, "location": "discard", "discard_id": player.discard_count - 1}
		_refresh_charge_flags()
	state_update.emit()
	_after_discard()

func _after_discard() -> void:
	_response_stage = "win"
	_pending_responders = _seat_order(int(last_discard.seat))
	_ask_next_responder(last_discard.seat, last_discard.tile)

func _seat_order(source: int) -> Array:
	return [(source + 1) % 4, (source + 2) % 4, (source + 3) % 4]

func _response_options(seat: int, tile: String) -> Dictionary:
	var player: PlayerState = players[seat]
	return {
		"can_win": _response_stage in ["win", "rob"] and RuleEngine.can_win_on(player.concealed, player.melds, tile),
		"can_pong": _response_stage == "meld" and not player.ready and Tiles.count(player.concealed, tile) >= 2,
		"can_kong": _response_stage == "meld" and not player.ready and _wall_count() > 0 and Tiles.count(player.concealed, tile) >= 3,
		"rob_kong": _response_stage == "rob",
	}

func _ask_next_responder(source: int, tile: String) -> void:
	if phase != "playing":
		return
	if _pending_responders.is_empty():
		if _response_stage == "win":
			_response_stage = "meld"
			_pending_responders = _seat_order(source)
			_ask_next_responder(source, tile)
		elif _response_stage == "rob":
			_complete_add_kong()
		else:
			_awaiting_response = {}
			_response_stage = ""
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
	awaiting = false
	state_update.emit()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		_process_response(seat, source, tile, actor.decide_response(self, seat, source, tile, options))
		return
	await tree.create_timer(ai_delay_seconds).timeout
	if phase != "playing" or _pending_responders.is_empty() or _pending_responders[0] != seat or _response_stage == "":
		return
	_process_response(seat, source, tile, actor.decide_response(self, seat, source, tile, options))

func submit_response(seat: int, tile: String, decision: Dictionary) -> bool:
	if phase != "playing" or not awaiting or _awaiting_response.get("seat", -1) != seat or _awaiting_response.get("tile", "") != tile:
		return false
	var action: String = decision.get("action", "pass")
	var options := _response_options(seat, tile)
	if action != "pass" and not options.get({"win": "can_win", "pong": "can_pong", "kong": "can_kong"}.get(action, "invalid"), false):
		return false
	var source: int = _awaiting_response.disc_seat
	awaiting = false
	_awaiting_response = {}
	_process_response(seat, source, tile, decision)
	return true

func _process_response(seat: int, source: int, tile: String, decision: Dictionary) -> void:
	var action: String = decision.get("action", "pass")
	var options := _response_options(seat, tile)
	if action == "win" and options.can_win:
		if _response_stage == "rob":
			var player: PlayerState = players[source]
			player.concealed.erase(tile)
			player.just_drew = ""
			round_meta.robber_seat = seat
			round_meta.burn_chicken_seat = source
			_pending_kong = {}
			_discard_win(seat, source, tile, true)
		else:
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
		_state_after_kong_draw()
		return
	if action == "pong" and options.can_pong:
		_remove_n(player.concealed, tile, 2)
		player.melds.append({"kind": "pung", "tile": tile, "robbed": false, "from_seat": source, "after_discard": player.discard_count})
		_remove_from_discards(source, tile, seat, "meld", player.melds.size() - 1)
		player.just_drew = ""
		current_turn = seat
		_kong_draw_turn = false
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
	_state_after_kong_draw()

func _do_add_kong(seat: int, tile: String) -> bool:
	var player: PlayerState = players[seat]
	if player.ready or not player.concealed.has(tile) or _wall_count() < 1:
		return false
	for index in player.melds.size():
		if player.melds[index].kind == "pung" and player.melds[index].tile == tile:
			_pending_kong = {"seat": seat, "tile": tile, "index": index}
			_response_stage = "rob"
			_pending_responders = _seat_order(seat)
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
	_state_after_kong_draw()

func _do_self_win(seat: int) -> void:
	round_meta.winner = seat
	round_meta.self_draw = true
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
	phase = "settled"
	awaiting = false
	_awaiting_response = {}
	round_meta.flip_tile = wall.peek_head() if wall != null and round_meta.winner >= 0 else ""
	var scored := ScoringEngine.settle(self)
	_last_deltas = scored.deltas
	_last_lines = scored.lines
	_last_points = scored.points
	_last_transfers = scored.transfers
	next_chicken_multiplier = int(scored.next_chicken_multiplier)
	round_meta.all_called_draw = scored.all_called_draw
	round_meta.next_chicken_multiplier = next_chicken_multiplier
	_last_total = 0.0
	for seat in SEATS:
		players[seat].score += scored.deltas[seat]
		_last_total += scored.deltas[seat]
	assert(is_zero_approx(_last_total), "Settlement must preserve the four players' total score")
	last_result = build_result()
	round_finished.emit(last_result)
	state_update.emit()

func build_result() -> Dictionary:
	var result := {
		"round_meta": round_meta.duplicate(true), "scores": [], "players": [],
		"deltas": _last_deltas, "lines": _last_lines, "points": _last_points,
		"transfers": _last_transfers, "total_delta": _last_total,
		"flip_tile": round_meta.get("flip_tile", ""),
		"next_chicken_multiplier": next_chicken_multiplier,
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
	var player: PlayerState = players[seat]
	return not player.first_turn_done and player.just_drew != "" and player.melds.all(func(meld): return meld.kind == "kong" and meld.get("concealed", false))

func _wall_count() -> int:
	if wall != null:
		return wall.remaining
	var count := 0
	for seat in SEATS:
		count += int(wall_remain.get(seat, 0))
	return count

func serialize() -> Dictionary:
	var state := {
		"current_turn": current_turn, "phase": phase, "round_meta": round_meta.duplicate(true),
		"last_discard": last_discard.duplicate(), "awaiting": awaiting, "prompt_id": prompt_id,
		"awaiting_response": _awaiting_response.duplicate(true), "last_result": last_result.duplicate(true),
		"players": [], "wall": {}, "wall_stacks": {}, "next_chicken_multiplier": next_chicken_multiplier,
	}
	for player in players:
		state.players.append({
			"seat": player.seat, "concealed": player.concealed.duplicate(),
			"melds": player.melds.duplicate(true), "discards": player.discards.duplicate(),
			"discard_history": player.discard_history.duplicate(),
			"discard_ids": player.discard_ids.duplicate(), "discard_count": player.discard_count,
			"score": player.score, "ready": player.ready, "name": player.name_label,
			"is_human": player.is_human, "is_dealer": player.is_dealer, "just_drew": player.just_drew,
			"first_turn_done": player.first_turn_done, "charge_chicken": player.charge_chicken,
		})
	for seat in SEATS:
		state.wall[seat] = wall.wall_remaining(seat)
		state.wall_stacks[seat] = wall.wall_stack_counts(seat)
	return state

func apply_sync(state: Dictionary) -> void:
	players.clear()
	for data in state.players:
		var player := PlayerState.new()
		player.seat = int(data.seat)
		player.concealed = data.concealed.duplicate()
		player.melds = data.melds.duplicate(true)
		player.discards = data.discards.duplicate()
		player.discard_history = data.get("discard_history", data.discards).duplicate()
		player.discard_ids = data.get("discard_ids", []).duplicate()
		player.discard_count = int(data.get("discard_count", player.discard_history.size()))
		player.score = float(data.score)
		player.ready = data.ready
		player.name_label = data.name
		player.is_human = data.is_human
		player.is_dealer = data.get("is_dealer", player.seat == 0)
		player.just_drew = data.get("just_drew", "")
		player.first_turn_done = data.get("first_turn_done", false)
		player.charge_chicken = data.get("charge_chicken", false)
		players.append(player)
	current_turn = int(state.current_turn)
	phase = state.phase
	round_meta = state.round_meta.duplicate(true)
	next_chicken_multiplier = int(state.get("next_chicken_multiplier", 1))
	last_discard = state.last_discard.duplicate()
	awaiting = state.awaiting
	prompt_id = int(state.get("prompt_id", 0))
	_awaiting_response = state.get("awaiting_response", {}).duplicate(true)
	last_result = state.get("last_result", {}).duplicate(true)
	wall_remain = state.wall.duplicate()
	wall_stacks = state.get("wall_stacks", {}).duplicate(true)

func serialize_for_seat(seat: int) -> Dictionary:
	var state := serialize()
	if phase == "settled":
		return state
	for player in state.players:
		if int(player.seat) == seat:
			continue
		player.concealed.fill("hidden0")
		if player.just_drew != "":
			player.just_drew = "hidden0"
		for meld in player.melds:
			if meld.get("concealed", false):
				meld.tile = "hidden0"
	return state

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
