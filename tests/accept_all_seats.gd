extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const Tiles := preload("res://scripts/core/Tiles.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.opening_delay_seconds = 0.0
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
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._deal_animating = false
	table._table_animation_controller._pending_test_deals.clear()
	table._new_areas.test_deal_only = false
	table._new_areas.test_frozen = false
	table._new_areas._sort_started = true
	table._new_areas._frozen_hands.clear()
	table._refresh()
	await create_timer(0.3).timeout
	for seat in [0, 2, 3, 1]:
		table.round.current_turn = seat
		table.round._begin_turn()
		for _i in 60:
			await process_frame
			if table.round.players[seat].just_drew != "": break
		await create_timer(0.6).timeout
		table._refresh()
		await create_timer(0.2).timeout
		var v2 = table._new_areas
		var hand: Array = v2.hand_boxes[seat].get_children()
		var draw: Array = v2.draw_boxes[seat].get_children()
		var axis_x: bool = seat in [1, 3]
		var lo := INF
		var hi := -INF
		for n in hand:
			# TileView.position always stores the unrotated top-left in the V2
			# design canvas; applying its rotated transform here double-counts
			# pivot rotation for side seats.
			var c: Vector2 = n.position + n.size / 2.0
			var v := c.x if axis_x else c.y
			lo = minf(lo, v - n.size.x * 0.5)
			hi = maxf(hi, v + n.size.x * 0.5)
		var center := (lo + hi) * 0.5
		var want: float = G.CENTER.x if axis_x else G.CENTER.y
		var gap := 0.0
		if draw.size() == 1:
			var dn: Control = draw[0]
			var dc: Vector2 = dn.position + dn.size / 2.0
			var dv := dc.x if axis_x else dc.y
			var total_lo := minf(lo, dv - dn.size.x * 0.5)
			var total_hi := maxf(hi, dv + dn.size.x * 0.5)
			gap = (total_hi - total_lo) - (hi - lo) - dn.size.x
		print("[seats] seat=", seat, " hand=", hand.size(), " draw=", draw.size(),
			" center=", center, " want=", want, " gap=", gap)
		t.expect(hand.size() == 13, "座位%d手牌13张" % seat)
		t.expect(draw.size() == 1, "座位%d摸牌1张" % seat)
		t.expect(absf(center - want) < 1.0, "座位%d手牌居中" % seat)
		t.expect(absf(gap - 20.0) < 1.0, "座位%d摸牌间距20" % seat)
	table.queue_free(); await H.quit_cleanly(self, t.finish("accept_all_seats"))
