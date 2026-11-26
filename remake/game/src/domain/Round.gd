extends RefCounted
## 权威行牌状态。实体牌在本局的 ID 等于洗牌后固定的初始墙槽。

const Wall = preload("res://src/domain/Wall.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Seats = preload("res://src/domain/Seats.gd")
const Rules = preload("res://src/anshun/scoring/RuleEngine.gd")
const KongRules = preload("res://src/anshun/scoring/KongRules.gd")
const Tiles = preload("res://src/anshun/scoring/Tiles.gd")

var wall
var players: Array = []
var phase := "idle"
var turn := -1
var prompt_id := 0
var last_discard := {}
var round_meta := {}
var events: Array = [] # 权威记录含私牌，不能直接广播。
var _audio_events: Array = []
var _last_audio_id := 0
var _response := {}
var _turn_options := {}
var _draw_kind := "none"
var _before_draw := 0

func start(dealer: int, red: int, white: int, shuffled_values: Array, carry_multiplier: int = 1) -> bool:
	if phase not in ["idle", "settled"] or dealer not in range(4) or red not in range(1, 7) or white not in range(1, 7):
		return false
	if carry_multiplier not in [1, 2] or not Catalog.valid_deck(shuffled_values):
		return false
	wall = Wall.new(shuffled_values)
	wall.open(dealer, red)
	players.clear()
	for seat in 4:
		players.append({"seat": seat, "hand": [], "draw_id": -1, "melds": [], "discards": [],
			"ready": false, "ready_ids": [], "normal_draws": 0, "discard_count": 0,
			"pass_win": false, "pass_pong": [], "dark_locked": [], "forbidden": ""})
	turn = dealer
	last_discard = {}
	_response = {}
	_draw_kind = "none"
	events.clear()
	_audio_events.clear()
	_last_audio_id = 0
	round_meta = {"dealer_seat": dealer, "die": red, "die_white": white,
		"chicken_multiplier": 2 if red == white else carry_multiplier,
		"winner": -1, "winners": [], "self_draw": false, "win_tile": "", "win_tile_id": -1,
		"discard_seat": -1, "robbed_kong": false, "burn_chicken_seat": -1, "burn_chicken_reason": "",
		"kong_draw_seat": -1, "last_four_self_draw_seat": -1, "flip_tile": "", "flip_wall_index": -1,
		"charge_chickens": {}, "resolved_chicken_discards": []}
	for amount in [4, 4, 4, 1]:
		var seat := dealer
		for _player in 4:
			var ids: Array = []
			for _tile in amount:
				var id: int = wall.take_head()
				players[seat].hand.append(id)
				ids.append(id)
			events.append({"type": "deal", "seat": seat, "ids": ids})
			seat = Seats.next(seat)
	_enter("dealt")
	return true

func begin_dealer_turn() -> bool:
	if phase != "dealt":
		return false
	_draw(turn, "none")
	return true

func _enter(new_phase: String) -> void:
	phase = new_phase
	prompt_id += 1
	_turn_options = {}

func _draw(seat: int, kind: String) -> void:
	turn = seat
	_draw_kind = kind
	_before_draw = wall.remaining
	var id: int = wall.take_head() if kind == "none" else wall.take_tail()
	if id < 0:
		_finish([], -1, -1, false, false)
		return
	var p: Dictionary = players[seat]
	p.self_win_declined = false
	p.hand.append(id)
	p.draw_id = id
	if kind == "none":
		p.normal_draws += 1
	events.append({"type": "draw", "seat": seat, "id": id, "kind": kind})
	_enter("ready_draw" if p.ready else "turn")

## 报听者等本人摸牌可见后才自动出牌，能自摸时进入单独的胡／过窗口。
func finish_draw_animation(seat: int, expected_prompt: int) -> bool:
	if phase != "ready_draw" or seat != turn or expected_prompt != prompt_id:
		return false
	if _self_win(players[seat]):
		_enter("turn")
	else:
		_discard(seat, players[seat].draw_id, false)
	return true

func choices(seat: int) -> Dictionary:
	if seat not in range(4):
		return {}
	if phase == "response":
		if not _response.options.has(seat) or _response.answers.has(seat):
			return {}
		return {"prompt_id": prompt_id, "actions": _response.options[seat].duplicate(),
			"source": _response.source, "tile_id": _response.id, "value": wall.value(_response.id)}
	if phase != "turn" or seat != turn:
		return {}
	if _turn_options.is_empty():
		_turn_options = _build_turn_options(players[seat])
	return _turn_options.duplicate(true)

func _values(ids: Array) -> Array:
	var result := []
	for id in ids:
		result.append(wall.value(id))
	return result

func _self_win(p: Dictionary) -> bool:
	return p.draw_id >= 0 and Rules.analyze(_values(p.hand), p.melds, wall.value(p.draw_id)).win

func _build_turn_options(p: Dictionary) -> Dictionary:
	var options := {"actions": [], "prompt_id": prompt_id, "discard_ids": [], "ready_ids": [],
		"concealed_kong_ids": [], "add_kong_ids": []}
	if _self_win(p) and not p.get("self_win_declined", false):
		options.actions.append("self_win")
	if p.ready:
		options.actions.append("pass")
		return options
	var hand := _values(p.hand)
	var checked := {}
	for id in p.hand:
		var value: String = wall.value(id)
		if value == p.forbidden:
			continue
		options.discard_ids.append(id)
		if not checked.has(value):
			var can_ready := false
			if p.normal_draws == 1 and p.draw_id >= 0 and p.discard_count == 0 and p.melds.is_empty():
				var after := hand.duplicate()
				after.erase(value)
				can_ready = Rules.is_tenpai(after, [])
			checked[value] = can_ready
			if p.draw_id >= 0 and wall.remaining > 0 and hand.count(value) == 4 and not p.dark_locked.has(value):
				options.concealed_kong_ids.append(id)
		if checked[value]:
			options.ready_ids.append(id)
	if wall.remaining > 0 and p.draw_id >= 0:
		for meld in p.melds:
			if meld.kind == "pung" and meld.tile == wall.value(p.draw_id):
				options.add_kong_ids.append(p.draw_id)
				break
	for action in ["discard", "ready", "concealed_kong", "add_kong"]:
		if not options[action + "_ids"].is_empty():
			options.actions.append(action)
	return options

func submit(seat: int, expected_prompt: int, action: String, tile_id: int = -1) -> bool:
	if expected_prompt != prompt_id:
		return false
	var options := choices(seat)
	# Sorting is an explicit owner request, not a new AI action or an automatic discard.
	if action == "sort":
		if phase != "turn" or seat != turn or tile_id != -1 or not options.get("actions", []).has("self_win"): return false
		if players[seat].ready: return submit(seat, expected_prompt, "pass")
		players[seat].self_win_declined = true
		_turn_options = {}
		events.append({"type": "pass_self_win", "seat": seat, "prompt_id": prompt_id, "reason": "sort"})
		return true
	if not options.get("actions", []).has(action):
		return false
	if phase == "response":
		if tile_id != -1 and tile_id != _response.id:
			return false
		_response.answers[seat] = action
		events.append({"type": "response", "seat": seat, "prompt_id": prompt_id, "action": action, "id": _response.id})
		if _response.answers.size() == _response.options.size():
			_resolve()
		return true
	if action in ["discard", "ready", "concealed_kong", "add_kong"]:
		if not options[action + "_ids"].has(tile_id):
			return false
	elif tile_id != -1 and tile_id != players[seat].draw_id:
		return false
	match action:
		"self_win":
			_finish([seat], -1, players[seat].draw_id, true, false)
		"pass":
			players[seat].pass_win = true
			events.append({"type": "pass_self_win", "seat": seat, "prompt_id": prompt_id})
			_discard(seat, players[seat].draw_id, false)
		"discard", "ready":
			for id in options.concealed_kong_ids:
				players[seat].dark_locked.append(wall.value(id))
			_discard(seat, tile_id, action == "ready")
		"concealed_kong":
			_meld(seat, -1, tile_id, "concealed")
		"add_kong":
			_open_responses(seat, tile_id, true)
	return true

func _discard(seat: int, id: int, announce: bool) -> void:
	var p: Dictionary = players[seat]
	p.hand.erase(id)
	p.draw_id = -1
	p.discards.append(id)
	p.discard_count += 1
	p.forbidden = ""
	p.pass_pong.clear()
	if not p.ready:
		p.pass_win = false
	if announce:
		p.ready = true
		p.ready_ids = p.hand.duplicate()
	var value: String = wall.value(id)
	if Tiles.is_chicken(value) and not round_meta.charge_chickens.has(value):
		round_meta.charge_chickens[value] = {"owner": seat, "location": "discard", "discard_id": id}
	last_discard = {"seat": seat, "tile": value, "tile_id": id, "after_kong": _draw_kind != "none", "kong_kind": _draw_kind}
	_announce(seat, wall.value(id))
	if announce:
		_announce(seat, "ready")
	events.append({"type": "discard", "seat": seat, "id": id, "ready": announce, "kong_kind": _draw_kind})
	for meld in p.melds:
		if meld.concealed and p.discard_count == meld.formed_at + 2:
			events.append({"type": "reveal", "seat": seat, "ids": meld.tile_ids.duplicate()})
	_draw_kind = "none"
	_open_responses(seat, id, false)

func _open_responses(source: int, id: int, rob: bool) -> void:
	_enter("response")
	_response = {"source": source, "id": id, "rob": rob, "options": {}, "answers": {}}
	if rob:
		_announce(source, "kong")
		events.append({"type": "offer_add_kong", "seat": source, "id": id})
	var value: String = wall.value(id)
	for seat in 4:
		if seat == source:
			continue
		var p: Dictionary = players[seat]
		var actions := []
		var hand := _values(p.hand)
		if not p.pass_win and _win_on(p, hand, source, value, rob):
			actions.append("win")
		if not rob and not p.ready:
			var copies := hand.count(value)
			if copies >= 2 and not p.pass_pong.has(value):
				actions.append("pong")
			if copies == 3 and wall.remaining > 0:
				actions.append("kong")
		if not actions.is_empty():
			actions.append("pass")
			_response.options[seat] = actions
	if _response.options.is_empty():
		_resolve()

func _win_on(p: Dictionary, hand: Array, source: int, value: String, rob: bool) -> bool:
	if not Rules.can_win_on(hand, p.melds, value):
		return false
	if rob or p.ready or players[source].ready or KongRules.is_post_kong_discard(last_discard) or KongRules.has_self_kong(p.melds):
		return true
	var pattern: Dictionary = Rules.analyze(hand + [value], p.melds, value)
	return pattern.all_triplets or pattern.seven_pairs or pattern.flush or Rules.special_pattern_key(pattern) != ""

## 由外层权威时钟触发。一个窗口中已提交的决定保持不变。
func expire_responses(expected_prompt: int) -> bool:
	if expected_prompt != prompt_id:
		return false
	if phase == "turn" and players[turn].ready:
		return submit(turn, expected_prompt, "pass")
	if phase != "response":
		return false
	for seat in _response.options:
		if not _response.answers.has(seat):
			_response.answers[seat] = "pass"
			events.append({"type": "response_timeout", "seat": seat, "id": _response.id, "prompt_id": prompt_id})
	_resolve()
	return true

func _resolve() -> void:
	var window := _response
	_response = {}
	var source: int = window.source
	var id: int = window.id
	var value: String = wall.value(id)
	var winners := []
	var claimant := -1
	var claim := ""
	var seat := source
	for _other in 3:
		seat = Seats.next(seat)
		if not window.answers.has(seat):
			continue
		var action: String = window.answers[seat]
		var allowed: Array = window.options[seat]
		if action == "win":
			winners.append(seat)
		else:
			if allowed.has("win"):
				players[seat].pass_win = true
			if action == "pass" and allowed.has("pong"):
				players[seat].pass_pong.append(value)
			if action in ["pong", "kong"]:
				# 同种只有四张，最多一家持有两张或三张可认领。
				claimant = seat
				claim = action
	if not winners.is_empty():
		if window.rob:
			players[source].hand.erase(id)
			players[source].draw_id = -1
		else:
			_claim_discard(source, id, winners[0], "hand")
		_finish(winners, source, id, false, window.rob)
	elif window.rob:
		_complete_add_kong(source, id)
	elif claimant != -1:
		_meld(claimant, source, id, claim)
	else:
		_draw(Seats.next(source), "none")

func _claim_discard(source: int, id: int, receiver: int, location: String) -> void:
	players[source].discards.erase(id)
	var value: String = wall.value(id)
	if not Tiles.is_chicken(value):
		return
	var first: Dictionary = round_meta.charge_chickens[value]
	if first.discard_id == id:
		first.owner = receiver
		first.location = location
	elif location == "hand":
		round_meta.resolved_chicken_discards.append({"owner": source, "tile": value, "charge": false, "discard_id": id})

func _meld(seat: int, source: int, id: int, action: String) -> void:
	var p: Dictionary = players[seat]
	var value: String = wall.value(id)
	var ids := []
	var need := 4 if action == "concealed" else (2 if action == "pong" else 3)
	for hand_id in p.hand:
		if wall.value(hand_id) == value and ids.size() < need:
			ids.append(hand_id)
	for hand_id in ids:
		p.hand.erase(hand_id)
	if source >= 0:
		_claim_discard(source, id, seat, "meld")
		ids.append(id)
	var meld := {"kind": "pung" if action == "pong" else "kong", "tile": value, "tile_ids": ids,
		"concealed": action == "concealed", "from_seat": source, "source_id": id if source >= 0 else -1,
		"formed_at": p.discard_count}
	p.melds.append(meld)
	_announce(seat, "pong" if action == "pong" else "kong")
	events.append({"type": "meld", "seat": seat, "meld": meld.duplicate(true)})
	p.draw_id = -1
	if action == "pong":
		turn = seat
		_draw_kind = "none"
		p.forbidden = value
		_enter("turn")
	else:
		_draw(seat, "concealed" if action == "concealed" else "exposed")

func _complete_add_kong(seat: int, id: int) -> void:
	var p: Dictionary = players[seat]
	for meld in p.melds:
		if meld.kind == "pung" and meld.tile == wall.value(id):
			meld.kind = "add_kong"
			meld.tile_ids.append(id)
			p.hand.erase(id)
			p.draw_id = -1
			events.append({"type": "add_kong", "seat": seat, "id": id})
			_draw(seat, "add_kong")
			return

func _finish(winners: Array, source: int, id: int, self_draw: bool, rob: bool) -> void:
	round_meta.winners = winners.duplicate()
	round_meta.winner = -1 if winners.is_empty() else winners[0]
	round_meta.discard_seat = source
	round_meta.win_tile_id = id
	round_meta.self_draw = self_draw
	round_meta.robbed_kong = rob
	if not winners.is_empty():
		round_meta.win_tile = wall.value(id)
		var flip_id: int = wall.peek_head()
		if flip_id >= 0:
			round_meta.flip_wall_index = flip_id
			round_meta.flip_tile = wall.value(flip_id)
		if self_draw:
			if _draw_kind != "none":
				round_meta.kong_draw_seat = turn
			if _before_draw <= 4:
				round_meta.last_four_self_draw_seat = turn
		elif rob or KongRules.is_post_kong_discard(last_discard):
			round_meta.burn_chicken_seat = source
			round_meta.burn_chicken_reason = "robbed_added_kong" if rob else "after_kong_discard"
	for winner_seat in winners:
		_announce(winner_seat, "zimo" if self_draw else "hu")
	events.append({"type": "finish", "winners": winners.duplicate(), "source": source,
		"id": id, "flip_id": round_meta.flip_wall_index, "rob": rob})
	_enter("settled")

## 仅终局返回供计分用的牌值投影。多人胡在每个赢家的视图引用同一实体。
func settlement_facts() -> Dictionary:
	if phase != "settled":
		return {}
	var rows := []
	for p in players:
		var ids: Array = p.hand.duplicate()
		if not round_meta.self_draw and round_meta.winners.has(p.seat):
			ids.append(round_meta.win_tile_id)
		rows.append({"seat": p.seat, "concealed_ids": ids, "concealed": _values(ids),
			"melds": p.melds.duplicate(true), "discards": _values(p.discards),
			"discard_ids": p.discards.duplicate(), "ready": p.ready})
	return {"players": rows, "round_meta": round_meta.duplicate(true), "last_discard": last_discard.duplicate(true)}

func _faces(ids: Array) -> Array:
	var faces := []
	for id in ids:
		faces.append({"id": id, "value": wall.value(id)})
	return faces

func _public_order(seat: int) -> Array:
	var order := []
	var p: Dictionary = players[seat]
	var meld_index := 0
	for event in events:
		if event.get("seat", -1) != seat:
			continue
		if event.type == "discard" and p.discards.has(event.id) and Tiles.is_chicken(wall.value(event.id)):
			order.append("c" + str(event.id))
		elif event.type == "meld":
			order.append("m" + str(meld_index))
			meld_index += 1
	return order

func _announce(seat: int, clip: String) -> void:
	_last_audio_id += 1
	_audio_events.append({"id": _last_audio_id, "seat": seat, "clip": clip})
	if _audio_events.size() > 12:
		_audio_events.pop_front()

func snapshot_for(seat: int) -> Dictionary:
	if phase == "idle" or seat not in range(4):
		return {}
	var rows := []
	for p in players:
		var show_hand: bool = p.seat == seat or phase == "settled"
		var melds := []
		for meld in p.melds:
			if show_hand or not meld.concealed or p.discard_count >= meld.formed_at + 2:
				melds.append(meld.duplicate(true))
			else:
				melds.append({"kind": "kong", "concealed": true, "count": 4})
		rows.append({"seat": p.seat, "ready": p.ready, "hand_count": p.hand.size(), "discard_count": p.discard_count,
			"hand": _faces(p.hand) if show_hand else [], "draw_id": p.draw_id if show_hand else -1,
			"has_draw": p.draw_id >= 0, "public_order": _public_order(p.seat),
			"discards": _faces(p.discards), "melds": melds})
	var view := {"viewer_seat": seat, "phase": phase, "turn": turn, "prompt_id": prompt_id, "audio_events": _audio_events.duplicate(true), "players": rows, "choices": choices(seat),
		"wall_remaining": wall.remaining, "wall_slots": wall.occupied_slots(), "last_discard": last_discard.duplicate(true),
		"dealer": round_meta.dealer_seat, "red": round_meta.die, "white": round_meta.die_white,
		"ready_ids": players[seat].ready_ids.duplicate(), "chicken_multiplier": round_meta.chicken_multiplier,
		"charge_chickens": round_meta.charge_chickens.duplicate(true), "draw_kind": _draw_kind if seat == turn else "none"}
	if phase == "response":
		view.response = {"source": _response.source, "tile_id": _response.id, "tile": wall.value(_response.id),
			"rob": _response.rob, "submitted": _response.answers.has(seat)}
	view.self_win_declined = players[seat].get("self_win_declined", false)
	if phase == "settled":
		view.result = round_meta.duplicate(true)
		view.result.flip_landing = wall.flip_landing(round_meta.flip_wall_index)
	return view


## 权威端全量导出/恢复：只经加密备用链路传给下家真人，永不进入玩家视图或日志。
func export_authority() -> Dictionary:
	var state := {"phase": phase, "turn": turn, "prompt_id": prompt_id,
		"last_discard": last_discard.duplicate(true), "round_meta": round_meta.duplicate(true),
		"events": events.duplicate(true), "players": players.duplicate(true),
		"_response": _response.duplicate(true), "_turn_options": _turn_options.duplicate(true),
		"_draw_kind": _draw_kind, "_before_draw": _before_draw,
		"_audio_events": _audio_events.duplicate(true), "_last_audio_id": _last_audio_id}
	if wall != null:
		state.wall = wall.snapshot()
	return state


func restore_authority(state: Dictionary) -> bool:
	if not state.get("players") is Array or state.players.size() != 4:
		return false
	if not state.get("round_meta") is Dictionary or not state.get("wall") is Dictionary:
		return false
	if state.get("turn") is not int or int(state.turn) not in range(4) and int(state.turn) != -1:
		return false
	var restored_wall = Wall.new()
	if not restored_wall.restore(state.wall):
		return false
	var restored_players: Array = state.players.duplicate(true)
	for row in restored_players:
		if not row is Dictionary or row.get("seat") is not int or int(row.seat) not in range(4):
			return false
	wall = restored_wall
	players = restored_players
	phase = str(state.get("phase", "idle"))
	turn = int(state.turn)
	prompt_id = int(state.get("prompt_id", 0))
	last_discard = state.get("last_discard", {}).duplicate(true)
	round_meta = state.round_meta.duplicate(true)
	events = state.get("events", []).duplicate(true)
	_response = state.get("_response", {}).duplicate(true)
	_turn_options = state.get("_turn_options", {}).duplicate(true)
	_draw_kind = str(state.get("_draw_kind", "none"))
	_before_draw = int(state.get("_before_draw", 0))
	_audio_events = state.get("_audio_events", []).duplicate(true)
	_last_audio_id = int(state.get("_last_audio_id", 0))
	return true
