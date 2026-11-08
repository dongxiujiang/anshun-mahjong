extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var host = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(host)
	host.round.controllers = [null, null, null, null]
	host.round.opening_delay_seconds = 0.0
	for _i in 240:
		await process_frame
		var ready_count := 0
		for player in host.round.players:
			if player.concealed.size() >= 13: ready_count += 1
		if ready_count == 4 and host.round.wall != null and host.round.wall.draw_log.size() >= 52:
			break
	var deck = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(deck)
	deck.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	deck.size = G.DESIGN_SIZE
	deck.set_round(host.round, 1)
	await process_frame

	var wall_count: int = deck.count_kind("wall")
	var hand_count: int = deck.count_kind("hand") + deck.count_kind("draw")
	print("[table_v2_static] phase=", host.round.phase, " wall=", wall_count, " hand=", hand_count,
		" ready=", [host.round.players[0].concealed.size(), host.round.players[1].concealed.size(),
			host.round.players[2].concealed.size(), host.round.players[3].concealed.size()],
		" draws=", host.round.wall.draw_log.size() if host.round.wall != null else -1,
		" remaining=", host.round.wall.remaining if host.round.wall != null else -1)
	var expected_wall: int = host.round.wall.remaining if host.round.wall != null else 0
	var expected_hand := 0
	for player in host.round.players:
		expected_hand += player.concealed.size()
	t.expect(wall_count == expected_wall, "静态新牌桌：牌墙数量与规则状态一致")
	t.expect(hand_count == expected_hand, "静态新牌桌：手牌数量与规则状态一致")

	var own_interactive := 0
	for child in deck.hand_boxes[1].get_children() + deck.draw_boxes[1].get_children():
		if child is TileView and bool(child.interactive): own_interactive += 1
	t.expect(own_interactive >= 13, "静态新牌桌：本地手牌可交互")

	var wall_rects: Array[Rect2] = []
	var hand_rects: Array[Rect2] = []
	for child in deck._wall_layer.get_children():
		if child is TileView:
			wall_rects.append(_rect(child))
	for child in deck._hand_layer.get_children():
		if child is TileView:
			hand_rects.append(_rect(child))
	var overlap := false
	for a in wall_rects:
		for b in hand_rects:
			if a.intersects(b): overlap = true
	t.expect(not overlap, "静态新牌桌：牌墙与手牌不重叠")

	# 普通弃牌 24 张上限。
	for seat in 4:
		var p = host.round.players[seat]
		p.discards = []
		for i in 24:
			p.discards.append(["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
				"wan7", "wan8", "wan9", "tiao2", "tiao3", "tong2"][i % 12])
		p.discard_ids = range(24)
		p.melds = []
	deck.refresh()
	await process_frame
	t.expect(deck.count_kind("ordinary") == 96, "静态新牌桌：普通弃牌24张显示")
	t.expect(deck.count_kind("red") == 0, "静态新牌桌：普通弃牌不进入红色区")

	# 红色区几何容量夹具：8 张单张鸡 + 4 个鸡杠 = 24 张（允许重复牌值）。
	for seat in 4:
		var p = host.round.players[seat]
		p.discards = []
		for i in 8:
			p.discards.append("tiao1" if i % 2 == 0 else "tong8")
		p.discard_ids = range(8)
		p.melds = [
			{"kind": "kong", "tile": "tiao1", "robbed": false, "from_seat": seat, "formed_at": 8},
			{"kind": "kong", "tile": "tong8", "robbed": false, "from_seat": seat, "formed_at": 8},
			{"kind": "kong", "tile": "tiao1", "robbed": false, "from_seat": seat, "formed_at": 8},
			{"kind": "kong", "tile": "tong8", "robbed": false, "from_seat": seat, "formed_at": 8},
		]
	# 冲锋鸡来自规则状态中的权威标记，只有全场首张幺鸡命中。
	host.round.round_meta["charge_chickens"] = {
		"tiao1": {"owner": 0, "location": "discard", "discard_id": 0},
	}
	deck.refresh()
	await process_frame
	t.expect(deck.count_kind("red") == 96, "静态新牌桌：红色区24张显示")
	t.expect(deck.count_kind("ordinary") == 0, "静态新牌桌：红色区不含普通弃牌")
	var red_size_ok := true
	for child in deck._red_layer.get_children():
		if not (child is TileView): continue
		if not child.size.is_equal_approx(Vector2(48.0, 64.0)):
			red_size_ok = false
		if not child.scale.is_equal_approx(Vector2(44.0 / 48.0, 56.0 / 64.0)):
			red_size_ok = false
	t.expect(red_size_ok, "对象池复用后红牌保持固定44×56视觉尺寸")

	# 使用实际牌面外边界校验整体居中；横放鸡牌与竖牌宽度不同。
	var red_centers_ok := true
	for seat in 4:
		var rel := G.relative_seat(1, seat)
		var lo := INF
		var hi := -INF
		for child in deck._red_layer.get_children():
			if not (child is TileView) or int(child.get_meta("v2_seat", -1)) != seat: continue
			var bounds: Rect2 = deck._visual_rect(child)
			lo = minf(lo, bounds.position.x if rel in [0, 2] else bounds.position.y)
			hi = maxf(hi, bounds.end.x if rel in [0, 2] else bounds.end.y)
		var target := G.CENTER.x if rel in [0, 2] else G.CENTER.y
		if not is_equal_approx((lo + hi) / 2.0, target): red_centers_ok = false
	t.expect(red_centers_ok, "红色区整体沿牌桌轴居中")

	# 东/西：牌墙外沿 = 红色区最靠近牌墙的边缘 + 10。
	var east_lo := INF
	var west_hi := -INF
	for child in deck._red_layer.get_children():
		if not (child is TileView): continue
		if int(child.get_meta("v2_seat", -1)) == 0:
			east_lo = minf(east_lo, _rect(child).position.x)
		elif int(child.get_meta("v2_seat", -1)) == 2:
			west_hi = maxf(west_hi, _rect(child).end.x)
	t.expect(is_equal_approx(east_lo, G.wall_outer_x(0) + G.SIDE_RED_GAP), "东家牌墙—红区间距8")
	t.expect(is_equal_approx(west_hi, G.wall_outer_x(2) - G.SIDE_RED_GAP), "西家牌墙—红区间距8")
	var east_hi := -INF
	var west_lo := INF
	for child in deck._red_layer.get_children():
		if not (child is TileView): continue
		if int(child.get_meta("v2_seat", -1)) == 0:
			east_hi = maxf(east_hi, _rect(child).end.x)
		elif int(child.get_meta("v2_seat", -1)) == 2:
			west_lo = minf(west_lo, _rect(child).position.x)
	print("[gap8] east lo/hi=", east_lo, "/", east_hi, " width=", east_hi - east_lo,
		" hand=", G.hand13_rect(0, 1).position.x, " wall=", G.wall_outer_x(0),
		" | west=", west_lo, "/", west_hi, " hand=", G.hand13_rect(2, 1).end.x, " wall=", G.wall_outer_x(2))
	t.expect(is_equal_approx(G.hand13_rect(0, 1).position.x - east_hi, G.SIDE_RED_GAP),
		"东家红区—手牌间距8")
	t.expect(is_equal_approx(west_lo - G.hand13_rect(2, 1).end.x, G.SIDE_RED_GAP),
		"西家红区—手牌间距8")

	# 北/南同步 A：牌墙—红8、红—手8。
	var north_lo := INF
	var north_hi := -INF
	var south_lo := INF
	var south_hi := -INF
	for child in deck._red_layer.get_children():
		if not (child is TileView): continue
		var sid := int(child.get_meta("v2_seat", -1))
		var rr := _rect(child)
		if sid == 1:
			south_lo = minf(south_lo, rr.position.y)
			south_hi = maxf(south_hi, rr.end.y)
		elif sid == 3:
			north_lo = minf(north_lo, rr.position.y)
			north_hi = maxf(north_hi, rr.end.y)
	var north_wall_top: float = G.wall_block_center(3, 0, 1).y - 32.0
	var south_wall_bottom: float = G.wall_block_center(1, 0, 1).y + 32.0
	t.expect(is_equal_approx(G.hand13_rect(1, 1).position.y - south_hi, 8.0), "南家红区—手牌间距8")
	t.expect(is_equal_approx(south_lo - south_wall_bottom, 8.0), "南家牌墙—红区间距8")
	t.expect(is_equal_approx(north_lo - G.hand13_rect(3, 1).end.y, 8.0), "北家红区—手牌间距8")
	t.expect(is_equal_approx(north_wall_top - north_hi, 8.0), "北家牌墙—红区间距8")

	# 不同红牌类型的实际间距：普通4、同类型8、不同类型12。
	var south_nodes: Array = []
	for child in deck._red_layer.get_children():
		if child is TileView and int(child.get_meta("v2_seat", -1)) == 1:
			south_nodes.append(child)
	south_nodes.sort_custom(func(a, b): return a.position.x < b.position.x)
	var red_rects: Array[Rect2] = []
	for n in south_nodes: red_rects.append(_rect(n))
	t.expect(is_equal_approx(red_rects[3].position.x - red_rects[2].end.x, 4.0), "普通幺鸡八筒之间间距4")
	t.expect(is_equal_approx(red_rects[8].position.x - red_rects[7].end.x, 12.0), "单张与杠之间间距12")
	t.expect(is_equal_approx(red_rects[12].position.x - red_rects[11].end.x, 8.0), "同类型杠之间间距8")

	# 冲锋标记只读规则权威值，视图不得把每家前两张强行标成冲锋鸡。
	var charge_nodes: Array = []
	for child in deck._red_layer.get_children():
		if child is TileView and bool(child.get_meta("v2_charge", false)):
			charge_nodes.append(child)
	t.expect(charge_nodes.size() == 1, "冲锋鸡只显示规则标记的首张牌")
	t.expect(not charge_nodes.is_empty() and int(charge_nodes[0].get_meta("v2_seat", -1)) == 0,
		"冲锋鸡标记落在权威座位")

	deck.queue_free()
	host.round.controllers = [null, null, null, null]
	root.get_node("AudioManager").stop_effects()
	root.get_node("AudioManager").end_table(host)
	host.queue_free()
	await process_frame
	await create_timer(0.8).timeout
	root.get_node("AudioManager").stop_effects()
	quit(t.finish("table_v2_static"))

func _rect(tile: TileView) -> Rect2:
	var xf := tile.get_global_transform()
	var points := [xf * Vector2.ZERO, xf * Vector2(tile.size.x, 0),
		xf * tile.size, xf * Vector2(0, tile.size.y)]
	return Rect2(points[0], Vector2.ZERO).expand(points[1]).expand(points[2]).expand(points[3])
