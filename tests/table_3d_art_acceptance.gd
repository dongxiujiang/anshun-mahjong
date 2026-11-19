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
	var charge_edges := await check_charge_edges(view, output)
	var result := FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify({"frames": measurements, "charge_edges": charge_edges, "checks": t.checks, "failures": t.failures}, "  "))
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

func check_charge_edges(view, output: String) -> Array:
	var results := []
	var outward := [Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]
	for pixels in [Vector2i(1280, 720), Vector2i(1600, 720)]:
		root.size = pixels
		view.scale = Vector2(pixels) / G.DESIGN_SIZE
		for owner in 4:
			var rel := G.relative_seat(0, owner)
			for card in ["tiao1", "tong8"]:
				var round := fixture(0, 0, 0)
				round._presentation.session = "charge-edge-%d-%s" % [owner, card]
				for player in round.players:
					player.discards.clear()
					player.discard_ids.clear()
					player.discard_count = 0
					player.concealed = player.concealed.slice(0, 10)
					player.just_drew = ""
				round.players[0].concealed = round.players[0].concealed.slice(0, 6)
				var player = round.players[owner]
				player.melds.append({"kind": "pung", "tile": "wan6", "from_seat": posmod(owner + 1, 4)})
				player.discards = [card]
				player.discard_ids = [200]
				player.discard_count = 1
				round.round_meta.charge_chickens = {card: {"owner": owner, "location": "discard", "discard_id": 200}}
				var renderer = view._table_3d
				for settled in [false, true]:
					round.phase = RoundState.Phase.SETTLED if settled else RoundState.Phase.PLAYING
					view.set_round(round, 0)
					view._settlement_started = settled
					renderer._own_hand_pitch = 0.0 if settled else deg_to_rad(63)
					view.refresh()
					renderer.sync_tiles()
					var charges: Array = view._red_layer.get_children().filter(func(tile): return tile.get_meta("v2_charge", false))
					var melds: Array = view._meld_layer.get_children().filter(func(tile): return tile.get_meta("v2_seat", -1) == owner)
					var label := "%dx%d-rel%d-%s-%s" % [pixels.x, pixels.y, rel, card, "result" if settled else "play"]
					if not t.expect(charges.size() == 1 and melds.size() == 3, label + " has four expected tiles"): continue
					var charge: TileView = charges[0]
					var mesh: MeshInstance3D = renderer.tile_nodes[charge.get_instance_id()]
					var pose := mesh.transform
					var angle: float = view.EXPOSED.ANGLES[rel] + PI / 2.0
					t.expect(mesh.basis.z.normalized().dot(Basis(Vector3.UP, -angle).z) > 0.999, label + " stays sideways")
					var edge := outward_edge(mesh, outward[rel])
					var gap := 0.0
					for tile in melds:
						var other: MeshInstance3D = renderer.tile_nodes[tile.get_instance_id()]
						gap = maxf(gap, absf(outward_edge(other, outward[rel]) - edge))
					t.expect(gap < 0.025, "%s outer edge lines up with its meld (gap %.4f, centers %s)" % [
						label, gap, view._exposed_specs.filter(func(spec): return spec.seat == owner).map(
							func(spec): return [spec.center, spec.lower, spec.sideways])])
					for tile in charges + melds:
						var shown: MeshInstance3D = renderer.tile_nodes[tile.get_instance_id()]
						for offset in [Vector3(0, 0.311, 0), Vector3(0.38, 0.311, 0.5), Vector3(-0.38, 0.311, -0.5)]:
							var point: Vector2 = renderer.camera.unproject_position(shown.transform * offset) / Vector2(renderer.viewport.size) * renderer.size
							t.expect(renderer.pick_tile(point, false) == tile, label + " leaves every face visible")
					if not settled:
						var unrelated = round.players[posmod(owner + 2, 4)]
						unrelated.discards = ["wan2"]
						unrelated.discard_ids = [201]
						unrelated.discard_count = 1
						view.refresh()
						t.expect(mesh.transform.is_equal_approx(pose), label + " keeps the charge pose on an unrelated discard")
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output.path_join(label + ".png"))
					results.append({"image": label + ".png", "outer_edge_error_world": gap})
	return results

func outward_edge(mesh: MeshInstance3D, direction: Vector3) -> float:
	var box := mesh.transform * mesh.mesh.get_aabb()
	return box.get_center().dot(direction) + box.size.dot(direction.abs()) / 2.0
