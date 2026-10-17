extends SceneTree
## 截图24/20回归、所有座位六对补差、客户端重复同步及实际结算卡。
const H := preload("res://tests/test_harness.gd")
const ORACLE := preload("res://tests/settlement_oracle.gd")
const SCREENSHOT_WIN := ["tong1", "tong1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "wan6", "wan7", "wan8"]
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong4", "tong5", "tong6", "wan9"]
var t := H.new()
var settlements := 0
var kong_settlements := 0

func _initialize() -> void: call_deferred("_run")

func _fixture(winner: int) -> RoundState:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.players[winner].concealed = SCREENSHOT_WIN.duplicate()
	r.players[winner].discards = ["tong8"]
	r.players[winner].discard_ids = [0]
	r.round_meta.merge({"winner": winner, "self_draw": true, "chicken_multiplier": 2,
		"flip_tile": "tong9", "charge_chickens": {"tong8": {"owner": winner, "location": "discard", "discard_id": 0}}}, true)
	return r

func _test_screenshot() -> void:
	for winner in 4:
		var r := _fixture(winner)
		t.expect(RuleEngine.analyze(r.players[winner].concealed, []).win, "截图回归手牌是合法普通胡")
		var result := ScoringEngine.settle(r)
		ORACLE.check(r, result, t, "截图胜者%d" % winner)
		t.expect(result.round_points[winner] == 24, "冲锋金鸡16+翻鸡4+自摸4=24")
		var components := {}
		for item in result.items[winner]: components[item.label] = item.amount
		t.expect(components == {"冲锋金鸡": 16.0, "翻鸡": 4.0, "自摸": 4.0}, "准确复现截图的三项得分")
		for other in 4:
			if other == winner: continue
			t.expect(result.round_points[other] == 0 and result.pairwise[winner][other] == 24, "本局0分向24分玩家支付24，不能漏翻鸡")
			t.expect(result.deltas[other] == -24, "每个付款人实际扣24")
		t.expect(result.deltas[winner] == 72, "胜者三家合计收72")
		# 验证实际入账，而非只验证 settle() 返回的数字。
		r.wall = WallRing.new(TileSetFactory.create_deck())
		r.wall.set_head(0)
		r.wall._ring[0] = "tong9"
		r._finish()
		t.expect(r.players[winner].score == 272, "胜者累计200+72=272")
		for other in 4:
			if other != winner: t.expect(r.players[other].score == 176, "其他累计200-24=176")
		var scores: Array = r.players.map(func(player): return player.score)
		r._finish()
		t.expect(scores == r.players.map(func(player): return player.score), "重复结束不能二次扣费")
		for seat in 4:
			var client := RoundState.new()
			var wire := r.serialize_for_seat(seat)
			client.apply_sync(wire)
			client.apply_sync(wire)
			t.expect(client.last_result.pairwise == r.last_result.pairwise and client.last_result.round_points == r.last_result.round_points, "每个客户端同步完整收付与得分点")
			t.expect(client.players.map(func(player): return player.score) == scores, "重复快照不能重复加减分")

func _test_six_pairs() -> void:
	# 已叫牌者有不同手中鸡、出牌鸡；未叫牌者即使持鸡也按0参与胡牌局。
	# 遍历赢家方位、三个对手叫牌组合、1/2倍、烧鸡与1/9循环翻牌。
	for winner in 4:
		for mask in 8:
			for multiplier in [1, 2]:
				for burn_offset in [-1, 1, 2, 3]:
					for flip in ["tong9", "tiao1", "wan9"]:
						var r := _fixture(winner)
						r.round_meta.chicken_multiplier = multiplier
						r.round_meta.flip_tile = flip
						r.round_meta.burn_chicken_seat = -1 if burn_offset == -1 else posmod(winner + burn_offset, 4)
						for offset in [1, 2, 3]:
							var seat := posmod(winner + offset, 4)
							var player: PlayerState = r.players[seat]
							player.concealed = WAIT.duplicate() if mask & (1 << (offset - 1)) else ["tiao1", "tong8", "wan1"]
							if mask & (1 << (offset - 1)):
								player.concealed[12] = ["tiao1", "tong8", "wan9"][offset - 1]
							player.discards = ["tiao1"] if offset == 1 else (["tiao1", "tong8"] if offset == 2 else [])
							player.discard_ids = [8, 9] if offset == 2 else ([8] if offset == 1 else [])
						var result := ScoringEngine.settle(r)
						ORACLE.check(r, result, t, "six-pairs %d" % settlements)
						settlements += 1
	# 同分应互相抵消，并非分别收取一遍鸡分。
	var equal := _fixture(0)
	for seat in [1, 2]:
		equal.players[seat].concealed = WAIT.duplicate()
		equal.players[seat].concealed[12] = "tiao1"
	var scored := ScoringEngine.settle(equal)
	t.expect(scored.round_points[1] == 4 and scored.round_points[2] == 4 and scored.pairwise[1][2] == 0, "相同鸡分四分互相不补")

func _test_uncalled_discard_chicken() -> void:
	# 被胡的弃牌会离开 source.discards；独立核账器和实际结算都必须
	# 保留这张未叫牌出牌鸡，并逐家补给所有叫牌玩家。
	for charge in [false, true]:
		for multiplier in [1, 2]:
			var r := RoundState.new()
			r.build_players(0)
			r.controllers = [null, null, null, null]
			r.phase = RoundState.Phase.PLAYING
			r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
				"discard_seat": 1, "win_tile": "tiao1", "chicken_multiplier": multiplier}, true)
			r.players[0].concealed = SCREENSHOT_WIN.duplicate()
			r.players[2].concealed = WAIT.duplicate()
			r.players[1].discards = ["tiao1"]
			r.players[1].discard_ids = [0]
			if charge:
				r.round_meta.charge_chickens["tiao1"] = {"owner": 1, "location": "discard", "discard_id": 0}
			r._remove_from_discards(1, "tiao1", 0, "hand")
			var expected: float = (4.0 if charge else 2.0) * multiplier
			var result := ScoringEngine.settle(r)
			ORACLE.check(r, result, t, "未叫牌被胡出牌鸡 charge=%s x%d" % [charge, multiplier])
			t.expect(result.discard_points[1] == expected, "被胡幺鸡仍计入未叫牌出牌鸡")
			t.expect(result.pairwise[1][0] == -expected and result.pairwise[1][2] == -expected and result.pairwise[1][3] == 0.0,
				"未叫牌出牌鸡逐家补付且不向未叫牌者补付")

func _test_mutual_kongs() -> void:
	# 同局两家有杠：既要抵消通用鸡分/暗加杠4，也要保留不同的明杠付款人。
	for winner in 4:
		var first := posmod(winner + 1, 4)
		var second := posmod(winner + 2, 4)
		for first_kind in ["exposed", "concealed", "add_kong"]:
			for second_kind in ["exposed", "concealed", "add_kong"]:
				for flip in ["tiao1", "tong9", "tong8"]:
					for multiplier in [1, 2]:
						for burned in [-1, first]:
							var r := _fixture(winner)
							r.players[winner].discards = []
							r.round_meta.charge_chickens = {}
							r.round_meta.merge({"flip_tile": flip, "chicken_multiplier": multiplier, "burn_chicken_seat": burned}, true)
							for entry in [[first, first_kind, "tiao1", posmod(winner + 3, 4)], [second, second_kind, "tong8", first]]:
								var player: PlayerState = r.players[entry[0]]
								player.concealed = WAIT.slice(0, 10)
								player.melds = [{"kind": "add_kong" if entry[1] == "add_kong" else "kong", "tile": entry[2], "from_seat": entry[3], "concealed": entry[1] == "concealed"}]
							var result := ScoringEngine.settle(r)
							ORACLE.check(r, result, t, "互有杠%d" % kong_settlements)
							kong_settlements += 1

func _test_result_ui() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.size = Vector2i(1280, 720)
	root.add_child(table)
	await process_frame
	table.round.phase = RoundState.Phase.IDLE
	for human in 4:
		var r := _fixture(3)
		r.wall = WallRing.new(TileSetFactory.create_deck())
		r.wall.set_head(0)
		r.wall._ring[0] = "tong9"
		r._finish()
		table.round = r
		table.human_seat = human
		table._show_result()
		await process_frame
		for seat in 4:
			var row: Control = table._result_panel.get_node("ResultSeat%d" % seat)
			t.expect(row.get_node("RoundPoints").text == ("本局24分" if seat == 3 else "本局0分"), "结算卡显示自己的得分点")
			for index in 3:
				var other := posmod(seat + [3, 2, 1][index], 4)
				var text: String = "+24" if seat == 3 else ("-24" if other == 3 else "0")
				t.expect(row.get_node("Payment%d" % index).text == text, "四个视角卡片按本人的上/对/下家显示真实24分补差")
	table.queue_free()
	await process_frame

func _run() -> void:
	_test_screenshot()
	_test_six_pairs()
	_test_uncalled_discard_chicken()
	_test_mutual_kongs()
	await _test_result_ui()
	print("[scoring_pairwise] %d mixed six-pair settlements + screenshot, sync and UI" % settlements)
	print("[scoring_pairwise] %d two-player kong settlements" % kong_settlements)
	quit(t.finish("scoring_pairwise"))
