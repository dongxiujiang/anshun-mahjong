extends SceneTree

const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const MELD_WAIT := ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.phase = RoundState.Phase.PLAYING
	r.awaiting = true
	return r

func settle(r: RoundState) -> Dictionary:
	var result := ScoringEngine.settle(r)
	check(is_zero_approx(result.deltas.reduce(func(a, b): return a + b, 0.0)), "Score transfers must be zero-sum")
	return result

func _run() -> void:
	_test_flip_cycle()
	_test_charges()
	_test_claims()
	_test_claimed_charge_settlement()
	_test_uncalled_discard_chicken_payments()
	_test_uncalled_kong_chicken_payments()
	_test_chicken_values()
	_test_win_payments()
	_test_draw_payments()
	_test_kong_payments()
	_test_multiplier()
	_test_ready_kongs()
	_test_concealed_kong_reveal()
	print("[rules_update] %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_flip_cycle() -> void:
	for suit in ["wan", "tiao", "tong"]:
		for rank in range(1, 10):
			var related := Tiles.flip_related(suit + str(rank))
			var expected := [suit + str(rank), suit + str(9 if rank == 1 else rank - 1), suit + str(1 if rank == 9 else rank + 1)]
			check(related == expected, "Flip cycle %s%d" % [suit, rank])
	check(Tiles.flip_related("").is_empty(), "No tile means no flipped chickens")

func _test_charges() -> void:
	for same_seat in [false, true]:
		var r := fixture()
		r.phase = RoundState.Phase.IDLE
		var second := 0 if same_seat else 2
		r.players[0].concealed = ["wan2", "tiao1", "tiao1"]
		r.players[second].concealed.append("tong8")
		r._discard(0, "wan2")
		r._discard(0, "tiao1")
		r._discard(second, "tong8")
		r._discard(0, "tiao1")
		check(r.round_meta.charge_chickens.size() == 2, "Each chicken kind has one independent first")
		check(r.is_charge_discard(0, 1), "First tiao1 is charge")
		check(r.is_charge_discard(second, 2 if same_seat else 0), "First tong8 is charge")
		check(not r.is_charge_discard(0, r.players[0].discards.size() - 1), "Second tiao1 is ordinary")
		check(r.players[0].charge_chicken and r.players[second].charge_chicken, "Seat badges follow charge ownership")

func _test_claims() -> void:
	for tile in ["tiao1", "tong8"]:
		for action in ["pong", "kong"]:
			var r := fixture()
			r.wall._ring[107] = "wan6"
			r.players[0].concealed = [tile]
			r.players[0].just_drew = tile
			r.players[1].concealed = [tile, tile, "wan6"]
			if action == "kong":
				r.players[1].concealed.append(tile)
			check(r.submit_turn(0, {"discard": tile}), "Source discards chicken")
			check(r.submit_response(1, tile, {"action": action}), "Chicken can be claimed via " + action)
			check(r.players[0].discards.is_empty() and r.players[0].discard_history.is_empty(), "Claim removes both source records")
			check(r.players[0].discard_ids.is_empty() and r.players[0].discard_count == 1, "Claim removes identity but keeps chronological counter")
			check(r.is_charge_meld(1, 0) and not r.players[0].charge_chicken, "Charge belongs to the claiming meld")
			var base := 6.0 if action == "pong" else 8.0
			check(ScoringEngine.chicken_profile(r, 0, "").total == 0.0, "Source chicken is not counted twice")
			check(ScoringEngine.chicken_profile(r, 1, "").total == base, "Claimed charge chicken is worth only two per tile")
			check(ScoringEngine.chicken_profile(r, 1, tile).total == base * 2, "Flip doubles claimed ordinary chicken value")
			if action == "pong":
				r.players[1].concealed.append(tile)
				r.players[1].just_drew = tile
				check(r.submit_turn(1, {"add_kong": [tile]}), "Chicken pung can be upgraded on the drawn fourth tile")
				check(r.players[1].melds[0].kind == "add_kong" and r.is_charge_meld(1, 0), "Added kong keeps charge identity")
				check(ScoringEngine.chicken_profile(r, 1, "").total == 8.0, "Added charge chicken kong is worth two per tile")
			var client := RoundState.new()
			client.apply_sync(r.serialize_for_seat(1))
			check(client.is_charge_meld(1, 0) and client.players[0].discard_count == 1, "Claim and chronology sync to clients")
			r.phase = RoundState.Phase.IDLE
			r.players[2].concealed = [tile]
			r._discard(2, tile)
			check(not r.is_charge_discard(2, 0), "Claimed charge never permits another first of the same kind")
	# A later identical discard may be claimed without moving the earlier charge.
	var r := fixture()
	r.phase = RoundState.Phase.IDLE
	r.players[0].concealed = ["tiao1", "tiao1"]
	r._discard(0, "tiao1")
	r._discard(0, "tiao1")
	r.players[1].melds = [{"kind": "pung", "tile": "tiao1"}]
	r._remove_from_discards(0, "tiao1", 1, "meld", 0)
	check(r.is_charge_discard(0, 0) and not r.is_charge_meld(1, 0), "Ordinary claimed copy does not steal the original charge")
	check(ScoringEngine.chicken_profile(r, 1, "").total == 6.0, "Ordinary pung contains three ordinary chickens")

func _test_chicken_values() -> void:
	for tile in ["tiao1", "tong8"]:
		var r := fixture()
		r.phase = RoundState.Phase.IDLE
		r.players[0].concealed = [tile, tile]
		r._discard(0, tile)
		r._discard(0, tile)
		check(ScoringEngine.chicken_profile(r, 0, "").discarded == 6.0, "Ordinary two plus charge four")
		check(ScoringEngine.chicken_profile(r, 0, tile).discarded == 12.0, "Flipped ordinary four plus charge eight, no extra flip point")
		r.round_meta.chicken_multiplier = 2
		var profile_mult = ScoringEngine.chicken_profile(r, 0, tile)
		check(profile_mult.total == 12.0, "chicken_profile returns base discarded, before multiplier (flipped = 12)")
		# 倍率在settle里应用。玩家0已打出2张鸡（翻牌后各6分，共12），其他玩家无鸡。
		# 流局结算：0得 (12-0)*3*2倍 = 72
		r.round_meta.outcome = "draw_all_called"
		r.round_meta.dealer_seat = 0
		# 让所有玩家都听牌（13张听1张）
		# 玩家0已打出2张鸡，手牌清空。补成听牌：3副+孤张（听对子）
		r.players[0].concealed = ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5"]  # 听wan5（13张）
		for i in range(1, 4):
			r.players[i].concealed = ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5"]  # 听wan5（13张），无鸡
		var s = settle(r)
		check(s.deltas == [0.0, 0.0, 0.0, 0.0], "§二十：四家叫牌流局本局不计分，即使倍率为2")
		check(s.next_chicken_multiplier == 2, "四家叫牌流局下局鸡分仍×2")
		r.round_meta.burn_chicken_seat = 0
		check(ScoringEngine.chicken_profile(r, 0, tile).total == 0.0, "Robbed added kong burns all chicken points")
	var r := fixture()
	r.players[0].concealed = ["tiao9", "tiao1", "tiao2", "tong8"]
	check(ScoringEngine.chicken_profile(r, 0, "tiao1").total == 8.0, "Wrap-nine and two each score one, tiao1 four and tong8 two")
	# 金鸡只由翻牌三张中的幺鸡/八筒触发；翻到普通牌时三张都只是翻鸡+1。
	r.players[0].concealed = ["tiao1", "tong8", "wan1", "wan9", "wan2"]
	var no_gold := ScoringEngine.chicken_profile(r, 0, "wan1")
	check(no_gold.held == 4.0, "幺鸡和八筒不在翻牌三张时各按普通鸡2分")
	check(no_gold.flipped == 3.0, "翻牌三张普通牌各按翻鸡+1")
	var tiao_gold := ScoringEngine.chicken_profile(r, 0, "tiao9")
	check(tiao_gold.held == 6.0, "翻牌三张含幺鸡时幺鸡按金鸡4分、八筒仍按普通鸡2分")
	r.players[0].concealed = ["wan2", "wan2", "wan2", "wan4"]
	var repeated_flip := ScoringEngine.chicken_profile(r, 0, "wan1")
	var repeated_item: Dictionary = {}
	for item in repeated_flip.items:
		if item.get("tile", "") == "wan2":
			repeated_item = item
	check(repeated_item.get("label", "") == "翻鸡" and repeated_item.get("amount", 0.0) == 3.0, "三张相同翻鸡应显示总分3而不是单张1")
	var settled := ScoringEngine.settle(r)
	for seat_items in settled.items:
		for item in seat_items:
			check(item.get("kind", "") != "net", "结算卡片不应显示补付或差额条目")

func _test_claimed_charge_settlement() -> void:
	# 冲锋鸡被碰：三张归碰家，每张2分，不再保留原出牌者4分。
	var pong := fixture()
	pong.players[1].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 0}]
	pong.round_meta.charge_chickens = {"tiao1": {"owner": 1, "location": "meld", "meld_index": 0}}
	var pong_profile := ScoringEngine.chicken_profile(pong, 1, "")
	check(pong_profile.total == 6.0, "被碰冲锋鸡归碰家，每张2分")
	check(pong_profile.items.size() == 1 and pong_profile.items[0].kind == "chicken" and pong_profile.items[0].label == "普通鸡" and pong_profile.items[0].unit_amount == 2.0, "被碰冲锋鸡在结算中显示为普通鸡且每张2分")

	# 冲锋鸡被明杠：四张归杠家，每张2分；原放牌者额外支付固定杠4分。
	var kong := fixture()
	kong.players[0].concealed = MELD_WAIT.duplicate()
	kong.players[0].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 1}]
	kong.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "meld", "meld_index": 0}}
	var kong_result := settle(kong)
	check(kong_result.items[0][0].chicken_amount == 8.0, "被杠冲锋鸡按四张每张2分")
	check(kong_result.pairwise[0][1] == 16.0, "荒牌明杠的放杠者支付基础补付4、明杠4和杠中鸡8")
	check(kong_result.pairwise[0][2] == 12.0 and kong_result.pairwise[0][3] == 12.0, "其他未叫牌者支付基础补付4和杠中鸡8")

func _test_uncalled_discard_chicken_payments() -> void:
	# 胡牌会把最后一张弃牌从 source.discards 移走；该牌仍必须作为
	# 原出牌者的出牌鸡，逐家补给所有叫牌玩家。
	for charge in [false, true]:
		for multiplier in [1, 2]:
			var r := fixture()
			r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
				"discard_seat": 1, "win_tile": "tiao1", "chicken_multiplier": multiplier}, true)
			r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
			r.players[2].concealed = WAIT.duplicate()
			r.players[1].discards = ["tiao1"]
			r.players[1].discard_ids = [0]
			if charge:
				r.round_meta.charge_chickens["tiao1"] = {"owner": 1, "location": "discard", "discard_id": 0}
			r._remove_from_discards(1, "tiao1", 0, "hand")
			var expected: float = (4.0 if charge else 2.0) * multiplier
			check(r.players[1].discards.is_empty(), "被胡弃牌从桌面记录移除")
			check(r.round_meta.resolved_chicken_discards.size() == 1, "被胡幺鸡保留出牌鸡结算记录")
			var result := settle(r)
			check(result.discard_points[1] == expected, "未叫牌被胡幺鸡出牌分为%.0f" % expected)
			check(result.pairwise[1][0] == -expected and result.pairwise[1][2] == -expected,
				"未叫牌出牌鸡逐家补给两位叫牌玩家")
			check(result.pairwise[1][3] == 0.0, "未叫牌之间不比较出牌鸡")
			check(result.transfers.any(func(item): return item.get("from", -1) == 1 and item.get("to", -1) == 0 and item.get("reason", "") == "未叫牌出牌鸡" and float(item.get("amount", 0.0)) == expected),
				"付款流水明确记录给赢家的未叫牌出牌鸡")
			check(result.transfers.any(func(item): return item.get("from", -1) == 1 and item.get("to", -1) == 2 and item.get("reason", "") == "未叫牌出牌鸡" and float(item.get("amount", 0.0)) == expected),
				"付款流水明确记录给其他叫牌家的未叫牌出牌鸡")

func _test_uncalled_kong_chicken_payments() -> void:
	# 未叫牌明杠幺鸡：四张按普通鸡每张2分，杠中鸡8分逐家补给叫牌者。
	# 未叫杠主向每位叫牌者反付基础4分（§十八一6）。
	var draw := fixture()
	draw.players[0].concealed = ["wan2"]
	draw.players[0].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 1, "concealed": false}]
	draw.players[1].concealed = WAIT.duplicate()
	draw.players[2].concealed = WAIT.duplicate()
	var draw_result := settle(draw)
	check(draw_result.pairwise[0][1] == -16.0 and draw_result.pairwise[0][2] == -12.0,
		"未叫牌明杠幺鸡流局：放杠者收基础4+荒牌基础4+杠中鸡8=16，其他叫牌者收12")
	check(draw_result.transfers.any(func(item): return item.get("from", -1) == 0 and item.get("to", -1) == 1 and item.get("reason", "") == "未叫牌杠中鸡" and float(item.get("amount", 0.0)) == 8.0),
		"未叫牌明杠幺鸡向原放杠叫牌者补8分")
	check(draw_result.transfers.any(func(item): return item.get("from", -1) == 0 and item.get("to", -1) == 2 and item.get("reason", "") == "未叫牌杠中鸡" and float(item.get("amount", 0.0)) == 8.0),
		"未叫牌明杠幺鸡向其他叫牌者补8分")
	var no_source_called := fixture()
	no_source_called.players[0].concealed = ["wan2"]
	no_source_called.players[0].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 1, "concealed": false}]
	no_source_called.players[2].concealed = WAIT.duplicate()
	var no_source_result := settle(no_source_called)
	check(no_source_result.pairwise[0][1] == 0.0 and no_source_result.pairwise[0][2] == -12.0,
		"未叫牌明杠：放杠者1也没叫牌，未叫者之间不发生付款；只向叫牌者2补杠中鸡8和荒牌基础4")
	var win := fixture()
	win.round_meta.winner = 2
	win.round_meta.winners = [2]
	win.round_meta.self_draw = true
	win.players[0].concealed = ["wan2"]
	win.players[0].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 1, "concealed": false}]
	win.players[2].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
	var win_result := settle(win)
	check(win_result.transfers.any(func(item): return item.get("from", -1) == 0 and item.get("to", -1) == 2 and item.get("reason", "") == "未叫牌杠中鸡" and float(item.get("amount", 0.0)) == 8.0),
		"胡牌局未叫牌明杠幺鸡仍向叫牌赢家补8分")
	win.round_meta.flip_tile = "wan5"
	var no_gold_result := settle(win)
	check(no_gold_result.transfers.any(func(item): return item.get("from", -1) == 0 and item.get("to", -1) == 2 and item.get("reason", "") == "未叫牌杠中鸡" and float(item.get("amount", 0.0)) == 8.0),
		"翻牌不关联幺鸡时杠中鸡仍为8分")
	win.round_meta.flip_tile = "tiao1"
	var gold_result := settle(win)
	check(gold_result.transfers.any(func(item): return item.get("from", -1) == 0 and item.get("to", -1) == 2 and item.get("reason", "") == "未叫牌杠中鸡" and float(item.get("amount", 0.0)) == 16.0),
		"翻牌关联幺鸡时未叫牌杠中鸡翻倍为16分")

func _test_win_payments() -> void:
	var r := fixture()
	r.round_meta.winner = 0
	r.round_meta.self_draw = true
	r.players[0].concealed = ["tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan3", "wan4", "wan5", "wan9", "wan9"]
	r.players[0].discards = ["tiao1"]
	r.players[1].concealed = WAIT.duplicate()
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	var probe := settle(r)
	check(probe.deltas == [36.0, -12.0, -12.0, -12.0], "Win: called compare full chickens; uncalled pay full chicken; all pay self draw")
	r.round_meta.flip_tile = "tiao2"
	probe = settle(r)
	check(probe.deltas == [58.0, -14.0, -22.0, -22.0], "Win flip doubles retained charge and held chicken; uncalled pays full chicken")
	r.round_meta.chicken_multiplier = 2
	probe = settle(r)
	check(probe.deltas == [116.0, -28.0, -44.0, -44.0], "先单倍结算后整体翻倍，包含自摸")
	r.round_meta.burn_chicken_seat = 1
	probe = settle(r)
	check(probe.deltas == [120.0, -40.0, -40.0, -40.0], "Burned called player has zero chicken points but still pays")

func _test_draw_payments() -> void:
	var r := fixture()
	r.players[0].concealed = WAIT.duplicate()
	r.players[1].concealed = WAIT.duplicate()
	r.players[0].discards = ["tiao1", "tong8"]
	r.players[1].discards = ["tiao1"]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}, "tong8": {"owner": 0, "location": "discard", "discard_id": 1}}
	r.round_meta.flip_tile = "tiao1" # Must be ignored without a winner.
	var result := settle(r)
	check(result.deltas == [24.0, 12.0, -18.0, -18.0], "荒牌未叫者向每位叫牌者补付双方出牌鸡和基础4分")
	check(result.next_chicken_multiplier == 2, "部分叫牌流局补付后，下局鸡分仍然×2")
	check(result.transfers.all(func(t): return t.from in [2, 3] and t.to in [0, 1]), "Draw transfers only cross from uncalled to called")
	check(result.discard_points == [8.0, 2.0, 0.0, 0.0], "No flip during wall exhaustion")
	r.players[0].discards.clear()
	r.players[0].discard_history = ["tiao1", "tong8"]
	var after_history := settle(r)
	check(after_history.deltas == [8.0, 12.0, -10.0, -10.0], "已移除弃牌不再重复计入，但仍补叫牌者保留出牌鸡和基础4分")
	r.players[1].discards = ["tong8"]
	r.players[1].discard_ids = [0]
	r.players[1].concealed = []
	var uncalled_chicken := settle(r)
	check(uncalled_chicken.deltas == [14.0, -6.0, -4.0, -4.0], "未叫牌者支付自己的鸡分、叫牌者鸡分和基础4分")

func _test_kong_payments() -> void:
	for kind in ["concealed", "add_kong", "kong", "pung"]:
		for source_called in [false, true]:
			var r := fixture()
			r.players[0].concealed = MELD_WAIT.duplicate()
			r.players[0].melds = [{"kind": "kong" if kind == "concealed" else kind, "tile": "wan7", "concealed": kind == "concealed", "from_seat": 1}]
			if source_called:
				r.players[1].concealed = WAIT.duplicate()
			var expected := [0.0, 0.0, 0.0, 0.0]
			if kind in ["concealed", "add_kong"]:
				expected = [16.0, 8.0, -12.0, -12.0] if source_called else [24.0, -8.0, -8.0, -8.0]
			elif kind == "kong":
				expected = [8.0, 8.0, -8.0, -8.0] if source_called else [16.0, -8.0, -4.0, -4.0]
			elif kind == "pung":
				expected = [8.0, 8.0, -8.0, -8.0] if source_called else [12.0, -4.0, -4.0, -4.0]
			check(settle(r).deltas == expected, "Draw kong payer selection: %s / source called %s" % [kind, source_called])
			r.round_meta.chicken_multiplier = 4
			check(settle(r).deltas == expected.map(func(v): return v * 2.0), "Chicken multiplier DOES multiply kong fees (capped at 2x)")
			r.players[0].concealed = ["wan2"]
			var uncalled_expected := [0.0, 0.0, 0.0, 0.0]
			if source_called:
				uncalled_expected = [-8.0, 16.0, -4.0, -4.0] if kind in ["concealed", "add_kong", "kong"] else [-4.0, 12.0, -4.0, -4.0]
			elif kind == "kong":
				# 明杠的放杠者1也没叫牌：未叫者之间不发生付款。
				uncalled_expected = [0.0, 0.0, 0.0, 0.0]
			check(settle(r).deltas == uncalled_expected.map(func(v): return v * 2.0), "未叫牌杠主反向支付基础杠分（倍率作用）")
	# Four concealed kongs: per-group fees plus a discarded charge.
	var r := fixture()
	r.players[0].concealed = ["wan9"]
	for tile in ["wan1", "wan3", "tiao1", "tong8"]:
		r.players[0].melds.append({"kind": "kong", "tile": tile, "concealed": true})
	r.players[0].discards = ["tiao1"]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	var four_kong_result := settle(r)
	check(four_kong_result.deltas == [180.0, -60.0, -60.0, -60.0], "四杠叫牌者按牌型分、每组杠基础和杠中鸡收取")

func _test_multiplier() -> void:
	var r := fixture()
	for multiplier in [1, 2, 2]:
		r.round_meta.chicken_multiplier = multiplier
		r.phase = RoundState.Phase.PLAYING
		for player in r.players:
			player.concealed = WAIT.duplicate()
		r._penzu()
		check(r.last_result.deltas == [0.0, 0.0, 0.0, 0.0] and r.round_meta.flip_tile == "", "All-called draw pays nothing and flips nothing")
		check(r.next_chicken_multiplier == 2, "Repeated all-called draws retain only a two-times multiplier")
		var client := RoundState.new()
		client.apply_sync(r.serialize_for_seat(1))
		check(client.next_chicken_multiplier == 2, "Capped next multiplier syncs")
		r.start_round(0, 1)
		check(r.round_meta.chicken_multiplier == 2 and r.next_chicken_multiplier == 1, "Next round consumes the capped multiplier exactly once")
	# A settled win or mixed draw resets the pending multiplier.
	for player in r.players:
		player.concealed.clear()
	r.players[0].concealed = WAIT.duplicate()
	r.players[0].discards = ["tiao1"]
	r.players[0].discard_ids = [0]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	r.round_meta.chicken_multiplier = 2
	r._penzu()
	check(r.last_result.deltas == [48.0, -16.0, -16.0, -16.0], "荒牌(出牌冲锋鸡4+基础4)最后整体乘2")
	check(r.next_chicken_multiplier == 2, "Mixed draw still doubles next round after uncalled payments")
	check(r.last_result.next_chicken_multiplier == 2, "Mixed draw result carries multiplier 2")
	r.round_meta.winner = 0
	r.players[0].concealed.append("wan9")
	check(settle(r).next_chicken_multiplier == 1, "A win resets multiplier")
	# The host uses the same next-round entry point.
	var host = load("res://scripts/online/NetGameNode.gd").new()
	root.add_child(host)
	check(host.host(false, true, 7537), "Multiplier test opens a real room")
	host._started = true
	host.round_number = 1
	host.game = r
	r.phase = RoundState.Phase.SETTLED
	r.next_chicken_multiplier = 2
	host.next_round()
	host._process(1.01)
	check(r.round_meta.chicken_multiplier == 2, "Network host next round carries multiplier")
	host.free()
	root.multiplayer.multiplayer_peer = null

func _test_ready_kongs() -> void:
	var r := fixture()
	var player: PlayerState = r.players[0]
	# Two quads + one sequence + pair + junk = 14; replacement tiles keep the junk expendable.
	player.concealed = ["wan7", "wan7", "wan7", "wan7", "tong6", "tong6", "tong6", "tong6", "tiao2", "tiao3", "tiao4", "wan9", "wan9", "tong1"]
	player.just_drew = "tong1"
	# Draw_tail returns the final entries of the 108-tile test wall.
	var deck := TileSetFactory.create_deck()
	deck[107] = "tong2"
	deck[106] = "tong3"
	r.wall = WallRing.new(deck)
	r.wall.set_head(0)
	check(r.submit_turn(0, {"kong_declares": ["wan7"]}), "First-turn concealed kong accepted")
	check(r.can_declare_ready(0), "First concealed kong preserves ready opportunity")
	check(r.submit_turn(0, {"kong_declares": ["tong6"]}), "Second concealed kong accepted")
	check(r.can_declare_ready(0), "Repeated concealed kongs preserve ready opportunity")
	check(r.submit_turn(0, {"discard": "wan9", "ready": true}), "After replacements, discarding pair copy leaves a valid wait")
	check(player.ready and not r.can_declare_ready(0), "Ready locks after first discard")
	for kind in ["pung", "kong", "add_kong"]:
		r = fixture()
		r.players[0].just_drew = "wan9"
		r.players[0].melds = [{"kind": kind, "tile": "wan7", "from_seat": 1}]
		check(not r.can_declare_ready(0), "Prior " + kind + " disqualifies ready")

func _check_kong_visibility(r: RoundState, owner: int, expected: Array) -> void:
	var actor := AiPlayer.new("Reveal test")
	for index in expected.size():
		var tile: String = r.players[owner].melds[index].tile
		check(r.is_meld_revealed(owner, index) == expected[index], "Concealed kong visibility follows its owner's discard count")
		check(r.serialize_for_seat(owner).players[owner].melds[index].tile == tile, "Owner retains its own kong value without changing the display rule")
		for viewer in 4:
			if viewer == owner:
				continue
			var view := r.serialize_for_seat(viewer)
			check(view.players[owner].melds[index].tile == (tile if expected[index] else "hidden0"), "Only revealed kong values are transmitted to opponents")
			var client := RoundState.new()
			client.apply_sync(view)
			check(client.is_meld_revealed(owner, index) == expected[index], "Client derives the same reveal time after joining or refreshing")
			check(int(actor._seen_map(r, viewer).get(tile, 0)) == (4 if expected[index] else 0), "AI counts an opponent's concealed kong only after it is revealed")
		check(int(actor._seen_map(r, owner).get(tile, 0)) == 4, "Owner knows all four of its own kong tiles even before reveal")

func _test_concealed_kong_reveal() -> void:
	for owner in 4:
		var r := fixture()
		r.current_turn = owner
		var player: PlayerState = r.players[owner]
		player.discard_count = 3
		player.concealed = ["wan7", "wan7", "wan7", "wan7", "tong6", "tong6", "tong6", "tong6", "tiao2", "tiao3", "tiao4", "wan9", "wan9", "tong1"]
		player.just_drew = "tong1"
		check(r.submit_turn(owner, {"kong_declares": ["wan7"]}), "Concealed kong is accepted for every seat")
		_check_kong_visibility(r, owner, [false])
		check(r.submit_turn(owner, {"kong_declares": ["tong6"]}), "Consecutive concealed kong is accepted in the same turn")
		_check_kong_visibility(r, owner, [false, false])
		check(not r.submit_turn(owner, {"discard": "invalid"}) and player.discard_count == 3, "Invalid discard cannot advance the reveal time")
		check(r.submit_turn(owner, {"discard": "tong1"}), "Kong replacement turn ends with a legal discard")
		_check_kong_visibility(r, owner, [false, false])
		var other := (owner + 1) % 4
		r.players[other].concealed.append("wan5")
		r._discard(other, "wan5")
		_check_kong_visibility(r, owner, [false, false])
		r.current_turn = owner
		r._begin_turn()
		_check_kong_visibility(r, owner, [false, false])
		check(r.submit_turn(owner, {"discard": player.just_drew}), "Owner completes the following turn's discard")
		_check_kong_visibility(r, owner, [true, true])
		r._remove_from_discards(owner, str(player.discards.back()))
		_check_kong_visibility(r, owner, [true, true])
		# Settlement reveals even a kong whose next discard has not yet occurred.
		player.discard_count = 4
		r.phase = RoundState.Phase.SETTLED
		_check_kong_visibility(r, owner, [true, true])
	# Kongs declared in different turns must reveal independently.
	var r := fixture()
	var player: PlayerState = r.players[0]
	player.concealed = ["wan7", "wan7", "wan7", "wan7", "tong6", "tong6", "tong6", "tiao2", "tiao3", "tiao4", "wan9", "wan9", "wan2", "wan3"]
	player.just_drew = "wan3"
	var deck := TileSetFactory.create_deck()
	deck[0] = "wan1"
	deck[1] = "tong6"
	deck[107] = "tong2"
	r.wall = WallRing.new(deck)
	r.wall.set_head(0)
	check(r.submit_turn(0, {"kong_declares": ["wan7"]}), "First staggered kong is accepted")
	check(r.submit_turn(0, {"discard": "wan2"}), "First staggered kong's replacement discard is accepted")
	r.current_turn = 0
	r._begin_turn()
	check(r.submit_turn(0, {"kong_declares": ["tong6"]}), "Next-turn concealed kong is accepted")
	_check_kong_visibility(r, 0, [false, false])
	check(r.submit_turn(0, {"discard": "wan3"}), "Next-turn discard reveals the older kong only")
	_check_kong_visibility(r, 0, [true, false])
	r.current_turn = 0
	r._begin_turn()
	check(r.submit_turn(0, {"discard": player.just_drew}), "Later discard reveals the newer kong")
	_check_kong_visibility(r, 0, [true, true])
