extends "res://tests/table_v2_layout_guards.gd"

func _run() -> void:
	var deck = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(deck)
	deck.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	deck.size = G.DESIGN_SIZE
	await process_frame
	await _test_voice_hud_bounds(deck)
	deck.queue_free()
	await process_frame
	await _test_android_own_voice()
	await H.quit_cleanly(self, t.finish("table_v2_voice_names"))

func _test_android_own_voice() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var previous_emulation := Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	for data in [
		[Vector2i(1920, 1080), Rect2(0, 0, 1920, 1044), 320.0],
		[Vector2i(2400, 1080), Rect2(92, 0, 2216, 1026), 480.0],
	]:
		root.size = data[0]
		var safe: Rect2 = data[1]
		var target_px: float = 48.0 * data[2] / 160.0
		var host := VoiceTable.new()
		host.round = _fixture(13)
		for player in host.round.players:
			player.melds.clear()
			player.ready = true
		var own: PlayerState = host.round.players[host.human_seat]
		own.concealed.append("tong4")
		own.just_drew = "tong4"
		host.round.awaiting = true
		var phone := Control.new()
		phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		phone.size = G.DESIGN_SIZE
		phone.position = Vector2(18, 22)
		phone.scale = (Vector2(data[0]) - Vector2(36, 22)) / G.DESIGN_SIZE
		host.add_child(phone)
		root.add_child(host)
		var view = load("res://scenes/table/TableV2.tscn").instantiate()
		view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
		view.test_touch_height = target_px / phone.scale.y
		view.test_screen_safe_area = safe
		phone.add_child(view)
		view.set_table(host)
		await process_frame
		view._table_3d.sync_tiles()
		view.refresh()

		var name_label: Label = view._name_labels[host.human_seat]
		var score: Label = view._labels[host.human_seat]
		var button: Button = view._voice_buttons[host.human_seat]
		var voice_states: Array[bool] = []
		button.pressed.connect(func(): voice_states.append(host.microphone))
		var transform: Transform2D = view.get_global_transform_with_canvas()
		var bounds: Rect2 = transform * button.get_rect()
		var context := str(data[0])
		t.expect(safe.encloses(bounds), "%s entire mic target avoids gesture and cutout insets" % context)
		t.expect(bounds.size.x >= target_px - 0.01 and bounds.size.y >= target_px - 0.01,
			"%s mic target is at least 48dp on both axes" % context)
		t.expect(bounds.encloses(transform * name_label.get_rect()) and bounds.encloses(transform * score.get_rect()),
			"%s whole name and score belong to the same target" % context)
		var local_projected := 0
		for hand in view.hand_boxes + view.draw_boxes:
			for tile in hand.get_children():
				var projected: Rect2 = view._table_3d.project_tile(tile)
				if hand in [view.hand_boxes[host.human_seat], view.draw_boxes[host.human_seat]] and projected.has_area():
					local_projected += 1
				t.expect(not bounds.intersects(transform * projected), "%s mic target clears projected hand tiles" % context)
		t.expect(local_projected == 14, "%s full hand and drawn tile were projected" % context)
		for control in [view._sort_button, view._restore_button, view._previous_sort_button]:
			t.expect(not bounds.intersects(transform * control.get_rect()), "%s mic target clears sort actions" % context)

		await _tap_at((transform * name_label.get_rect()).get_center())
		t.expect(host.microphone and name_label.get_theme_color("font_color") == view.UI.GOLD,
			"%s name touch reaches mic enable and displays its live state" % context)
		await _tap_at((transform * score.get_rect()).get_center())
		t.expect(not host.microphone and name_label.get_theme_color("font_color") == view.UI.INK,
			"%s score touch reaches mic disable and displays its live state" % context)
		t.expect(voice_states == [true, false] and host.speakers == [true, true, true, true],
			"%s two taps fire the local voice action exactly once each" % context)
		print("[own-voice-target] screen=", data[0], " safe=", safe, " target=", bounds,
			" minimum_px=", target_px, " callbacks=", voice_states)
		host.queue_free()
		await process_frame
	Input.emulate_mouse_from_touch = previous_emulation

func _tap_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
