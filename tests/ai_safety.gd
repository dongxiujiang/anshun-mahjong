extends SceneTree
## AI privacy/legality and risk-model regression. These assertions guard the
## boundaries that can otherwise silently make the AI cheat or stall a seat.
const H := preload("res://tests/test_harness.gd")
const VALUE := preload("res://scripts/ai/AiValueModel.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _fixture() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261023)
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.players[0].concealed = ["wan1", "wan2", "wan3", "wan2", "wan3", "wan4", "tong3", "tong4", "tong5", "tiao3", "tiao4", "tiao5", "wan9", "tiao8"]
	r.players[0].just_drew = "tiao8"
	r.players[0].first_turn_done = true
	return r

func _run() -> void:
	var round := _fixture()
	round.players[0].forbidden_discard_tile = "wan1"
	var ai := AiPlayer.new()
	ai.use_mcts = false
	var decision: Dictionary = ai.decide_turn(round, 0)
	t.expect(str(decision.get("discard", "")) != "wan1", "AI excludes a just-claimed forbidden tile")
	t.expect(round.legal_turn_options(0).discards.has(str(decision.get("discard", ""))), "AI discard is in the legal list")

	# A real opponent profile must expose a normalized probability mass.
	round.players[1].ready = true
	round.players[1].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9"]
	round.players[1].discards = ["tong8"]
	round.players[1].discard_history = ["tong8"]
	round.players[1].discard_ids = [0]
	round.players[1].discard_count = 1
	round.round_meta.chicken_multiplier = 2
	var seen: Dictionary = ai._seen_map(round, 0)
	var context: Dictionary = ai.opponent_model.observe(round, 0, seen)
	var all_normalized := true
	var special_normalized := true
	for opponent in context.opponents:
		var total_waits := 0.0
		var total_special := 0.0
		for tile in Tiles.all_values():
			total_waits += float(opponent.waits.get(tile, 0.0))
			total_special += float(opponent.special_waits.get(tile, 0.0))
		all_normalized = all_normalized and total_waits <= 1.001
		special_normalized = special_normalized and total_special <= 1.001
	t.expect(all_normalized, "each opponent's wait mass is normalized")
	t.expect(special_normalized, "each opponent's special wait mass is normalized")

	# Claiming a chicken is removed from the opponent profile at single-round
	# value; risk() applies the multiplier once.
	var before_context: Dictionary = ai.opponent_model.observe(round, 0, seen)
	var before := float(before_context.opponents[0].discarded)
	var updated: Dictionary = ai._claim_context(round, before_context, 1, "tong8")
	var claimed := before - float(updated.opponents[0].discarded)
	var charge := round.is_charge_discard(1, 0)
	var expected := VALUE.tile_value("tong8", before_context.flips, 1, charge)
	t.expect(is_equal_approx(claimed, expected), "claim adjustment does not pre-apply the round multiplier")

	var teaching := AiTeaching.recommend(round, 0)
	t.expect(not teaching.is_empty() and str(teaching.get("message", "")).begins_with("AI帮打"), "AI teaching returns a bounded recommendation")
	var teaching_tile := str(teaching.get("tile", ""))
	t.expect(teaching_tile == "" or round.legal_turn_options(0).discards.has(teaching_tile), "AI teaching recommends a legal tile")

	t.expect(AiPlayer.new().use_mcts, "normal AI retains MCTS")
	t.expect(not ai.use_mcts, "teaching mode disables MCTS")
	await H.quit_cleanly(self, t.finish("ai_safety"))
