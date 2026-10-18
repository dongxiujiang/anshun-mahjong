extends SceneTree

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

func _tile_rect(tile: TileView) -> Rect2:
	return tile.get_global_transform() * Rect2(Vector2.ZERO, tile.size)

func _check_group_geometry(group: Control, scroll: ScrollContainer) -> void:
	var occupied: Array[Rect2] = []
	for child in group.get_children():
		if not child is TileView:
			continue
		var rect := _tile_rect(child)
		t.expect(group.get_global_rect().encloses(rect), "杠牌的完整牌面必须在自己的组内")
		t.expect(scroll.get_global_rect().encloses(rect), "四张杠牌默认完整可见，无需滚动半张牌")
		for previous in occupied:
			t.expect(not rect.grow(-0.5).intersects(previous.grow(-0.5)), "对家横牌在三张竖牌上方，四张牌面不得重叠")
		occupied.append(rect)

func _test_kong_ui() -> void:
	table.human_seat = 0
	table.round.last_result.items = [[], [], [], []]
	for owner in 4:
		for offset in [1, 2, 3]:
			var item := _reference_item("kong", "明杠", ["tong2", "tong2", "tong2", "tong2"], 4)
			item.merge({"kong_kind": RoundState.KongKind.EXPOSED, "from_seat": posmod(owner + offset, 4), "base_amount": 4})
			table.round.last_result.items[owner].append(item)
	for dimensions in [Vector2i(1440, 1520), Vector2i(1280, 720), Vector2i(1080, 1920), Vector2i(960, 540)]:
		root.size = dimensions
		table._show_result()
		await process_frame
		await process_frame
		for owner in 4:
			var scroll: ScrollContainer = table._result_panel.get_node("ResultSeat%d/Details/ScoreGroups" % owner)
			var groups: HFlowContainer = scroll.get_node("Groups")
			for offset in [1, 2, 3]:
				var group: Control = groups.get_child(offset - 1)
				# 三组杠会换行；滚动至该组，逐组检查四张牌完整可见。
				scroll.scroll_vertical = int(group.position.y)
				await process_frame
				_check_group_geometry(group, scroll)
				var tiles: Array = group.get_children().filter(func(child): return child is TileView)
				var horizontal: Rect2 = _tile_rect(tiles[{1: 3, 2: 3, 3: 0}[offset]])
				var upright: Rect2 = _tile_rect(tiles[1])
				if offset == 1:
					t.expect(horizontal.position.x > upright.position.x, "下家明杠最后一张在右侧横放")
				elif offset == 3:
					t.expect(horizontal.end.x < upright.position.x, "上家明杠第一张在左侧横放")
				else:
					t.expect(horizontal.end.y < upright.position.y, "对家明杠横牌位于三张竖牌上方")
					t.expect(is_equal_approx(horizontal.get_center().x, upright.get_center().x), "对家横牌对齐中间竖牌")
	# 留一张实际渲染图：前三行三种来源，最后一行暗杠/加杠四竖。
	root.size = Vector2i(1440, 1520)
	for entry in [[0, 1], [3, 3], [2, 2]]:
		var owner: int = entry[0]
		table.round.last_result.items[owner] = [table.round.last_result.items[owner][entry[1] - 1]]
	table.round.last_result.items[1] = []
	for kind in ["concealed", "add_kong"]:
		var item := _reference_item("kong", "暗杠" if kind == "concealed" else "加杠", ["tiao9", "tiao9", "tiao9", "tiao9"], 4)
		item.merge({"kong_kind": RoundState._kong_kind_from_name(kind), "base_amount": 4, "from_seat": 2})
		table.round.last_result.items[1].append(item)
	table.round.last_result.round_points = [0.0, 8.0, 0.0, 0.0]
	table.round.last_result.status = ["叫牌", "叫牌", "叫牌", "叫牌"]
	var transfers: Array = [{"from": 1, "to": 0, "amount": 4}, {"from": 2, "to": 3, "amount": 4}, {"from": 0, "to": 2, "amount": 4}]
	for payer in [0, 2, 3]:
		transfers.append({"from": payer, "to": 1, "amount": 8})
	table.round.last_result.pairwise = ScoringEngine.pairwise_payments(transfers)
	table._show_result()
	await process_frame
	await process_frame
	var scroll: ScrollContainer = table._result_panel.get_node("ResultSeat1/Details/ScoreGroups")
	for group in scroll.get_node("Groups").get_children():
		_check_group_geometry(group, scroll)
		for tile in group.get_children():
			if tile is TileView:
				t.expect(is_zero_approx(tile.rotation), "自己的暗杠、加杠在结算卡片上四张全部竖放")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		t.expect(root.get_texture().get_image().save_png("res://docs/kong_arrangements.png") == OK, "保存三种明杠与暗杠加杠排列截图")

func _reference_transfers() -> Array:
	# 图中你/上家/对家/下家的六对关系，真实付款范围另用规则测试验证。
	return [{"from": 3, "to": 0, "amount": 2}, {"from": 2, "to": 0, "amount": 13},
		{"from": 1, "to": 0, "amount": 17}, {"from": 2, "to": 3, "amount": 11},
		{"from": 1, "to": 3, "amount": 15}, {"from": 1, "to": 2, "amount": 8}]

func _test_reference() -> void:
	var pairs := ScoringEngine.pairwise_payments(_reference_transfers())
	for seat in 4:
		var expected: Array = [[2.0, 13.0, 17.0], [-17.0, -15.0, -8.0], [8.0, -13.0, -11.0], [11.0, 15.0, -2.0]][seat]
		t.expect(ScoringEngine.relative_payments(pairs, seat) == expected, "各玩家自己的上/对/下家顺序应与参考图一致")

func _reference_item(kind: String, label: String, tiles: Array, amount: float) -> Dictionary:
	return {"kind": kind, "label": label, "tiles": tiles, "amount": amount, "note": ""}

func _show_reference() -> void:
	table.round.phase = RoundState.Phase.SETTLED
	table.round.round_meta.winner = 3
	table.round.round_meta.self_draw = true
	table.round.round_meta.flip_tile = "tiao1"
	var dark := _reference_item("kong", "暗杠", ["tiao9", "tiao9", "tiao9", "tiao9"], 4)
	dark.merge({"kong_kind": RoundState.KongKind.CONCEALED, "base_amount": 4, "owner": 2})
	var exposed := _reference_item("kong", "明杠", ["tong2", "tong2", "tong2", "tong2"], 4)
	exposed.merge({"kong_kind": RoundState.KongKind.EXPOSED, "from_seat": 3, "base_amount": 4, "owner": 2})
	table.round.last_result = {"round_points": [17.0, 0.0, 4.0, 15.0],
		"pairwise": ScoringEngine.pairwise_payments(_reference_transfers()),
		"status": ["叫牌", "未叫牌", "叫牌", "自摸"], "items": [
			[_reference_item("charge", "冲锋鸡", ["tong8"], 4), _reference_item("chicken", "普通鸡", ["tong8"], 2),
			_reference_item("charge", "冲锋金鸡", ["tiao1"], 8), _reference_item("flip", "翻鸡", ["tiao2", "tiao3", "tiao3"], 3)],
			[], [dark, exposed], [_reference_item("bonus", "自摸", [], 4),
			_reference_item("chicken", "普通鸡", ["tong8", "tong8"], 4), _reference_item("chicken", "金鸡", ["tiao1"], 4),
			_reference_item("flip", "翻鸡", ["tiao2", "tiao3", "tiao3"], 3)]]}
	table._show_result()

func _test_ui() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 1520)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	table.round.phase = RoundState.Phase.IDLE
	_show_reference()
	await process_frame
	await process_frame
	var rows: Array = []
	for seat in [0, 3, 2, 1]:
		var row: Control = table._result_panel.get_node("ResultSeat%d" % seat)
		rows.append(row)
		t.expect(row.get_node("RoundPoints").text == "本局%.0f分" % table.round.last_result.round_points[seat], "本局分文字正确")
		var expected := ScoringEngine.relative_payments(table.round.last_result.pairwise, seat)
		for index in 3:
			t.expect(row.get_node("Payment%d" % index).text == "%+.0f" % expected[index], "三家收付按当前玩家视角展示")
		var groups: HFlowContainer = row.get_node("Details/ScoreGroups/Groups")
		for group in groups.get_children():
			var item: Dictionary = group.get_meta("score_item")
			var count := 0
			for child in group.get_children():
				if child is TileView:
					count += 1
					t.expect(child.unit == table.RESULT_TILE_UNIT, "结算牌面统一放大")
			t.expect(count == item.tiles.size(), "每组必须显示全部牌面")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		t.expect(root.get_texture().get_image().save_png("res://docs/settlement_reference.png") == OK, "保存参考结算界面")
	table._toggle_result_panel(false)
	t.expect(table._result_restore.visible and not table._result_panel.visible, "看牌桌可收起结算")
	t.expect(table._result_restore.get_global_rect().position.is_equal_approx(table._result_panel.get_global_rect().position + table._result_toggle_position() * table.surface.scale), "查看结算与看牌桌在同一位置")
	table._toggle_result_panel(true)
	# 最大同分组需要换行/滚动，不能缩小牌面或越过明细区。
	var many: Array = []
	for index in 14:
		many.append("tong8")
	table.round.last_result.items[0].append(_reference_item("chicken", "普通鸡", many, 28))
	table._show_result()
	for dimensions in [Vector2i(1440, 1520), Vector2i(1280, 720), Vector2i(1080, 1920), Vector2i(960, 540)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var panel_rect: Rect2 = table._result_panel.get_global_rect()
		t.expect(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel_rect), "结算卡片在各窗口尺寸内完整显示")
		for seat in 4:
			var row: Control = table._result_panel.get_node("ResultSeat%d" % seat)
			var scroll: ScrollContainer = row.get_node("Details/ScoreGroups")
			t.expect(row.get_global_rect().encloses(scroll.get_global_rect()), "明细区不越过本玩家的行")
		var scroll: ScrollContainer = table._result_panel.get_node("ResultSeat0/Details/ScoreGroups")
		t.expect(scroll.get_v_scroll_bar().max_value > scroll.size.y, "长牌组可滚动，牌面不用缩小")
		for group in scroll.get_node("Groups").get_children():
			t.expect(group.size.x <= 1000, "牌组宽度不溢出")
	root.size = Vector2i(1440, 1520)
	for human in [1, 2, 3]:
		table.human_seat = human
		table._show_result()
		var own: Control = table._result_panel.get_node("ResultSeat%d" % human)
		t.expect(own.position.y == 112 and own.get_node("SeatName").text == "你", "联机换座位后自己的行始终第一行")
	# 来源牌位置覆盖上/对/下家；暗杠和加杠全部竖放。
	for source_offset in [1, 2, 3]:
		for owner in 4:
			var item := {"kind": "kong", "kong_kind": RoundState.KongKind.EXPOSED, "from_seat": posmod(owner + source_offset, 4)}
			t.expect(table._result_sideways_index(item, owner) == {1: 3, 2: 3, 3: 0}[source_offset], "明杠横牌按该玩家自己的方向显示")
	t.expect(table._result_sideways_index({"kind": "kong", "kong_kind": RoundState.KongKind.ADD_KONG}, 0) == -1, "加杠四张竖放")
	t.expect(table._result_sideways_index({"kind": "kong", "kong_kind": RoundState.KongKind.CONCEALED}, 0) == -1, "暗杠没有来源横牌")
	table.human_seat = 0
	table.round.last_result.items[0] = [_reference_item("charge", "冲锋鸡", ["tiao1", "tong8"], 8)]
	table._show_result()
	await process_frame
	await process_frame
	var charge_group: Control = table._result_panel.get_node("ResultSeat0/Details/ScoreGroups/Groups").get_child(0)
	var sideways := 0
	for tile in charge_group.get_children():
		if tile is TileView and not is_zero_approx(tile.rotation):
			sideways += 1
	t.expect(sideways == 2, "两种同分冲锋鸡合并后均横放")
	# 被碰/杠转入的冲锋鸡在结算里显示成普通鸡并竖向按碰摆放，不再横放或标冲锋字样。
	var claimed := fixture()
	claimed.players[1].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 0}]
	claimed.round_meta.charge_chickens = {"tiao1": {"owner": 1, "location": "meld", "meld_index": 0}}
	var claimed_profile := ScoringEngine.chicken_profile(claimed, 1, "wan5")
	t.expect(claimed_profile.items.size() == 1 and claimed_profile.items[0].kind == "chicken" and claimed_profile.items[0].label == "普通鸡" and claimed_profile.items[0].count == 3, "被碰冲锋鸡识别为普通鸡")
	table.round.last_result.items = [[], claimed_profile.items, [], []]
	table._show_result()
	await process_frame
	await process_frame
	var claimed_groups: HFlowContainer = table._result_panel.get_node("ResultSeat1/Details/ScoreGroups/Groups")
	var saw_claimed_chicken := false
	for group in claimed_groups.get_children():
		var item: Dictionary = group.get_meta("score_item")
		if str(item.get("kind", "")) == "chicken" and str(item.get("label", "")) == "普通鸡":
			saw_claimed_chicken = true
			for tile in group.get_children():
				if tile is TileView:
					t.expect(is_zero_approx(tile.rotation), "被碰冲锋鸡在结算中竖向摆放")
	t.expect(saw_claimed_chicken, "被碰冲锋鸡应归入普通鸡组")

func _run() -> void:
	_test_kongs()
	_test_chicken_kong_example()
	_test_groups()
	_test_reference()
	await _test_ui()
	await _test_kong_ui()
	quit(t.finish("settlement_card"))
