extends "res://tests/table_3d_river_badges.gd"

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.get_node("FpsOverlay").hide()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var output := ProjectSettings.globalize_path("res://build/quality-optimization-evidence/layout-20261120/real-replay")
	DirAccess.make_dir_recursive_absolute(output)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/meld_layout_replay.json"))
	var round := RoundState.new()
	round.controllers = [null, null, null, null]
	round.set_rng_seed(int(record.seed))
	round.pause_after_opening = true
	round.start_round(1, int(record.red), int(record.white), false)
	round.resume_after_opening()
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	for pixels in [Vector2i(1920, 1080), Vector2i(2400, 1080)]:
		root.size = pixels
		view.scale = Vector2(pixels) / G.DESIGN_SIZE
		for viewer in 4:
			view.set_round(round, viewer)
			view._table_3d.sync_tiles()
			_check_hand_bottom(view)
	for step in record.actions.size():
		var action: Dictionary = record.actions[step]
		var accepted: bool = round.submit_turn(int(action.seat), action.decision) if action.kind == "turn" else round.submit_response(int(action.seat), str(action.tile), action.decision)
		t.expect(accepted, "recorded action %d remains legal" % step)
		if not accepted: break
		var physical := {}
		for player in round.players:
			for card in player.concealed + player.discards:
				physical[card] = int(physical.get(card, 0)) + 1
			for meld in player.melds:
				physical[meld.tile] = int(physical.get(meld.tile, 0)) + (3 if meld.kind == "pung" else 4)
		for card in physical:
			t.expect(physical[card] <= 4, "real replay never creates a fifth copy of " + str(card))
		if step not in [15, 31, 47, 63]: continue
		var state := var_to_bytes(round.serialize())
		for viewer in 4:
			view.set_round(round, viewer)
			for frame in 4: await process_frame
			view._table_3d.sync_tiles()
			_check_river_contacts(view)
			_check_hand_bottom(view)
			t.expect(var_to_bytes(round.serialize()) == state, "view changes leave the recorded game unchanged")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("step-%02d-view-%d.png" % [step, viewer]))
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_layout_live_replay"))

func _check_hand_bottom(view) -> void:
	var renderer = view._table_3d
	for box in [view.hand_boxes[view.human_seat], view.draw_boxes[view.human_seat]]:
		for source in box.get_children():
			if not source.is_visible_in_tree(): continue
			var bottom: float = renderer.project_tile(source).end.y
			t.expect(absf(bottom - (G.DESIGN_SIZE.y - 6.0)) < 1.0, "each own tile shares the tabletop bottom edge")

func _check_river_contacts(view) -> void:
	var renderer = view._table_3d
	for seat in 4:
		if G.relative_seat(view.human_seat, seat) not in [0, 2]: continue
		var sources: Array = view._discard_layer.get_children().filter(func(tile): return int(tile.get_meta("v2_seat", -1)) == seat)
		for a in sources:
			var first: MeshInstance3D = renderer.tile_nodes[a.get_instance_id()]
			for b in sources:
				if a == b: continue
				var second: MeshInstance3D = renderer.tile_nodes[b.get_instance_id()]
				var width := first.basis.get_scale().x
				var distance := second.position.x - first.position.x
				if absf(first.position.z - second.position.z) > 0.01 or distance <= 0.0 or distance > width * 1.2: continue
				t.expect(distance <= width + 0.001 and distance >= width * 0.95, "adjacent north/south tiles touch without a felt gap or covering artwork")
