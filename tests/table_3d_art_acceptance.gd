extends "res://tests/table_3d_river_badges.gd"
## Fixed camera and fixtures for material comparison, with real rendered evidence.

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.get_node("FpsOverlay").hide()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var output := ProjectSettings.globalize_path("res://build/qa/art-acceptance")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	var measurements := []
	for pixels in [Vector2i(1280, 720), Vector2i(1600, 720)]:
		root.size = pixels
		view.scale = Vector2(pixels) / G.DESIGN_SIZE
		for stage in ["wall", "melds", "dense", "settlement"]:
			var round := fixture(0, 0 if stage == "wall" else (4 if stage == "dense" else 2), 0 if stage == "wall" else 2)
			if stage != "dense":
				for player in round.players:
					player.discards = [] if stage == "wall" else ["wan2", "tong3", "wan5", "tiao7", "wan8", "tong6", "tiao1", "tong8"]
					player.discard_ids = range(player.discards.size())
					player.discard_count = player.discards.size()
				round.wall = WallRing.new(TileSetFactory.create_deck())
				if stage != "wall":
					for i in 84: round.wall.draw_head()
			if stage == "settlement": round.phase = RoundState.Phase.SETTLED
			view.set_round(round, 0)
			view._table_3d._own_hand_pitch = 0.0 if stage == "settlement" else deg_to_rad(63)
			for frame in 5: await process_frame
			view._table_3d.sync_tiles()
			if stage != "wall":
				check_rivers(view)
				check_exposed(view)
			await RenderingServer.frame_post_draw
			var filename := "%s-%dx%d.png" % [stage, pixels.x, pixels.y]
			root.get_texture().get_image().save_png(output.path_join(filename))
			var renderer = view._table_3d
			measurements.append({"image": filename, "tiles": renderer.tile_nodes.size(),
				"draw_calls": RenderingServer.viewport_get_render_info(renderer.viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				"primitives": RenderingServer.viewport_get_render_info(renderer.viewport.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)})
	check_charge_orientation(view)
	var result := FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify({"frames": measurements, "checks": t.checks, "failures": t.failures}, "  "))
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_3d_art_acceptance"))

func check_charge_orientation(view) -> void:
	for viewer in 4:
		for owner in 4:
			var round := fixture(viewer, 1, 2)
			var discard_id: int = round.players[owner].discards.find("tiao1")
			round.round_meta.charge_chickens = {"tiao1": {"owner": owner, "location": "discard", "discard_id": discard_id}}
			for settled in [false, true]:
				round.phase = RoundState.Phase.SETTLED if settled else RoundState.Phase.PLAYING
				view.set_round(round, viewer)
				view._table_3d.sync_tiles()
				var charged: Array = view._red_layer.get_children().filter(func(tile): return tile.get_meta("v2_charge", false))
				t.expect(charged.size() == 1, "the charge chicken retains its unique public identity during play and settlement")
				if charged.size() != 1: continue
				var expected: float = view.EXPOSED.ANGLES[G.relative_seat(viewer, owner)] + PI / 2
				var mesh: MeshInstance3D = view._table_3d.tile_nodes[charged[0].get_instance_id()]
				t.expect(mesh.basis.z.normalized().dot(Basis(Vector3.UP, -expected).z) > 0.999,
					"the real charge-chicken mesh stays sideways for every owner and viewer, including settlement")
