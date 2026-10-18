extends RefCounted
## Immutable, visibility-safe snapshot of everything AiPlayer needs for one
## decision. It deliberately implements only the RoundState-shaped read methods
## used by the AI; no Node, scene tree, signal or original PlayerState escapes.

const ACTIONS := preload("res://scripts/core/LegalActions.gd")

var players: Array[PlayerState] = []
var round_meta: Dictionary = {}
var last_discard: Dictionary = {}
var seat := 0
var current_turn := 0
var phase := 0
var settled := false
var _kong_draw_turn := false
var wall_remaining := 0
var can_ready := false
var legal_options: Dictionary = {}
var source_seat := -1
var source_tile := ""
var response_options: Dictionary = {}

## Filled by the service when the job is submitted.
var task_id := 0
var session := ""
var prompt_id := 0
var state_revision := 0
var control_revision := 0

static func build(round, seat_value: int) -> RefCounted:
	var context = load("res://scripts/ai/AiTurnContext.gd").new()
	context.seat = seat_value
	context.current_turn = int(round.current_turn)
	context.phase = int(round.phase)
	context.settled = round.phase == round.Phase.SETTLED
	context._kong_draw_turn = bool(round._kong_draw_turn)
	context.wall_remaining = int(round._wall_count())
	context.round_meta = round.round_meta.duplicate(true)
	context.last_discard = round.last_discard.duplicate(true)
	context.legal_options = round.legal_turn_options(seat_value).duplicate(true)
	context.can_ready = bool(round.can_declare_ready(seat_value))
	for index in 4:
		var source: PlayerState = round.players[index]
		var player := PlayerState.new()
		player.seat = source.seat
		player.is_human = source.is_human
		player.is_dealer = source.is_dealer
		player.name_label = source.name_label
		player.melds = source.melds.duplicate(true)
		player.discards = source.discards.duplicate()
		player.discard_history = source.discard_history.duplicate(true)
		player.discard_ids = source.discard_ids.duplicate()
		player.discard_count = source.discard_count
		player.score = source.score
		player.ready = source.ready
		player.announced_ready = source.announced_ready
		player.first_turn_done = source.first_turn_done
		player.charge_chicken = source.charge_chicken
		player.passed_win_until_draw = source.passed_win_until_draw
		player.passed_pong_tiles = source.passed_pong_tiles.duplicate()
		player.forbidden_discard_tile = source.forbidden_discard_tile
		# AI is allowed to see only its own concealed hand. Opponent melds stay
		# present but is_meld_revealed() decides whether their tile value is public.
		if index == seat_value:
			player.concealed = source.concealed.duplicate()
			player.just_drew = source.just_drew
		else:
			player.concealed = []
			player.just_drew = ""
		context.players.append(player)
	return context

func has_charge(tile: String) -> bool:
	return round_meta.get("charge_chickens", {}).has(tile)

func is_charge_discard(seat_value: int, index: int) -> bool:
	if seat_value < 0 or seat_value >= players.size(): return false
	var player: PlayerState = players[seat_value]
	if index < 0 or index >= player.discards.size(): return false
	var tile: String = player.discards[index]
	var charge: Dictionary = round_meta.get("charge_chickens", {}).get(tile, {})
	if charge.get("owner", -1) != seat_value or charge.get("location", "") != "discard":
		return false
	var discard_id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
	return discard_id == charge.get("discard_id", -1)

func is_meld_revealed(seat_value: int, index: int) -> bool:
	if seat_value < 0 or seat_value >= players.size(): return false
	var player: PlayerState = players[seat_value]
	if index < 0 or index >= player.melds.size(): return false
	var meld: Dictionary = player.melds[index]
	if not meld.get("concealed", false) or settled:
		return true
	return player.discard_count >= int(meld.get("after_discard", 0)) + 2

func can_declare_ready(_seat_value: int) -> bool:
	return can_ready

func legal_turn_options(_seat_value: int) -> Dictionary:
	return legal_options

func _wall_count() -> int:
	return wall_remaining
