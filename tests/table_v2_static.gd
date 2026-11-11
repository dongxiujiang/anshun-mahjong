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

	# 四家牌河全部填满。
	for seat in 4:
		var p = host.round.players[seat]
		p.discards = []
		for i in G.river_capacity(G.relative_seat(1, seat)):
			p.discards.append(["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
				"wan7", "wan8", "wan9", "tiao2", "tiao3", "tong2"][i % 12])
		p.discard_ids = range(p.discards.size())
		p.melds = []
	deck.refresh()
	await process_frame
	t.expect(deck.count_kind("ordinary") == 82, "all 82 ordinary river slots are visible")
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
	var sizes_ok := true
	var rects: Array[Rect2] = []
	for child in deck._red_layer.get_children():
		if not (child is TileView): continue
		var meld: bool = int(child.get_meta("meld_index", -1)) >= 0
		var want := G.MELD_SIZE if meld else Vector2(G.RED_WIDTH, G.RED_HEIGHT)
		var rect := _rect(child)
		sizes_ok = sizes_ok and (child.size * child.scale).is_equal_approx(want)
		for other in rects:
			if rect.intersects(other.grow(-0.05)): sizes_ok = false
		rects.append(rect)
	t.expect(sizes_ok, "pooled chicken discards and equal-size melds retain their own size and do not overlap")

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
