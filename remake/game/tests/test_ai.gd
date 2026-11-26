extends SceneTree

const Ai = preload("res://src/ai/AiPlayer.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_difficulty()
	_hidden_wall_and_hands()
	_hidden_concealed_kong()
	_restricted_turn_choice()
	var moves := {}
	_play_round(4, "low", moves)
	_play_round(8, "medium", moves)
	_play_round(12, "high", moves)
	_play_round(5, "low", moves)
	_play_round(9, "low", moves)
	for action in ["discard", "ready", "pong", "kong", "concealed_kong", "add_kong", "pass", "win", "self_win"]:
		check(moves.has(action), "self-play exercised %s" % action)
	print("AI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _round(deck: Array):
	var game := Round.new()
	check(game.start(1, 5, 2, deck), "start a valid deck")
	check(game.begin_dealer_turn(), "dealer receives the first draw")
	return game

func _legal(view: Dictionary, decision: Dictionary) -> bool:
	var legal: Dictionary = view.choices
	if legal.is_empty() or decision.is_empty():
		return legal.is_empty() and decision.is_empty()
	if decision.prompt_id != legal.prompt_id or decision.action not in legal.actions:
		return false
	if view.phase == "response":
		return decision.tile_id == legal.tile_id
	if decision.action in ["self_win", "pass"]:
		return decision.tile_id == -1
	return decision.tile_id in legal[decision.action + "_ids"]

func _difficulty() -> void:
	var game = _round(Catalog.values(3))
	var view: Dictionary = game.snapshot_for(1)
	check(view.choices.actions == ["discard"], "difficulty fixture compares discard evaluation")
	var low := Ai.decide(view, "low")
	var medium := Ai.decide(view, "medium")
	var high := Ai.decide(view, "high")
	check(_legal(view, low) and _legal(view, medium) and _legal(view, high), "each difficulty returns a legal move")
	check(low != medium and medium == high, "production low and medium behave differently while high matches medium")
	for unsupported in ["", "b18", "Medium"]:
		check(Ai.decide(view, unsupported).is_empty(), "unsupported difficulty %s does not select an implicit tier" % unsupported)

func _hidden_wall_and_hands() -> void:
	var deck := Catalog.values(3)
	var original = _round(deck)
	var foreign_id: int = original.players[0].hand[0]
	var wall_id: int = original.wall.occupied_slots().filter(func(id): return deck[id] != deck[foreign_id])[0]
	var held := deck[foreign_id]
	deck[foreign_id] = deck[wall_id]
	deck[wall_id] = held
	var changed = _round(deck)
	check(original.wall.value(foreign_id) != changed.wall.value(foreign_id) and original.wall.value(wall_id) != changed.wall.value(wall_id),
		"fixture changes an opponent tile and an undrawn wall tile")
	var view: Dictionary = original.snapshot_for(1)
	var same_information: Dictionary = changed.snapshot_for(1)
	check(view == same_information, "private changes preserve the entire observing seat's view")
	for level in Ai.DIFFICULTIES:
		check(Ai.decide(view, level) == Ai.decide(same_information, level), "%s cannot distinguish hidden stock or hand changes" % level)
	var without_choices: Dictionary = changed.snapshot_for(0)
	check(Ai.decide(without_choices, "medium").is_empty(), "a seat without a prompt cannot act")

func _hidden_concealed_kong() -> void:
	var pool := Catalog.values(8427)
	for _copy in 4:
		pool.erase("wan9")
	var deck := []
	for id in 108:
		deck.append("wan9" if id in range(10, 14) else pool.pop_back())
	var game = _round(deck)
	var kong: int = game.choices(1).concealed_kong_ids[0]
	check(game.submit(1, game.prompt_id, "concealed_kong", kong), "concealed kong is formed by authority")
	check(game.snapshot_for(1).draw_kind == "concealed" and game.snapshot_for(0).draw_kind == "none",
		"replacement draw kind is given only to its owner")
	var drawn: int = game.players[1].draw_id
	check(game.submit(1, game.prompt_id, "discard", drawn), "discard replacement tile to move to the next turn")
	if game.phase == "response":
		check(game.expire_responses(game.prompt_id), "advance after any claims time out")
	var view: Dictionary = game.snapshot_for(game.turn)
	check(view.players[1].hand.is_empty() and view.players[1].melds == [{"kind": "kong", "concealed": true, "count": 4}],
		"opponent view masks the concealed kong face and IDs")
	var leaked := view.duplicate(true)
	leaked.players[1].hand = game.snapshot_for(1).players[1].hand
	leaked.players[1].melds = game.snapshot_for(1).players[1].melds
	var original := Ai.decide(view, "medium")
	check(_legal(view, original) and original == Ai.decide(leaked, "medium"),
		"the AI projection ignores an opponent's private hand and unrevealed meld face")

func _restricted_turn_choice() -> void:
	var game = _round(Catalog.values(3))
	var view: Dictionary = game.snapshot_for(1)
	var original := Ai.decide(view, "high")
	var only_id: int = view.choices.discard_ids[0]
	check(only_id != original.tile_id, "restricted prompt removes the preferred physical tile")
	view.choices.discard_ids = [only_id]
	var reply := Ai.decide(view, "high")
	check(_legal(view, reply) and reply.tile_id == only_id, "AI only submits an allowed physical ID")
	check(not game.submit(1, reply.prompt_id - 1, reply.action, reply.tile_id), "authority rejects a stale AI result")
	check(game.submit(1, reply.prompt_id, reply.action, reply.tile_id), "authority accepts the matching fresh AI result")

func _play_round(seed_value: int, level: String, moves: Dictionary) -> void:
	var game = _round(Catalog.values(seed_value))
	for _step in 160:
		if game.phase == "settled":
			break
		if game.phase == "ready_draw":
			check(game.finish_draw_animation(game.turn, game.prompt_id), "ready draw animation advances")
			continue
		var prompt: int = game.prompt_id
		for seat in 4:
			var view: Dictionary = game.snapshot_for(seat)
			var reply := Ai.decide(view, level)
			var legal := _legal(view, reply)
			check(legal, "%s returned an invalid choice %s for seat %s" % [level, reply, seat])
			if not legal:
				return
			if reply.is_empty():
				continue
			var accepted: bool = game.submit(seat, reply.prompt_id, reply.action, reply.tile_id)
			check(accepted, "authority accepted %s for seat %s" % [reply.action, seat])
			if not accepted:
				return
			moves[reply.action] = true
			if game.prompt_id != prompt:
				break
	check(game.phase == "settled", "%s self-play settled within 160 prompts" % level)
