extends SceneTree
## 独立算例核账：期望分值用规则数值和收付款表计算，不调用计分内部函数。
const H := preload("res://tests/test_harness.gd")
const WIN := ["tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan3", "wan4", "wan5", "wan9", "wan9"]
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const MELD_WAIT := ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const NEIGHBORS := {1: [9, 1, 2], 2: [1, 2, 3], 3: [2, 3, 4], 4: [3, 4, 5], 5: [4, 5, 6], 6: [5, 6, 7], 7: [6, 7, 8], 8: [7, 8, 9], 9: [8, 9, 1]}
var t := H.new()
var settlement_count := 0

func _initialize() -> void: call_deferred("_run")

func fixture() -> RoundState:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = "playing"
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.wall._ring[0] = "tiao7"
	return r

func blank_matrix() -> Array:
	return [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]

func check_ledger(r: RoundState, gross: Array, label: String) -> void:
	var result := ScoringEngine.settle(r)
	settlement_count += 1
	var total := 0.0
	for seat in 4:
		var net := 0.0
		for other in 4:
			var expected: float = gross[other][seat] - gross[seat][other]
			t.expect(result.pairwise[seat][other] == expected, "%s: seat %d vs %d expected %s got %s" % [label, seat, other, expected, result.pairwise[seat][other]])
			net += expected
		t.expect(result.deltas[seat] == net, "%s: total change for seat %d" % [label, seat])
		total += float(result.deltas[seat])
	t.expect(total == 0, "%s: four-player scores remain conserved" % label)
	t.expect(ScoringEngine.settle(r) == result, "%s: score calculation itself does not mutate the round" % label)

func _test_all_flip_tiles() -> void:
	# 每种牌分别放在手中，验证27种翻牌、两种鸡、1/9循环、翻倍和烧鸡。
	for suit in ["wan", "tiao", "tong"]:
		for rank in range(1, 10):
			var flipped: String = suit + str(rank)
			for multiplier in [1, 2]:
				for tile_suit in ["wan", "tiao", "tong"]:
					for tile_rank in range(1, 10):
						var tile: String = tile_suit + str(tile_rank)
						var hit: bool = tile_suit == suit and tile_rank in NEIGHBORS[rank]
						var chicken: bool = tile == "tiao1" or tile == "tong8"
						var each: int = ((4 if hit else 2) if chicken else (1 if hit else 0)) * multiplier
						var r := fixture()
						r.round_meta.chicken_multiplier = multiplier
						r.players[0].concealed = [tile, tile]
						var profile := ScoringEngine.chicken_profile(r, 0, flipped)
						t.expect(profile.total == each * 2, "Held %s flip %s x%d" % [tile, flipped, multiplier])
						r.players[0].concealed.clear()
						r.players[0].discards = [tile, tile]
						r.players[0].discard_ids = [7, 11]
						r.round_meta.charge_chickens = {tile: {"owner": 0, "location": "discard", "discard_id": 7}}
						profile = ScoringEngine.chicken_profile(r, 0, flipped)
						t.expect(profile.total == (each * 3 if chicken else 0), "Discard charge + ordinary %s flip %s x%d" % [tile, flipped, multiplier])
						r.round_meta.burn_chicken_seat = 0
						t.expect(ScoringEngine.chicken_profile(r, 0, flipped).total == 0, "Burn cancels chickens including gold and carry")

func _test_call_masks_and_kongs() -> void:
	# 每个查叫组合、三种杠、不同来源以及鸡/金鸡/翻鸡，逐一核对谁给谁钱。
	for kind in ["kong", "concealed", "add_kong"]:
		for source in [1, 2, 3]:
			for scenario in ["ordinary", "chicken", "gold", "flip"]:
				for multiplier in [1, 2]:
					for mask in 16:
						for draw in [true, false]:
							if not draw and not bool(mask & 1): continue
							var r := fixture()
							var tile := "tiao1" if scenario in ["chicken", "gold"] else "tong5"
							for seat in 4:
								if mask & (1 << seat): r.players[seat].concealed = WAIT.duplicate()
							if mask & 1: r.players[0].concealed = MELD_WAIT.duplicate()
							r.players[0].melds = [{"kind": "add_kong" if kind == "add_kong" else "kong", "tile": tile, "from_seat": source, "concealed": kind == "concealed"}]
							r.players[0].discards = ["tong8"]
							r.players[0].discard_ids = [5]
							r.round_meta.charge_chickens = {"tong8": {"owner": 0, "location": "discard", "discard_id": 5}}
							r.round_meta.chicken_multiplier = multiplier
							var flip := "tiao9" if scenario == "gold" else ("tong6" if scenario == "flip" else "")
							r.round_meta.flip_tile = flip
							if not draw:
								r.round_meta.winner = 0
								r.round_meta.self_draw = true
								r.players[0].concealed.append("wan9")
							var gross := blank_matrix()
							var kong_chickens: int = (16 if scenario == "gold" and not draw else 8) * multiplier if tile == "tiao1" else 0
							var kong_flip: int = 4 * multiplier if scenario == "flip" and not draw else 0
							var owner_chickens: int = 4 * multiplier + kong_chickens + kong_flip
							# All ordinary hand fixtures deliberately have no chickens or relevant flip tiles.
							for payer in [1, 2, 3]:
								var payer_called := bool(mask & (1 << payer))
								if mask & 1 and not (draw and payer_called):
									gross[payer][0] += owner_chickens if payer_called else 4 * multiplier + kong_chickens
									if kind != "kong" or payer == source: gross[payer][0] += 4
								if not draw:
									gross[payer][0] += 4 # self draw
									if scenario == "ordinary": gross[payer][0] += 14 # no chicken in hand
							check_ledger(r, gross, "%s %s src%d mask%d draw%s x%d" % [kind, scenario, source, mask, draw, multiplier])

func _test_patterns_and_ready() -> void:
	var cases := [
		[WIN, 0, "普通胡"],
		[["tiao1", "tiao1", "wan2", "wan2", "wan4", "wan4", "wan6", "wan6", "tong2", "tong2", "tong5", "tong5", "tong7", "tong7"], 24, "小七对"],
		[["tiao1", "tiao1", "tiao1", "tiao1", "wan2", "wan2", "wan4", "wan4", "tong2", "tong2", "tong5", "tong5", "tong7", "tong7"], 44, "龙七对"],
		[["tiao1", "tiao1", "tiao1", "wan2", "wan2", "wan2", "tong3", "tong3", "tong3", "tong5", "tong5", "tong5", "wan9", "wan9"], 14, "大队子"],
		[["tiao1", "tiao2", "tiao3", "tiao2", "tiao3", "tiao4", "tiao4", "tiao5", "tiao6", "tiao7", "tiao8", "tiao9", "tiao9", "tiao9"], 24, "清一色"],
		[["tiao1", "tiao1", "tiao2", "tiao2", "tiao3", "tiao3", "tiao4", "tiao4", "tiao5", "tiao5", "tiao6", "tiao6", "tiao9", "tiao9"], 48, "清七对"],
		[["tiao1", "tiao1", "tiao1", "tiao1", "tiao2", "tiao2", "tiao3", "tiao3", "tiao5", "tiao5", "tiao7", "tiao7", "tiao9", "tiao9"], 68, "清龙七对"],
		[["tiao1", "tiao1", "tiao1", "tiao2", "tiao2", "tiao2", "tiao4", "tiao4", "tiao4", "tiao6", "tiao6", "tiao6", "tiao9", "tiao9"], 38, "清大队子"],
	]
	for entry in cases:
		for winner in 4:
			for source in 4: # winner==source means self draw
				for ready_mask in 16:
					var r := fixture()
					for seat in 4:
						r.players[seat].concealed = WAIT.duplicate()
						r.players[seat].ready = bool(ready_mask & (1 << seat))
						r.players[seat].score = [-10, 250, 340, 220][seat]
						r.players[seat].discards = ["tong8"] if seat == winner else []
						r.players[seat].discard_ids = [0] if seat == winner else []
					r.round_meta.winner = winner
					r.round_meta.self_draw = source == winner
					r.round_meta.discard_seat = source if source != winner else -1
					r.players[winner].concealed = entry[0].duplicate()
					var own_chickens := 2 # discarded ordinary tong8
					for tile in entry[0]:
						if tile in ["tiao1", "tong8"]: own_chickens += 2
					var gross := blank_matrix()
					for payer in 4:
						if payer == winner: continue
						gross[payer][winner] = own_chickens
						if source == winner: gross[payer][winner] += 4
						if source == winner or source == payer: gross[payer][winner] += entry[1]
						if r.players[payer].ready or (r.players[winner].ready and (source == winner or source == payer)):
							gross[payer][winner] += 24
					check_ledger(r, gross, "%s winner%d source%d ready%d" % [entry[2], winner, source, ready_mask])

func _test_finish_once_and_sync() -> void:
	var r := fixture()
	r.players[0].concealed = WIN.duplicate()
	r.players[0].discards = ["tiao1"]
	r.players[0].discard_ids = [4]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 4}}
	r.round_meta.winner = 0
	r.round_meta.self_draw = true
	r.apply_scores([-4, 204, 300, 300])
	r._finish()
	t.expect(r.last_result.deltas == [24.0, -8.0, -8.0, -8.0], "Finish applies discarded charge4 + selfdraw4 per uncalled payer")
	t.expect(r.last_result.scores == [20.0, 196.0, 292.0, 292.0], "Actual balances apply one settlement, including negative starting balance")
	var saved := r.last_result.duplicate(true)
	r._finish()
	t.expect(r.last_result == saved and r.players[0].score == 20, "Repeated finish must not charge the same round twice")
	for seat in 4:
		var client := RoundState.new()
		client.apply_sync(r.serialize_for_seat(seat))
		t.expect(client.last_result == r.last_result, "Each network seat receives the same complete settlement")
		t.expect(client.players.map(func(p): return p.score) == r.last_result.scores, "Client balances match settlement card")
		client.apply_sync(r.serialize_for_seat(seat))
		t.expect(client.players.map(func(p): return p.score) == r.last_result.scores, "Repeated snapshot must not add scores again")
	r.set_rng_seed(700)
	r.start_round(0, 1)
	t.expect(r.last_result.is_empty() and r.players[0].score == 20, "New round clears settlement guard and preserves accumulated scores")
	for player in r.players:
		player.concealed.clear()
		player.melds.clear()
		player.discards.clear()
		player.discard_ids.clear()
	r.players[0].concealed = WIN.duplicate()
	r.wall._ring[r.wall._head] = "tiao7"
	r.round_meta.winner = 0
	r.round_meta.self_draw = true
	r._finish()
	t.expect(r.last_result.deltas == [12.0, -4.0, -4.0, -4.0] and r.players[0].score == 32, "Next round is still allowed to settle once")

func _test_bonus_and_burn() -> void:
	for multiplier in [1, 2]:
		for bonuses in 4:
			var r := fixture()
			r.round_meta.winner = 0
			r.round_meta.self_draw = true
			r.round_meta.chicken_multiplier = multiplier
			r.round_meta.kong_draw_seat = 0 if bonuses & 1 else -1
			r.round_meta.last_four_self_draw_seat = 0 if bonuses & 2 else -1
			r.players[0].concealed = WIN.duplicate()
			var gross := blank_matrix()
			var bonus: int = 4 + (9 if bonuses & 1 else 0) + (9 if bonuses & 2 else 0)
			for payer in [1, 2, 3]: gross[payer][0] = bonus
			check_ledger(r, gross, "Selfdraw/kongdraw/lastfour stack; no carry multiplication")
			# 换成不含鸡牌的普通手牌，只有无鸡14增加，仍不受两倍鸡影响。
			r.players[0].concealed = ["tiao2", "tiao3", "tiao4", "wan4", "wan5", "wan6", "tong1", "tong2", "tong3", "wan3", "wan4", "wan5", "wan9", "wan9"]
			for payer in [1, 2, 3]: gross[payer][0] += 14
			check_ledger(r, gross, "No chicken14 stacks with bonuses without carry multiplication")
	# 抢杠后的原碰仍是三张；被抢者鸡分全烧，不能凭未完成的加杠收4分。
	var r := fixture()
	r.current_turn = 0
	r.awaiting = true
	r.players[0].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 2}]
	r.players[0].concealed = MELD_WAIT.duplicate()
	r.players[0].concealed.append("tiao1")
	r.players[0].just_drew = "tiao1"
	r.players[0].discards = ["tong8"]
	r.players[0].discard_ids = [0]
	r.round_meta.charge_chickens = {"tong8": {"owner": 0, "location": "discard", "discard_id": 0}}
	r.players[1].concealed = ["tiao1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong1", "tong2", "tong3", "tong4", "tong5", "tong6"]
	t.expect(r.submit_turn(0, {"add_kong": ["tiao1"]}), "Real turn begins robbable added kong")
	t.expect(r.submit_response(1, "tiao1", {"action": "win"}), "Real response wins by robbing kong")
	t.expect(r.round_meta.burn_chicken_seat == 0 and r.players[0].melds[0].kind == "pung", "Rob keeps original pung and burns source chickens")
	t.expect(r.last_result.deltas == [-4.0, 4.0, 0.0, 0.0], "Rob winner's two chickens4 collected from called source; no kong fee or selfdraw bonus")
	t.expect(r.last_result.items[0].size() == 1 and r.last_result.items[0][0].label == "抢杠烧鸡", "Burned player has no stale chicken or added-kong score items")

func _run() -> void:
	if "--finish-only" in OS.get_cmdline_user_args():
		_test_finish_once_and_sync()
		quit(t.finish("scoring_audit"))
		return
	_test_all_flip_tiles()
	_test_call_masks_and_kongs()
	_test_patterns_and_ready()
	_test_bonus_and_burn()
	_test_finish_once_and_sync()
	print("[scoring_audit] independently calculated settlements: %d" % settlement_count)
	quit(t.finish("scoring_audit"))
