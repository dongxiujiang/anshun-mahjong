extends SceneTree
## 合法动作序列的全程守恒与隐私检查；不是手机实局或 AI 强度验收。

const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Scoring = preload("res://src/anshun/scoring/ScoringEngine.gd")
var checks := 0
var failures := 0
var actions_seen := {}

func _initialize() -> void:
	for seed_value in range(40, 64):
		_run_round(seed_value)
	print("Sequence actions: ", actions_seen)
	print("RoundSequences: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr(message)

func _run_round(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var deck := Catalog.values(seed_value)
	var r := Round.new()
	check(r.start(seed_value % 4, seed_value % 6 + 1, 3, deck), "start legal sequence")
	_check_state(r, deck)
	check(r.begin_dealer_turn(), "dealer starts after deal completion")
	for step in 400:
		_check_state(r, deck)
		if r.phase == "settled":
			break
		if r.phase == "ready_draw":
			check(r.finish_draw_animation(r.turn, r.prompt_id), "ready automatic draw completion")
			continue
		var available := []
		for seat in 4:
			if not r.choices(seat).is_empty():
				available.append(seat)
		check(not available.is_empty(), "active sequence has a legal actor")
		if available.is_empty():
			break
		var seat: int = available[rng.randi_range(0, available.size() - 1)]
		var option: Dictionary = r.choices(seat)
		var action: String = option.actions[rng.randi_range(0, option.actions.size() - 1)]
		# Exercise available meld/ready branches often, while retaining varied passes.
		for preferred in ["self_win", "win", "add_kong", "concealed_kong", "kong", "pong", "ready"]:
			if option.actions.has(preferred) and rng.randf() < 0.8:
				action = preferred
				break
		var tile_id := -1
		if option.has(action + "_ids"):
			var ids: Array = option[action + "_ids"]
			tile_id = ids[rng.randi_range(0, ids.size() - 1)]
		var prior: Array = r.players.duplicate(true)
		var version: int = r.prompt_id
		check(not r.submit(seat, version - 1, action, tile_id), "stale command rejected in every phase")
		check(r.players == prior and r.prompt_id == version, "rejected command changes no cards or locks")
		check(r.submit(seat, version, action, tile_id), "advertised legal action accepted")
		actions_seen[action] = int(actions_seen.get(action, 0)) + 1
	check(r.phase == "settled", "bounded sequence reaches terminal state")
	if r.phase != "settled":
		return
	var result := Scoring.settle(r.settlement_facts())
	var balance := 0
	for delta in result.deltas:
		check(delta == int(delta), "all scores remain integral")
		balance += int(delta)
	check(balance == 0, "complete ledger conserves score")
	for first in 4:
		var total := 0.0
		for second in 4:
			check(result.pairwise[first][second] == -result.pairwise[second][first], "every pair has opposite net amounts")
			total += result.pairwise[first][second]
		check(total == result.deltas[first], "pairwise totals agree with each player's actual change")
	check(r.round_meta.flip_wall_index == r.wall.peek_head() or r.round_meta.flip_wall_index == -1, "flip references current head without consuming it")
	_check_state(r, deck)

func _check_state(r, deck: Array) -> void:
	var all: Array = r.wall.occupied_slots()
	for p in r.players:
		all.append_array(p.hand)
		all.append_array(p.discards)
		for meld in p.melds:
			all.append_array(meld.tile_ids)
	if r.phase == "settled" and not r.round_meta.self_draw and not r.round_meta.winners.is_empty():
		all.append(r.round_meta.win_tile_id)
	all.sort()
	check(all == range(108), "108 physical IDs owned exactly once after every operation")
	check(r.wall.snapshot().tiles == deck, "initial wall array never reordered")
	for viewer in 4:
		var view: Dictionary = r.snapshot_for(viewer)
		check(view.viewer_seat == viewer and not view.has("events") and not view.has("tiles"), "client gets identified filtered data")
		check(view.players[viewer].hand.map(func(face): return face.id) == r.players[viewer].hand, "own view keeps exact physical IDs")
		check(view.chicken_multiplier == r.round_meta.chicken_multiplier, "public multiplier follows authority")
		if viewer != r.turn:
			check(view.draw_kind == "none", "current draw detail not copied to another player's AI context")
		for seat in 4:
			if seat == viewer or r.phase == "settled":
				continue
			check(view.players[seat].hand.is_empty() and view.players[seat].draw_id == -1, "opponents have no private hand values or IDs")
			for index in r.players[seat].melds.size():
				var meld: Dictionary = r.players[seat].melds[index]
				if meld.concealed and r.players[seat].discard_count < meld.formed_at + 2:
					check(not view.players[seat].melds[index].has("tile") and not view.players[seat].melds[index].has("tile_ids"), "unrevealed dark kong stays private")
