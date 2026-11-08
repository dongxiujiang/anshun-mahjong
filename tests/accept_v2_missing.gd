extends SceneTree
const H := preload("res://tests/test_harness.gd")
const Tiles := preload("res://scripts/core/Tiles.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.cancel_opening()
	table._table_animation_controller.cancel()
	table.round.phase = RoundState.Phase.PLAYING
	table.round.awaiting = false
	var base: Array = Tiles.all_values()
	for seat in 4:
		var p = table.round.players[seat]
		p.concealed.clear()
		p.just_drew = ""
		for i in 13: p.concealed.append(str(base[(seat * 13 + i) % base.size()]))
	# 西家暗杠：别人视角必须反扣；南家自己的暗杠必须正面。
	var p0 = table.round.players[0]
	p0.melds.append({"kind": "kong", "tile": "wan5", "concealed": true, "revealed": false})
	p0.concealed = p0.concealed.slice(0, 9)
	var p1 = table.round.players[1]
	p1.melds.append({"kind": "kong", "tile": "tong5", "concealed": true, "revealed": false})
	p1.concealed = p1.concealed.slice(0, 9)
	p1.ready = true
	# 北家两组碰 + 一组加杠，按总纲验证加杠四张竖放。
	var p3 = table.round.players[3]
	p3.melds.append({"kind": "pung", "tile": "wan2"})
	p3.melds.append({"kind": "pung", "tile": "wan6"})
	p3.melds.append({"kind": "add_kong", "tile": "tong7"})
	p3.concealed = p3.concealed.slice(0, 2)
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._pending_test_deals.clear()
	table._table_animation_controller._deal_animating = false
	table._new_areas.auto_sort_hands = false
	table._new_areas.test_deal_only = false
	table._new_areas.test_frozen = false
	table._new_areas._sort_started = true
	table._new_areas._frozen_hands.clear()
	table._refresh()
	await create_timer(0.25).timeout
	var v2 = table._new_areas
	var hidden := 0
	var own_face := 0
	for node in v2._meld_layer.get_children():
		var seat := int(node.get_meta("v2_seat", -1))
		if seat == 0 and int(node.get_meta("meld_index", -1)) == 0:
			if not node.face_up: hidden += 1
		if seat == 1 and int(node.get_meta("meld_index", -1)) == 0:
			if node.face_up: own_face += 1
	var north_nodes := 0
	var sideways := false
	for node in v2._meld_layer.get_children():
		if int(node.get_meta("v2_seat", -1)) == 3:
			north_nodes += 1
			if int(node.get_meta("meld_sideways", -1)) == 3: sideways = true
	var ready_seen := false
	for label in v2._label_layer.get_children():
		if label is Label and label.text == "听" and label.visible: ready_seen = true
	print("[missing] hidden=", hidden, " own=", own_face, " north=", north_nodes,
		" sideways=", sideways, " ready=", ready_seen)
	t.expect(hidden == 4, "别人暗杠4张全部反扣")
	t.expect(own_face == 4, "自己暗杠4张正面")
	t.expect(north_nodes == 3 + 3 + 4, "多组碰杠全部渲染")
	t.expect(not sideways, "加杠四张竖放")
	t.expect(ready_seen, "报听标记显示")
	# 红色区/普通弃牌上限 + V2 AI教学高亮。
	var p2 = table.round.players[2]
	# 独立测试鸡牌容量，清掉前一阶段的普通暗杠；混合容量由布局守卫覆盖。
	p1.melds.clear()
	for i in 50:
		p2.discards.append("wan2")
		p2.discard_ids.append(i)
	for i in 30:
		p1.discards.append("tiao1")
		p1.discard_ids.append(100 + i)
	p1.concealed[0] = "wan1"
	table._refresh()
	await create_timer(0.2).timeout
	var ordinary_count := 0
	var red_count := 0
	for node in v2._discard_layer.get_children():
		if int(node.get_meta("v2_seat", -1)) == 2: ordinary_count += 1
	for node in v2._red_layer.get_children():
		if int(node.get_meta("v2_seat", -1)) == 1: red_count += 1
	v2.highlight_ai_teach(["wan1"])
	var highlighted := 0
	for node in v2.hand_boxes[1].get_children():
		if node is TileView and node.ai_teach_highlight: highlighted += 1
	print("[missing] ordinary_cap=", ordinary_count, " red_cap=", red_count, " teach=", highlighted)
	var ordinary_cap := 40 if G.relative_seat(1, 2) in [1, 3] else 36
	t.expect(ordinary_count == ordinary_cap, "普通弃牌上限%d" % ordinary_cap)
	t.expect(red_count == 24, "红色区上限24")
	t.expect(highlighted >= 1, "V2 AI教学高亮")
	# 翻鸡沿用原牌墙实体。
	table._table_animation_controller.cancel()
	table.round.phase = RoundState.Phase.SETTLED
	table.round.round_meta.winner = table.human_seat
	table.round.round_meta.winners = [table.human_seat]
	var flip_index: int = table.round.wall.peek_head_index()
	var flip_value: String = table.round.wall.peek_head()
	table.round.round_meta.flip_tile = flip_value
	table.round.round_meta.flip_wall_index = flip_index
	var remaining: int = table.round.wall.remaining
	table._refresh()
	if DisplayServer.get_name() == "headless":
		v2.start_native_settlement(true)
	var settlement_deadline := Time.get_ticks_msec() + 10000
	while v2.native_settlement_active() and Time.get_ticks_msec() < settlement_deadline:
		await process_frame
	var flip: TileView = v2._native_wall_flip_tile()
	t.expect(flip != null and flip.face_up and flip.tile == flip_value and int(flip.get_meta("wall_ring_index")) == flip_index,
		"翻鸡在权威牌头槽位翻开")
	t.expect(table.round.wall.remaining == remaining, "翻鸡不消耗牌墙")
	table.queue_free(); await H.quit_cleanly(self, t.finish("accept_v2_missing"))
