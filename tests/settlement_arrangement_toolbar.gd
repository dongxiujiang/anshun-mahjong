extends SceneTree
## The removed toolbar stays hidden while settlement waits for the last native flight.
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class Host extends Control:
	var round: RoundState
	var human_seat := 0
	var _table_animation_controller = null
	var _settlement_card = null
	var view
	var finished := false
	func _net_mode() -> String: return ""
	func _update_interactivity() -> void: pass
	func _clear_actions() -> void: pass
	func _refresh() -> void: view.refresh()
	func _on_settlement_animation_finished() -> void: finished = true

func _initialize() -> void: call_deferred("_run")

func _hidden(view) -> bool:
	for button in [view._sort_button, view._restore_button, view._previous_sort_button]:
		if button.visible or not button.disabled or button.mouse_filter != Control.MOUSE_FILTER_IGNORE: return false
	return not view._arrangement_caption.visible and not view._hand_groups.is_visible_in_tree() \
		and view._hand_groups.get_child_count() == 0

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.get_node("GameConfig").set_tile_animation_seconds(0.30, false)
	var images: Array = []
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864), Vector2i(1600, 1000)]:
		root.size = screen
		for footer in [0.0, 110.0, 150.0]:
			var label := "%dx%d footer%d" % [screen.x, screen.y, footer]
			var host := Host.new()
			host.size = G.DESIGN_SIZE
			host.scale = Vector2(screen) / G.DESIGN_SIZE
			root.add_child(host)
			host.round = RoundState.new()
			host.round.build_players(0)
			host.round.controllers = [null, null, null, null]
			host.round.phase = RoundState.Phase.PLAYING
			host.round.wall = WallRing.new(TileSetFactory.create_deck())
			for player in host.round.players:
				player.concealed.assign(["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5"])
				player.ready = true
			var view = load("res://scenes/table/TableV2.tscn").instantiate()
			view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
			view.test_touch_height = footer
			host.add_child(view)
			host.view = view
			view.table = host
			view.auto_sort_hands = false
			view._sort_started = true
			view.set_round(host.round, 0)
			view._sort_own_hand()
			await process_frame
			t.expect(not view._local_arrangement.is_empty(), label + " fixture selects an arrangement before settlement")
			t.expect(_hidden(view), label + " PLAYING keeps removed toolbar and annotations hidden")
			var completed := {"draw": 0}
			view.animate_draw(2, "tong7", 0, func(): completed.draw += 1)
			t.expect(view.native_presentation_pending(), label + " real native draw is pending")
			host.round._finish()
			var sources: Array = []
			for box in view.hand_boxes:
				for tile in box.get_children(): sources.append([tile, tile.position, tile.get_parent(), tile.get_index()])
			view.refresh()
			t.expect(host.round.phase == RoundState.Phase.SETTLED and not view._settlement_started, label + " actual SETTLED precedes native settlement")
			t.expect(_hidden(view), label + " pending refresh immediately hides toolbar and annotations")
			for state in sources:
				t.expect(is_instance_valid(state[0]) and state[0].position == state[1] and state[0].get_parent() == state[2] and state[0].get_index() == state[3], label + " pending refresh preserves tile identity, position and order")
			var all_hidden := true
			var captured := false
			var start := Time.get_ticks_msec()
			while view.native_presentation_pending() and Time.get_ticks_msec() - start < 3000:
				await process_frame
				view.refresh()
				all_hidden = all_hidden and _hidden(view)
				if not captured and Time.get_ticks_msec() - start >= 120 and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					images.append(["%dx%d-footer%d-pending.png" % [screen.x, screen.y, footer], root.get_texture().get_image()])
					captured = true
			t.expect(all_hidden, label + " toolbar never flashes back during natural flip and flight")
			t.expect(completed.draw == 1 and not view.native_presentation_pending(), label + " draw finishes exactly once without a retained lock")
			view._refresh_hand_arrangement()
			t.expect(_hidden(view), label + " late arrangement refresh cannot restore playing controls")
			view.start_native_settlement(true)
			t.expect(view._settlement_started and view._settlement_complete and host.finished and _hidden(view), label + " completed settlement keeps playing controls hidden")
			view.reset_native_settlement()
			host.round.phase = RoundState.Phase.PLAYING
			view.refresh()
			view._sort_own_hand()
			t.expect(not view._local_arrangement.is_empty() and not view.native_presentation_pending(), label + " PLAYING resumes without a retained presentation lock")
			t.expect(_hidden(view), label + " returning to PLAYING keeps removed toolbar and annotations hidden")
			host.queue_free()
			await process_frame
	var capture := OS.get_environment("SETTLEMENT_TOOLBAR_CAPTURE_DIR")
	if not capture.is_empty():
		DirAccess.make_dir_recursive_absolute(capture)
		for entry in images: entry[1].save_png(capture.path_join(entry[0]))
	await H.quit_cleanly(self, t.finish("settlement_arrangement_toolbar"))
