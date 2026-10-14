extends SceneTree
const H := preload("res://tests/test_harness.gd")
const VALUE := preload("res://scripts/ai/AiValueModel.gd")
var t := H.new()
const NORMAL := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9", "wan9"]
const WAIT := ["wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "tiao5", "tiao6", "tiao7", "tong4", "tong5", "tong6", "tong9"]

func _initialize() -> void: call_deferred("_run")

func _profiles(r: RoundState, flip: String) -> Array:
	var profiles: Array = []
	for seat in range(1, 4):
		var player: PlayerState = r.players[seat]
		var profile := ScoringEngine.chicken_profile(r, seat, flip)
		var draw := ScoringEngine.chicken_profile(r, seat, "")
		var kong_chickens := 0.0
		var draw_kong_chickens := 0.0
		for item in profile.raw_items:
			if item.source == "kong" and Tiles.is_chicken(item.tile): kong_chickens += float(item.amount)
		for item in draw.raw_items:
			if item.source == "kong" and Tiles.is_chicken(item.tile): draw_kong_chickens += float(item.amount)
		profiles.append({"seat": seat, "ready": player.ready, "melds": player.melds,
			"tenpai_probability": 1.0 if RuleEngine.is_tenpai(player.concealed, player.melds) else 0.0,
			"chickens": profile.total, "discarded": profile.discarded, "kong_chickens": kong_chickens,
			"draw_discarded": draw.discarded, "draw_kong_chickens": draw_kong_chickens})
	return profiles

func _fixture(index: int) -> RoundState:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.wall_remain = {0: 20}
	r.players[0].concealed = NORMAL.duplicate()
	if index == 1:
		r.players[0].concealed = ["tiao1", "tiao1", "tong8", "tong8", "wan1", "wan1", "wan3", "wan3", "wan5", "wan5", "tiao4", "tiao4", "tong2", "tong2"]
	elif index == 2:
		r.players[0].concealed = ["wan1", "wan1", "wan1", "wan1", "wan3", "wan3", "tiao4", "tiao4", "tiao6", "tiao6", "tong2", "tong2", "tong8", "tong8"]
	elif index == 3:
		r.players[0].concealed = ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan9", "wan9"]
	elif index >= 4:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9", "wan9"]
		r.players[0].melds = [{"kind": "kong", "tile": "tiao1", "concealed": true}]
		if index == 5:
			r.players[0].concealed = ["wan1", "wan2", "wan3", "tong1", "tong2", "tong3", "wan9", "wan9"]
			r.players[0].melds.append({"kind": "kong", "tile": "tong8", "from_seat": 1})
	r.players[0].discards = ["tiao1", "tong8", "tong8", "tong2"] if index < 4 else ["tong2"]
	r.players[0].discard_ids = [0, 1, 2, 3] if index < 4 else [0]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}, "tong8": {"owner": 0, "location": "discard", "discard_id": 1}} if index < 4 else {}
	for seat in range(1, 4):
		if seat != 2: r.players[seat].concealed = WAIT.duplicate()
		r.players[seat].discards = ["tiao1", "tong8"]
		r.players[seat].discard_ids = [0, 1]
	r.players[3].ready = true
	return r

func _run() -> void:
	var cases := 0
	for index in 6:
		for flip in Tiles.all_values():
			for multiplier in [1, 2]:
				for self_draw in [true, false]:
					for ready in [true, false]:
						var r := _fixture(index)
						r.players[0].ready = ready
						r.round_meta.merge({"winner": 0, "self_draw": self_draw, "discard_seat": 1, "flip_tile": flip, "chicken_multiplier": multiplier}, true)
						var flips := VALUE.flip_distribution({}, flip)
						var actual := ScoringEngine.settle(r)
						var expected := VALUE.win_value(r, 0, r.players[0].concealed, r.players[0].melds, flips, _profiles(r, flip), ready, self_draw, 1)
						t.expect(is_equal_approx(expected, float(actual.deltas[0])), "Exact win payments case %d: expected %s, actual %s" % [cases, expected, actual.deltas[0]])
						var profile := VALUE.profile(r, 0, r.players[0].concealed, r.players[0].melds, flips)
						var original := ScoringEngine.chicken_profile(r, 0, flip)
						t.expect(is_equal_approx(float(profile.total), float(original.total)) and is_equal_approx(float(profile.discarded), float(original.discarded)), "Chicken expectation matches scoring engine")
						cases += 1
	# Actual draw payments, with mixed called / uncalled players and targeted kongs.
	for index in [0, 4, 5]:
		var r := _fixture(index)
		r.round_meta.winner = -1
		r.players[0].concealed.pop_back()
		var values := VALUE.draw_value(r, 0, r.players[0].concealed, r.players[0].melds, _profiles(r, ""))
		t.expect(is_equal_approx(float(values.called), float(ScoringEngine.settle(r).deltas[0])), "Called draw pays only retained discards and kongs")
		r.players[0].concealed = ["wan2"]
		values = VALUE.draw_value(r, 0, r.players[0].concealed, r.players[0].melds, _profiles(r, ""))
		t.expect(is_equal_approx(float(values.uncalled), float(ScoringEngine.settle(r).deltas[0])), "Uncalled draw pays only called opponents")
	var sample := _fixture(0)
	# 胡牌局的条件收益也必须计入完整鸡分，不能继续使用流局补付范围。
	# tiao1翻鸡：本人出牌鸡14+手中二条翻鸡1=15；两名叫牌对手各6，一名未叫牌0。
	var normal_value := VALUE.settlement_value(sample, 0, sample.players[0].concealed, [], {"tiao1": 1.0}, _profiles(sample, "tiao1"))
	t.expect(normal_value.called == 33 and normal_value.uncalled == -12, "胡牌局收益：15-6、15-0、15-6，未叫牌时付两家各6")
	# tiao6翻鸡：本人10；两名叫牌对手各有出牌鸡4+手中翻鸡3=7。
	normal_value = VALUE.settlement_value(sample, 0, sample.players[0].concealed, [], {"tiao6": 1.0}, _profiles(sample, "tiao6"))
	t.expect(normal_value.called == 16 and normal_value.uncalled == -14, "未叫牌风险需包含对手手中翻鸡，不能仅算其打出的鸡")
	var seen := {"wan1": 4, "tong7": 3, "tiao9": 2}
	var distribution := VALUE.flip_distribution(seen)
	var average := VALUE.profile(sample, 0, sample.players[0].concealed, [], distribution)
	var manual := 0.0
	for flip in distribution: manual += distribution[flip] * ScoringEngine.chicken_profile(sample, 0, flip).total
	t.expect(is_equal_approx(float(average.total), manual), "Unknown flip is weighted by unseen copies, including 1/9 wraparound")
	t.expect(distribution.wan1 == 0.0 and is_equal_approx(distribution.tong7 * 2.0, distribution.tiao9), "Known copies are excluded from flip probabilities")
	var bonus := _fixture(0)
	bonus.round_meta.merge({"winner": 0, "self_draw": true, "kong_draw_seat": 0, "last_four_self_draw_seat": 0, "flip_tile": "wan9"}, true)
	bonus.wall_remain = {0: 3}
	t.expect(is_equal_approx(VALUE.win_value(bonus, 0, bonus.players[0].concealed, [], {"wan9": 1.0}, _profiles(bonus, "wan9"), false, true, -1, "", true), float(ScoringEngine.settle(bonus).deltas[0])), "Kong draw and last-four bonuses match actual transfers")
	bonus.round_meta.burn_chicken_seat = 0
	t.expect(float(VALUE.profile(bonus, 0, bonus.players[0].concealed, [], {"wan9": 1.0}).total) == 0.0, "Robbed kong burns all own chicken income")
	t.expect(VALUE.kong_base([{"kind": "kong", "tile": "wan1", "from_seat": 2}], 2) == 4.0 and VALUE.kong_base([{"kind": "kong", "tile": "wan1", "from_seat": 2}], 1) == 0.0, "Exposed kong base targets only its source")
	print("[ai_value] audited %d exact win scenarios" % cases)
	quit(t.finish("ai_value"))
