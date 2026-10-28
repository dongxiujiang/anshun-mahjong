extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.players[0].concealed = ["wan1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong1", "tong2", "tong3", "tiao4", "tiao5", "tiao6", "tong9"]
	r.players[0].first_turn_done = true
	var ai := AiPlayer.new()
	var started := Time.get_ticks_msec()
	var choice := ai._pick_discard(r, 0)
	t.expect(r.players[0].concealed.has(choice.tile), "AI chooses legal tile")
	t.expect(choice.tile == "tong9", "Complete blocks survive isolated discard")
	for index in 3:
		r.players[index + 1].concealed = ["wan9", "wan9", "wan9", "wan9"]
	t.expect(ai._pick_discard(r, 0) == choice, "Hidden opponent hands cannot influence AI")
	t.expect(Time.get_ticks_msec() - started < 5000, "Decision regression stays within desktop smoke budget")
	r.players[1].melds = [{"kind": "pung", "tile": "tong3"}, {"kind": "pung", "tile": "tong6"}]
	var suited := ai._danger(r, 0, "tong5")
	var off_suit := ai._danger(r, 0, "tiao5")
	t.expect(suited > off_suit, "Same-suit exposed sets increase flush risk")
	r.players[1].ready = true
	r.players[1].discard_history = ["tong5"]
	t.expect(ai._danger(r, 0, "tong5") > 0.0, "Discard history does not imply absolute safety without furiten")
	r.phase = RoundState.Phase.PLAYING
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.players[1].melds.append({"kind": "kong", "tile": "wan9", "concealed": true, "after_discard": r.players[1].discard_count})
	var seen := ai._seen_map(r, 0)
	var private_choice := ai._pick_discard(r, 0)
	r.players[1].melds[2].tile = "tiao9"
	t.expect(ai._seen_map(r, 0) == seen and ai._pick_discard(r, 0) == private_choice, "Unrevealed kong values cannot affect AI decisions")
	var masked := RoundState.new()
	masked.apply_sync(r.serialize_for_seat(0))
	t.expect(ai._pick_discard(masked, 0) == private_choice, "Host and masked-client observations produce the same choice")
	t.expect(ai._danger(masked, 0, "tong5") == ai._danger(r, 0, "tong5"), "Risk inference uses only public information on both peers")
	r.players[0].concealed = ["wan1", "wan1", "wan2", "wan2", "wan4", "wan4", "tong2", "tong2", "tong5", "tong5", "tiao3", "tiao3", "tiao8"]
	t.expect(not ai._pong_helps(r, 0, "wan1"), "Pong does not destroy six-pair hand")
	_test_public_sampling()
	_test_score_defense()
	_test_dragon_kong()
	quit(t.finish("ai_inference"))

func _test_public_sampling() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.players[0].concealed = ["wan1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong1", "tong2", "tong3", "tiao4", "tiao5", "tiao6", "tong9"]
	r.players[1].ready = true
	r.players[1].melds = [{"kind": "pung", "tile": "tong6"}, {"kind": "pung", "tile": "tong3"}]
	r.players[2].melds = [{"kind": "kong", "tile": "wan9", "concealed": true, "after_discard": 8}]
	r.players[2].discard_count = 8
	r.players[2].discard_history = ["tong4", "tong7", "wan8", "tiao9", "tiao2"]
	var ai := AiPlayer.new()
	var seen := ai._seen_map(r, 0)
	var context := ai.opponent_model.observe(r, 0, seen)
	var reordered := {}
	var keys := seen.keys()
	keys.reverse()
	for tile in keys: reordered[tile] = seen[tile]
	var fresh := AiPlayer.new()
	t.expect(fresh.opponent_model.observe(r, 0, reordered) == context, "Public tile counts have canonical sampling order")
	var samples := 0
	for opponent in context.opponents:
		for sample in opponent.sample_hands:
			samples += 1
			t.expect(RuleEngine.is_tenpai(sample.hand, sample.melds), "Sampled opponent hand is legal tenpai")
			var additions := Tiles.to_counts(sample.hand)
			for index in sample.melds.size():
				if not r.is_meld_revealed(int(opponent.seat), index):
					var tile: String = sample.melds[index].tile
					additions[tile] = int(additions.get(tile, 0)) + 4
			var compatible := true
			for tile in additions:
				if int(additions[tile]) + int(seen.get(tile, 0)) > 4: compatible = false
			t.expect(compatible, "Samples respect physical copies, including unknown concealed kongs")
		for tile in Tiles.all_values():
			t.expect(float(opponent.special_waits[tile]) <= float(opponent.waits[tile]) and float(opponent.waits[tile]) >= 0.0 and float(opponent.waits[tile]) <= 1.0, "Restricted ron probability is bounded by all waits")
	t.expect(samples >= 10, "Threatening public observations produce enough legal hypotheses")
	for player in r.players:
		if player.seat != 0: player.concealed = ["tiao1", "tiao1", "tiao1", "tiao1"]
	r.players[2].melds[0].tile = "tiao8"
	r.wall = WallRing.new(TileSetFactory.create_deck())
	t.expect(ai.opponent_model.observe(r, 0, ai._seen_map(r, 0)) == context, "All hidden hands, kong faces and wall order leave the full inference unchanged")
	var regular := ai.opponent_model.risk(context, "tong5", false, false, false, 0)
	var declared := ai.opponent_model.risk(context, "tong5", true, false, false, 0)
	var robbed := ai.opponent_model.risk(context, "tong5", false, false, true, 0)
	t.expect(float(declared.probability) >= float(regular.probability) and float(robbed.probability) >= float(regular.probability), "Ready source and rob-kong exceptions allow normal hands to win")
	# Four copies in our hand cannot eliminate a sequence wait.
	r.players[0].concealed = ["wan5", "wan5", "wan5", "wan5"]
	r.players[1].melds = []
	context = ai.opponent_model.observe(r, 0, ai._seen_map(r, 0))
	t.expect(float(ai.opponent_model.risk(context, "wan5", false, false, false, 0).probability) > 0.0, "Owning all four copies is not absolute safety against sequence waits")
	var blocked: Array[int] = []
	blocked.resize(27)
	blocked.fill(0)
	t.expect(not ai.opponent_model._can_wait(Tiles.value_index("wan5"), blocked, 0), "Physically impossible waits have zero support")
	# The four copies in an opponent's visible kong cannot receive a fifth.
	r.players[1].melds = [{"kind": "kong", "tile": "tong5", "concealed": false}]
	context = ai.opponent_model.observe(r, 0, ai._seen_map(r, 0))
	t.expect(is_zero_approx(float(context.opponents[0].waits.tong5)), "Visible opponent kong excludes impossible fifth-copy wait from the prior")
	var pool: Array[int] = []
	pool.resize(27)
	pool.fill(4)
	var four_melds := [{"kind": "pung", "tile": "wan5"}]
	t.expect(not ai.opponent_model._can_wait(Tiles.value_index("wan5"), pool, 4, four_melds), "Four-meld pair wait cannot reuse an existing pung")
	print("[ai_inference] %d legal opponent hypotheses checked" % samples)

func _test_score_defense() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.wall_remain = {0: 30}
	r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "tong9"]
	r.players[0].first_turn_done = true
	var ai := AiPlayer.new()
	var seen := ai._seen_map(r, 0)
	var context := ai.opponent_model.observe(r, 0, seen).duplicate(true)
	for opponent in context.opponents:
		opponent.tenpai_probability = 1.0
		for tile in Tiles.all_values():
			opponent.waits[tile] = 0.001
			opponent.special_waits[tile] = 0.001
			opponent.costs[tile] = 10.0
			opponent.special_costs[tile] = 10.0
			opponent.uncalled_costs[tile] = 10.0
			opponent.special_uncalled_costs[tile] = 10.0
		opponent.waits.wan9 = 0.45
		opponent.special_waits.wan9 = 0.45
		opponent.costs.wan9 = 160.0
		opponent.special_costs.wan9 = 160.0
	var options := ai._discard_options(r, 0, r.players[0].concealed, [], seen, context)
	t.expect(ai._best_option(options).tile == "tong9", "Expected payment makes AI avoid a costly discard between equivalent waits")
	for option in options:
		t.expect(int(option.distance) == 0, "A live ready route is not broken for speculative income")
	var after: Array = r.players[0].concealed.duplicate()
	after.erase("wan9")
	var dangerous := ai._evaluate_hand(r, 0, after, [], seen, context, "wan9")
	context.opponents[0].special_costs.wan9 = 300.0
	var more_costly := ai._evaluate_hand(r, 0, after, [], seen, context, "wan9")
	t.expect(float(more_costly.merit) < float(dangerous.merit), "Equal danger probabilities react to larger payable scores")
	var ready_risk := ai.opponent_model.risk(context, "wan9", true, false, false, 0)
	var kong_risk := ai.opponent_model.risk(context, "wan9", false, true, false, 0)
	t.expect(float(ready_risk.probability) == float(kong_risk.probability) and float(ready_risk.loss) == float(kong_risk.loss), "§十二：放炮者报听不额外收杀报，通行条件相同则费用相同")

func _test_dragon_kong() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.wall_remain = {0: 40}
	r.players[0].concealed = ["wan1", "wan1", "wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan5", "wan5", "wan6", "wan7"]
	r.players[0].first_turn_done = true
	var ai := AiPlayer.new()
	t.expect(ai._kong_keeps_shape(r.players[0], "wan1", false), "Dragon regression has shape-preserving kong alternative")
	# 新规则：手里四张不再自动等于龙七对（必须胡那张第四张才算），
	# 所以开杠不再必然破坏牌型路线，这里按新规则期望「开杠有利」。
	t.expect(ai._kong_helps(r, 0, "wan1", false), "四张在手不等于龙七对，开杠不再破坏牌型路线")
	var started := Time.get_ticks_usec()
	var decision := ai._pick_discard(r, 0)
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	t.expect(decision.tile in ["wan6", "wan7"], "High-value dragon route keeps six completed pairs")
	print("[ai_inference] warm value decision %.1f ms" % elapsed)
