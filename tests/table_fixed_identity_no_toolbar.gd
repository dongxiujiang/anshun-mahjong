extends "res://tests/table_v2_layout_guards.gd"
## 当前需求：固定四家名分、移除排法工具栏，保留自动理牌。

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(G.DESIGN_SIZE)
	for touch in [0.0, 96.0, 176.0]:
		var view = load("res://scenes/table/TableV2.tscn").instantiate()
		view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
		view.test_touch_height = touch
		view.test_screen_safe_area = Rect2(92, 0, 2096, 1226) if touch > 0 else Rect2()
		root.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = G.DESIGN_SIZE
		await process_frame
		for viewer in 4:
			var r := _fixture(0)
			for player in r.players:
				player.melds.clear()
				player.score = -1234567
			view.set_round(r, viewer)
			var anchors := _identity_rects(view)
			for count in [0, 1, 4, 8, 13, 14, 10, 7, 4, 1]:
				r.phase = RoundState.Phase.DEALING if count in [0, 8, 13] else RoundState.Phase.PLAYING
				for player in r.players:
					player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong1", "tong2", "tong3", "tiao2", "tiao3"].slice(0, count)
					player.just_drew = "tiao3" if count == 14 else ""
					player.melds.clear()
					if count in [10, 7, 4, 1]:
						for i in (13 - count) / 3:
							player.melds.append({"kind": "kong", "tile": "tong8", "from_seat": player.seat, "revealed": true, "formed_at": i + 1})
				view.refresh()
				view._table_3d.sync_tiles()
				view._follow_hand_hud()
				t.expect(_identity_rects(view) == anchors, "viewer %d touch %d count %d keeps all four name and score rects fixed" % [viewer, touch, count])
				_check_hidden_toolbar(view)
				_check_clearance(view, count)
			r.phase = RoundState.Phase.SETTLED
			r.last_result = {"deltas": [-123456789, 123456789, -123456789, 123456789]}
			view._settlement_started = true
			view.refresh()
			t.expect(_identity_rects(view) == anchors, "settlement and large deltas keep every name and score fixed")
			_check_hidden_toolbar(view)
			view._local_arrangement = {"key": "unused-toolbar", "cards": r.players[viewer].concealed.duplicate()}
			view._start_arrangement_search()
			t.expect(view._arrangement_thread == null, "removed toolbar never starts a background arrangement search")
			t.expect(view.auto_sort_hands, "automatic opening hand sorting remains enabled")
		view.queue_free()
		await process_frame
	await _test_dense_phone()
	await H.quit_cleanly(self, t.finish("table_fixed_identity_no_toolbar"))

func _identity_rects(view) -> Array:
	var result := []
	for seat in 4:
		result.append([view._name_labels[seat].get_rect(), view._labels[seat].get_rect()])
	return result

func _check_hidden_toolbar(view) -> void:
	for button in [view._sort_button, view._restore_button, view._previous_sort_button]:
		t.expect(not button.visible and button.disabled and button.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"removed arrangement buttons stay hidden and cannot intercept touches")
	t.expect(not view._arrangement_caption.visible and not view._hand_groups.visible and view._hand_groups.get_child_count() == 0,
		"no arrangement caption or gold hand-group underline is created")

func _check_clearance(view, count: int) -> void:
	var panels := []
	for seat in 4:
		var panel: Rect2 = view._own_hud_rect() if seat == view.human_seat else view._seat_hud_rect(seat)
		panels.append(panel)
		var safe: Rect2 = view.test_screen_safe_area if view.test_touch_height > 0 else Rect2(Vector2.ZERO, G.DESIGN_SIZE)
		t.expect(safe.encloses(panel), "fixed seat HUD stays inside screen safe area")
		var clear := true
		for box in view.hand_boxes + view.draw_boxes + [view._meld_layer, view._red_layer, view._wall_layer]:
			for tile in box.get_children():
				if not tile is TileView or not tile.is_visible_in_tree(): continue
				var projected: Rect2 = view._table_3d.project_tile(tile)
				if projected.has_area() and panel.intersects(projected):
					clear = false
					print("[hud-overlap] count=", count, " seat=", seat, " panel=", panel, " tile=", tile.get_meta("new_kind", ""), " rect=", projected)
		t.expect(clear, "fixed seat HUD avoids all visible hand, meld and wall tiles")
	var actions: Rect2 = view.action_bar_rect(Vector2(700, 96))
	t.expect(not panels.any(func(panel): return panel.intersects(actions)), "status actions avoid fixed names and scores")

func _test_dense_phone() -> void:
	root.size = Vector2i(2400, 1080)
	var host := VoiceTable.new()
	host.round = _fixture(13)
	for player in host.round.players:
		player.melds.clear()
		player.ready = true
	host.round.players[host.human_seat].concealed.append("tong4")
	host.round.players[host.human_seat].just_drew = "tong4"
	host.round.awaiting = true
	var phone := Control.new()
	phone.size = G.DESIGN_SIZE
	phone.position = Vector2(18, 22)
	phone.scale = Vector2(2364, 1058) / G.DESIGN_SIZE
	host.add_child(phone)
	root.add_child(host)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.test_touch_height = 144.0 / phone.scale.y
	view.test_screen_safe_area = Rect2(92, 0, 2216, 1026)
	phone.add_child(view)
	view.set_table(host)
	await process_frame
	view._table_3d.sync_tiles()
	view.refresh()
	var panel: Rect2 = view._own_hud_rect()
	var anchors := _identity_rects(view)
	for box in view.hand_boxes + view.draw_boxes:
		for tile in box.get_children():
			var bounds: Rect2 = view._table_3d.project_tile(tile)
			if panel.intersects(bounds): print("[dense-phone-hud-overlap] panel=", panel, " tile=", tile.get_meta("new_kind", ""), " rect=", bounds)
			t.expect(not panel.intersects(bounds), "480dpi wide phone fixed HUD clears all projected hands")
	for player in host.round.players:
		player.concealed = ["wan1"]
		player.just_drew = ""
	view.refresh()
	t.expect(_identity_rects(view) == anchors, "480dpi wide phone fixed HUD stays put after hands shrink")
	host.queue_free()
	await process_frame
