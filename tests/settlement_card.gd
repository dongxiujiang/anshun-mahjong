extends SceneTree
## Legacy scoring coverage retained; presentation assertions now target tabletop boards/melds.

const H := preload("res://tests/test_harness.gd")
const WIN := ["tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan3", "wan4", "wan5", "wan9", "wan9"]
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const MELD_WAIT := ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
var t := H.new()
var table

func _initialize() -> void:
	call_deferred("_run")

func fixture() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.players[0].concealed = WIN.duplicate()
	r.players[2].concealed = MELD_WAIT.duplicate()
	r.players[2].melds = [{"kind": "pung", "tile": "tong5", "from_seat": 1}]
	r.round_meta.winner = 0
	r.round_meta.self_draw = true
	return r

func _check_pairs(result: Dictionary) -> void:
	for seat in 4:
		var total := 0.0
		for other in 4:
			t.expect(result.pairwise[seat][other] == -result.pairwise[other][seat], "双方收付必须互为正负")
			total += float(result.pairwise[seat][other])
		t.expect(total == result.deltas[seat], "三家收付合计必须等于实际分数变化")

func _test_kongs() -> void:
	for source_called in [false, true]:
		var r := fixture()
		if source_called:
			r.players[1].concealed = WAIT.duplicate()
		var before := ScoringEngine.settle(r)
		r.players[2].melds[0].kind = "kong"
		var after := ScoringEngine.settle(r)
		_check_pairs(after)
		t.expect(after.deltas[2] == before.deltas[2] + 4, "明杠收4分")
		t.expect(after.deltas[1] == before.deltas[1] - 4, "明杠只由放杠者付4分")
		t.expect(after.deltas[0] == before.deltas[0] and after.deltas[3] == before.deltas[3], "明杠不能向另外两家收基础分")
		t.expect(after.round_points[2] == 0, "定向明杠4分不能混入通用本局分")
		var kong: Dictionary = after.items[2][0]
		t.expect(kong.tiles.size() == 4 and kong.payers == [1], "明杠应显示四张牌和唯一付款人")
	for kind in ["concealed", "add_kong"]:
		var r := fixture()
		var before := ScoringEngine.settle(r)
		r.players[2].melds[0].kind = "add_kong" if kind == "add_kong" else "kong"
		r.players[2].melds[0].concealed = kind == "concealed"
		var after := ScoringEngine.settle(r)
		_check_pairs(after)
		t.expect(after.deltas[2] == before.deltas[2] + 12, "暗杠/加杠每家4分")
		t.expect(after.round_points[2] == 4, "自有杠4分列入本局分一次")
		for payer in [0, 1, 3]:
			t.expect(after.deltas[payer] == before.deltas[payer] - 4, "自有杠每家只收4分一次")
	var r := fixture()
	r.players[2].melds[0].tile = "tiao1"
	var before := ScoringEngine.settle(r)
	r.players[2].melds[0].kind = "kong"
	var after := ScoringEngine.settle(r)
	_check_pairs(after)
	t.expect(after.pairwise[2][1] == 12, "未叫牌的放杠者付4杠分加四张鸡各2分")
	t.expect(after.round_points[2] == 8, "明杠鸡分8列入本局分，定向基础4单列")
	t.expect(after.items[2].size() == 1 and after.items[2][0].chicken_amount == 8, "杠内鸡集中展示，不能在鸡牌区重复列出")
	t.expect(after.pairwise[2][3] == 8, "非放杠的未叫牌者付四张鸡8分，不付定向杠4")
	r.players[1].concealed = WAIT.duplicate()
	r.round_meta.flip_tile = "tiao1"
	after = ScoringEngine.settle(r)
	_check_pairs(after)
	var kong: Dictionary = {}
	for item in after.items[2]:
		if item.get("kind", "") == "kong":
			kong = item
	t.expect(kong.get("chicken_amount", 0) == 16, "杠内金鸡四张各4分")
	t.expect(after.pairwise[2][1] == 20, "叫牌放杠者付金鸡差额16加定向杠4，不能重复计鸡")

func _test_groups() -> void:
	var r := fixture()
	r.players[0].concealed = ["tiao1", "tong8", "tong8", "wan1", "wan2", "wan2", "wan9"]
	r.players[0].discards = ["tiao1", "tong8"]
	var profile := ScoringEngine.chicken_profile(r, 0, "wan1")
	t.expect(profile.items.size() == 2, "不同牌种、来源的同类同分鸡应合并")
	t.expect(profile.items[0].count == 5 and profile.items[0].amount == 10, "五张普通鸡显示全部牌面和合计10分")
	t.expect(profile.items[0].note.contains("打出") and profile.items[0].note.contains("手中"), "来源不能在合并后误标成全是打出")
	t.expect(profile.items[1].tiles.size() == 4 and profile.items[1].amount == 4, "不同牌种的翻鸡应放一组合计4分")
	t.expect(ScoringEngine.group_chicken_items(profile.items) == profile.items, "已合并的牌组不能二次合并时丢牌或改分")
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	profile = ScoringEngine.chicken_profile(r, 0, "tiao1")
	var amounts := {}
	for item in profile.items:
		amounts[item.label] = item.amount
	t.expect(amounts.get("冲锋金鸡", 0) == 8 and amounts.get("金鸡", 0) == 4 and amounts.get("普通鸡", 0) == 6, "8分冲锋金鸡、4分金鸡、2分普通鸡不能混组")
	r.round_meta.flip_tile = "tiao1"
	var result := ScoringEngine.settle(r)
	var sum := 0.0
	for item in result.items[0]:
		sum += maxf(0, float(item.amount))
	t.expect(result.round_points[0] == sum, "本局分应等于自己的得分点，不是净收付")
	# 自摸/牌型/报听这些自己的得分点每项计一次，不把三家付款重复加入本局分。
	r = fixture()
	r.players[0].concealed = ["tiao1", "tiao1", "wan2", "wan2", "wan3", "wan3", "tiao4", "tiao4", "tiao5", "tiao5", "tong6", "tong6", "tong7", "tong7"]
	r.players[0].ready = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.wall._ring[0] = "tiao8"
	r._finish()
	t.expect(r.last_result.round_points[0] == 52, "§十二：小七对24+报听24+手中鸡4=52，每项只记一次")
	var client := RoundState.new()
	client.set_rng_seed(20261018)
	client.apply_sync(r.serialize_for_seat(2))
	t.expect(client.last_result.round_points == r.last_result.round_points and client.last_result.pairwise == r.last_result.pairwise, "联机必须同步本局分和实际三家收付")
	t.expect(client.last_result.items == r.last_result.items, "联机必须同步全部牌面及杠来源")

func _test_chicken_kong_example() -> void:
	for is_draw in [false, true]:
		for source_called in [false, true]:
			for multiplier in [1, 2]:
				var r := RoundState.new()
				r.set_rng_seed(20261018)
				r.build_players(0)
				r.players[0].concealed = MELD_WAIT.duplicate()
				r.players[0].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 1}]
				r.round_meta.winner = -1 if is_draw else 0
				r.round_meta.self_draw = false
				r.round_meta.discard_seat = 1
				r.round_meta.chicken_multiplier = multiplier
				if not is_draw:
					r.players[0].concealed.append("wan9")
				if source_called:
					r.players[1].concealed = WAIT.duplicate()
				var result := ScoringEngine.settle(r)
				_check_pairs(result)
				var chickens: float = 8.0 * multiplier
				var kong_items: Array = result.items[0].filter(func(item): return item.get("kind", "") == "kong")
				if is_draw:
					t.expect(kong_items.size() == 1 and kong_items[0].chicken_amount == chickens, "荒牌杠中鸡按四张每张2分")
				else:
					# 普通弃牌没有17/21基础费；只有暗杠/加杠后的第一张弃牌
					# 才进入杠后放炮窗口。此构造没有该窗口，故不应出现基础费。
					var has_base: bool = result.transfers.any(func(item): return item.get("from", -1) == 1 and item.get("to", -1) == 0 and float(item.get("amount", 0.0)) >= 17.0)
					t.expect(not has_base, "普通点炮不收17/21基础费")
					t.expect(kong_items.size() == 1 and kong_items[0].chicken_amount == chickens, "胡牌局杠中鸡展示为鸡分比较来源，不重复单独收费")

func _reference_transfers() -> Array:
	return [{"from": 3, "to": 0, "amount": 2}, {"from": 2, "to": 0, "amount": 13},
		{"from": 1, "to": 0, "amount": 17}, {"from": 2, "to": 3, "amount": 11},
		{"from": 1, "to": 3, "amount": 15}, {"from": 1, "to": 2, "amount": 8}]

func _test_reference() -> void:
	var pairs := ScoringEngine.pairwise_payments(_reference_transfers())
	for seat in 4:
		var expected: Array = [[2.0, 13.0, 17.0], [-17.0, -15.0, -8.0], [8.0, -13.0, -11.0], [11.0, 15.0, -2.0]][seat]
		t.expect(ScoringEngine.relative_payments(pairs, seat) == expected, "Reference 上/对/下 payments remain unchanged")

func _bind(r: RoundState, human: int) -> void:
	if table.round != null: table.round.cancel_opening()
	table.round = r
	table.human_seat = human
	table._connect_audio_round()
	table._refresh()
	table._settlement_animation_controller.skip()

func _finish(r: RoundState) -> void:
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.wall._ring[0] = "wan8"
	r._finish()

func _check_tabletop(r: RoundState) -> void:
	var c = table._settlement_animation_controller
	t.expect(c.is_completed() and c.boards.size() == 4, "Settlement remains directly on the table")
	for seat in 4:
		t.expect(c.boards[seat].get_child_count() == 3, "Exactly three counterpart rows replace the old details card")
		var expected := ScoringEngine.relative_payments(r.last_result.pairwise, seat)
		for index in 3:
			var label: Label = c.payment_labels[seat][index]
			var signed := "%+.0f" % expected[index] if expected[index] != 0 else "0"
			t.expect(label.text == signed, "Tabletop preserves actual signed payments in player-relative order")
		t.expect(not table.discard_scroll[seat].get_node("Tiles").visible, "Payments replace river contents")

func _test_ui() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var r := fixture()
	_finish(r)
	var before := var_to_bytes([r.serialize(), r.last_result])
	for human in 4:
		_bind(r, human)
		for dimensions in [Vector2i(1440, 1520), Vector2i(1280, 720), Vector2i(1080, 1920), Vector2i(960, 540)]:
			root.size = dimensions
			await process_frame
			await process_frame
			_check_tabletop(r)
			var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
			var occupied: Array[Rect2] = []
			for board in table._settlement_animation_controller.boards.values():
				var rect: Rect2 = board.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, board.size)
				t.expect(viewport.grow(1).encloses(rect), "All four payment boards fit after resizing")
				for previous in occupied: t.expect(not rect.grow(-1).intersects(previous.grow(-1)), "Payment boards do not overlap")
				occupied.append(rect)
	t.expect(var_to_bytes([r.serialize(), r.last_result]) == before, "Rendering and rotation never write the settlement")

func _test_kong_ui() -> void:
	# Preserve the old source-direction/complete-face assertions on actual table melds.
	for human in 4:
		for offset in [1, 2, 3]:
			for kind in ["exposed", "concealed", "add_kong"]:
				var r := fixture()
				for owner in 4:
					r.players[owner].concealed = MELD_WAIT.duplicate()
					r.players[owner].melds = [{"kind": "add_kong" if kind == "add_kong" else "kong",
						"tile": "tong5", "from_seat": posmod(owner + offset, 4), "concealed": kind == "concealed"}]
				r.players[0].concealed.append("wan9")
				_finish(r)
				var before := var_to_bytes([r.serialize(), r.last_result])
				_bind(r, human)
				_check_tabletop(r)
				for owner in 4:
					var tiles: Array = table.meld_box[owner].get_children().filter(func(node): return node is TileView)
					t.expect(tiles.size() == 4, "All four kong faces remain visible on the tabletop")
					var sideways := 0
					var occupied: Array[Rect2] = []
					for tile in tiles:
						t.expect(tile.face_up and tile.tile == "tong5", "Settlement reveals every kong tile")
						var bounds: Rect2 = tile.get_transform() * Rect2(Vector2.ZERO, tile.size)
						for previous in occupied:
							t.expect(not bounds.grow(-0.5).intersects(previous.grow(-0.5)), "All four kong faces fit without overlap on the table")
						occupied.append(bounds)
						if not is_zero_approx(tile.rotation): sideways += 1
						if kind != "exposed": t.expect(is_zero_approx(tile.rotation), "Concealed/added kong keeps all four upright")
					t.expect(sideways == (1 if kind == "exposed" else 0), "Only exposed kong has a source tile sideways")
					if kind == "exposed":
						var expected_index: int = {1: 3, 2: 3, 3: 0}[offset]
						t.expect(not is_zero_approx(tiles[expected_index].rotation), "Exposed kong sideways index follows its owner's source direction")
				t.expect(var_to_bytes([r.serialize(), r.last_result]) == before, "Tabletop kong rendering does not alter payment metadata")

func _test_charge_ui() -> void:
	var r := fixture()
	r.players[0].discards = ["tiao1", "tong8"]
	r.players[0].discard_ids = [0, 1]
	r.players[0].discard_count = 2
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0},
		"tong8": {"owner": 0, "location": "discard", "discard_id": 1}}
	_finish(r)
	_bind(r, 0)
	var chickens: Array = table.chicken_box[0].get_children().filter(func(node): return node is TileView)
	t.expect(chickens.size() == 2, "Both charge chickens remain displayed on table")
	for tile in chickens:
		t.expect(not is_zero_approx(tile.rotation), "Retained charge chickens stay sideways")
	# Claimed charge becomes an ordinary pung, preserving all three physical faces.
	r = fixture()
	r.players[1].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 0}]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 1, "location": "meld", "meld_index": 0}}
	var profile := ScoringEngine.chicken_profile(r, 1, "wan5")
	t.expect(profile.items.size() == 1 and profile.items[0].kind == "chicken" and profile.items[0].label == "普通鸡" and profile.items[0].count == 3, "Claimed charge chicken is scored as three ordinary chickens")
	_finish(r)
	_bind(r, 0)
	var tiles: Array = table.meld_box[1].get_children().filter(func(node): return node is TileView)
	t.expect(tiles.size() == 3 and table.chicken_box[1].get_child_count() == 0, "Claimed chicken is represented once as a pung, never duplicated")
	for tile in tiles:
		t.expect(tile.face_up and tile.tile == "tiao1" and not tile.get_meta("charge_chicken", false), "Claimed chicken loses charge marking on tabletop")

func _run() -> void:
	_test_kongs()
	_test_chicken_kong_example()
	_test_groups()
	_test_reference()
	await _test_ui()
	_test_kong_ui()
	_test_charge_ui()
	table.free()
	await process_frame
	await H.quit_cleanly(self, t.finish("settlement_card"))
