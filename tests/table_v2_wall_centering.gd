extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class OpeningCounter extends RefCounted:
	var shown := 0
	func visual_hold_active() -> bool: return true
	func dice_gate_active() -> bool: return false
	func dealt_count(seat: int) -> int: return shown if seat == 0 else 0

class OpeningHost extends RefCounted:
	var round: RoundState
	var _table_animation_controller := OpeningCounter.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var tiles: Array = []
	for i in 4: tiles.append_array(Tiles.all_values())
	var ring := WallRing.new(tiles)
	if not t.expect(ring.has_method("wall_centering"), "牌墙提供首次过半时的固定视觉基准"):
		await H.quit_cleanly(self, t.finish("table_v2_wall_centering"))
		return
	root.get_node("GameConfig").set_tile_animation_seconds(0.0, false)
	if DisplayServer.get_name() != "headless":
		root.content_scale_size = Vector2i(G.DESIGN_SIZE)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		DirAccess.make_dir_recursive_absolute("res://build/wall-centering")
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.auto_sort_hands = false
	for segment in WallRing.SEG.values():
		var seat := int(segment.seat)
		var r := RoundState.new()
		r.set_rng_seed(7114 + seat)
		r.pause_after_opening = true
		r.start_round(1, 2, 3)
		r.controllers = [null, null, null, null]
		r.wall = WallRing.new(tiles)
		r.wall.set_head(int(segment.start))
		r.round_meta.erase("break") # 单独测试逐张取牌；正式开局的四张批次另测。
		for i in int(segment.len) / 2 - 1: r.wall.draw_head()
		t.expect(not r.wall.wall_centering().has(seat), "不足一半时保持原墙位 seat%d" % seat)
		for viewer in 4:
			view.set_round(r, viewer)
			for node in view._wall_layer.get_children():
				var index := int(node.get_meta("wall_ring_index"))
				t.expect(_original(view, index).is_equal_approx(node.position + node.size / 2), "过半前不提前移动")
		r.wall.draw_head()
		var marker: Dictionary = r.wall.wall_centering()[seat].duplicate(true)
		t.expect(marker.indices.size() == int(segment.len) / 2, "首次剩余半墙锁存余牌槽位")
		var frozen := {}
		for viewer in 4:
			view.set_round(r, viewer)
			var before := _positions(view)
			frozen[viewer] = before
			var side: int = view._wall_screen_seat(seat)
			var axis := Vector2.RIGHT if side in [1, 3] else Vector2.DOWN
			var values: Array = marker.indices.map(func(index): return Vector2(before[index]).dot(axis))
			t.expect(is_equal_approx((float(values.min()) + float(values.max())) / 2, G.CENTER.dot(axis)), "首次过半余牌沿本家中心线居中")
			var client := RoundState.new()
			client.apply_sync(r.serialize_for_seat(viewer))
			view.set_round(client, viewer)
			t.expect(_same(_positions(view), before), "重连首次进入与单机墙位一致")
			if DisplayServer.get_name() != "headless" and viewer == seat:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://build/wall-centering/seat%d-half.png" % seat)
		for i in 4: r.wall.draw_head()
		t.expect(r.wall.wall_centering()[seat] == marker, "继续摸牌不改变首次居中基准")
		for viewer in 4:
			view.set_round(r, viewer)
			for index in _positions(view):
				t.expect(Vector2(frozen[viewer][index]).is_equal_approx(view.wall_center_for_index(index)), "居中后继续摸牌不再平移")
			var client := RoundState.new()
			client.apply_sync(r.serialize_for_seat(viewer))
			view.set_round(client, viewer)
			t.expect(_same(_positions(view), _remaining(frozen[viewer], r.wall)), "晚加入也使用首次基准，不按当前余牌重新居中")
	# 牌头与杠后牌尾同时消耗同一段墙，阈值仍只触发一次。
	ring.set_head(82)
	for i in 6:
		ring.draw_head()
		ring.draw_tail()
	t.expect(not ring.wall_centering().has(2), "两端合计未过半不居中")
	ring.draw_tail()
	var tail_marker: Dictionary = ring.wall_centering()[2].duplicate(true)
	for i in 4: ring.draw_tail()
	t.expect(tail_marker.indices.size() == 13 and ring.wall_centering()[2] == tail_marker, "杠后补牌触发过半，后续补牌不再移动")
	ring.set_head(0)
	t.expect(ring.wall_centering().is_empty(), "新局清除上局的居中基准")
	_check_opening_gate(view)
	await _check_flight_sources(view, tiles)
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_v2_wall_centering"))

func _check_opening_gate(view) -> void:
	var r := RoundState.new()
	r.set_rng_seed(854)
	r.pause_after_opening = true
	r.start_round(1, 2, 3)
	r.controllers = [null, null, null, null]
	var host := OpeningHost.new()
	host.round = r
	view.set_round(r, 1)
	view.table = host
	for seat in r.wall.wall_centering():
		var marker: Dictionary = r.wall.wall_centering()[seat]
		var index := int(marker.indices[0])
		var trigger := ((int(marker.taken) + 3) / 4) * 4 if int(marker.taken) <= 48 else int(marker.taken)
		host._table_animation_controller.shown = trigger - 1
		view._update_wall_centering()
		t.expect(view.wall_center_for_index(index).is_equal_approx(view._original_wall_center(index)), "收到发完牌的快照也不提前移动尚未发到半墙的墙段")
		host._table_animation_controller.shown += 1
		view._update_wall_centering()
		t.expect(view._wall_offsets.has(seat), "开局视觉进度到首次半墙时触发")
		var remaining: Array = marker.indices.filter(func(slot): return posmod(int(slot) - int(r.round_meta.break), WallRing.N) >= trigger)
		var side: int = view._wall_screen_seat(seat)
		var axis := Vector2.RIGHT if side in [1, 3] else Vector2.DOWN
		var positions: Array = remaining.map(func(slot): return view.wall_center_for_index(int(slot)).dot(axis))
		t.expect(is_equal_approx((float(positions.min()) + float(positions.max())) / 2, G.CENTER.dot(axis)), "跨半墙的四张整组拿走后，按真正余牌居中")
	view.table = null

func _check_flight_sources(view, tiles: Array) -> void:
	var config = root.get_node("GameConfig")
	config.set_tile_animation_seconds(0.1, false)
	for viewer in 4:
		for tail in [false, true]:
			var r := RoundState.new()
			r.pause_after_opening = true
			r.start_round(1, 2, 3)
			r.controllers = [null, null, null, null]
			r.wall = WallRing.new(tiles)
			r.wall.set_head(82)
			r.round_meta.erase("break")
			for i in 12:
				if tail: r.wall.draw_tail()
				else: r.wall.draw_head()
			view.set_round(r, viewer)
			for draw in 2:
				var index := r.wall._tail_index() if tail else r.wall.peek_head_index()
				var start := Vector2(_positions(view)[index])
				var card := r.wall.draw_tail() if tail else r.wall.draw_head()
				var done := {"count": 0}
				view.animate_draw(viewer, card, index, func(): done.count += 1)
				var moving: Control = view._deal_layer.get_child(0)
				t.expect((moving.position + moving.size / 2).is_equal_approx(start), "过半前后摸牌、杠后补牌都从屏幕实际墙牌位置起飞")
				var deadline := Time.get_ticks_msec() + 3000
				while done.count == 0 and Time.get_ticks_msec() < deadline: await process_frame
				t.expect(done.count == 1 and not view.native_actions_pending(), "墙位变化不阻塞摸补牌动画或重复完成")
				view.refresh()
				t.expect(view._wall_offsets.has(2), "摸牌落稳后采用半墙基准")
	config.set_tile_animation_seconds(0.0, false)

func _positions(view) -> Dictionary:
	var out := {}
	for node in view._wall_layer.get_children():
		out[int(node.get_meta("wall_ring_index"))] = node.position + node.size / 2
	return out

func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.size() == b.size() and a.keys().all(func(index): return b.has(index) and Vector2(a[index]).is_equal_approx(b[index]))

func _remaining(positions: Dictionary, wall: WallRing) -> Dictionary:
	var out := {}
	for index in positions:
		if not wall._drawn[index]: out[index] = positions[index]
	return out

func _original(view, index: int) -> Vector2:
	var segment: Dictionary = view._wall_segment_for_index(index)
	var side: int = view._wall_screen_seat(int(segment.seat))
	var columns := int(segment.len) / 2
	var slot := (index - int(segment.start)) / 2
	if side in [1, 2]: slot = columns - 1 - slot
	return G.wall_block_center(side, slot, index % 2, columns)
