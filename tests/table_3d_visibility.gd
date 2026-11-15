extends RefCounted

static func public_faces_visible(view) -> bool:
	var renderer = view._table_3d
	renderer.sync_tiles()
	var clear := true
	var own_groups := {}
	for layer in [view._discard_layer, view._red_layer, view._meld_layer]:
		for tile in layer.get_children():
			if not tile.face_up: continue
			var mesh: MeshInstance3D = renderer.tile_nodes[tile.get_instance_id()]
			var visible_points := 0
			for offset in [Vector2.ZERO, Vector2(-0.29, -0.40), Vector2(0.29, -0.40), Vector2(-0.29, 0.40), Vector2(0.29, 0.40)]:
				var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(offset.x, 0.31, offset.y)) / Vector2(renderer.viewport.size) * renderer.size
				var hit: TileView = renderer.pick_tile(point, false)
				if hit == tile:
					visible_points += 1
				elif hit == null or int(tile.get_meta("v2_seat")) != view.human_seat or int(hit.get_meta("v2_seat", -1)) != view.human_seat or str(hit.get_meta("new_kind", "")) not in ["hand", "draw"]:
					print("[occlusion] ", tile.tile, " seat", tile.get_meta("v2_seat"), " blocked by ", hit.get_meta("new_kind") if hit else "nothing", " ", hit.tile if hit else "")
					clear = false
			var own_meld: bool = int(tile.get_meta("v2_seat")) == view.human_seat and int(tile.get_meta("meld_index", -1)) >= 0
			if own_meld:
				var group := int(tile.get_meta("meld_index"))
				own_groups[group] = maxi(own_groups.get(group, 0), visible_points)
			if visible_points < 2 and (not own_meld or int(tile.get_meta("meld_sideways", -1)) >= 0):
				print("[occlusion] fewer than two visible face points: ", tile.tile, " seat", tile.get_meta("v2_seat"), " viewer", view.human_seat, " kind", tile.get_meta("new_kind"), " melds", view.round.players[view.human_seat].melds.size())
				clear = false
	for visible_points in own_groups.values():
		if visible_points < 2: clear = false
	return clear
