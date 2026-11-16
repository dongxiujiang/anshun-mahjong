extends SceneTree
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void: run.call_deferred()

func _footprint(node: MeshInstance3D) -> Rect2:
	var box := node.mesh.get_aabb()
	var rect := Rect2(Vector2(node.position.x, node.position.z), Vector2.ZERO)
	for x in [box.position.x, box.end.x]:
		for y in [box.position.y, box.end.y]:
			for z in [box.position.z, box.end.z]:
				var point: Vector3 = node.transform * Vector3(x, y, z)
				rect = rect.expand(Vector2(point.x, point.z))
	return rect

func check_group(view, seat: int, from_seat: int, kind: String) -> void:
	var tiles: Array = []
	for layer in [view._meld_layer, view._red_layer]:
		for source in layer.get_children():
			if source is TileView and source.is_visible_in_tree() and int(source.get_meta("v2_seat", -1)) == seat and int(source.get_meta("meld_index", -1)) == 0: tiles.append(source)
	if not t.expect(tiles.size() == 4, "kong retains all four tiles"): return
	var renderer = view._table_3d
	var connected: Array = [0]
	var rel := G.relative_seat(view.human_seat, seat)
	var label := "%s seat=%d from=%d viewer=%d rel=%d resolution=%s" % [kind, seat, from_seat, view.human_seat, rel, root.size]
	for _pass in 4:
		for i in tiles.size():
			if i in connected: continue
			var node: MeshInstance3D = renderer.tile_nodes[tiles[i].get_instance_id()]
			var tolerance := node.basis.get_scale().x * 0.055
			for j in connected.duplicate():
				var other: MeshInstance3D = renderer.tile_nodes[tiles[j].get_instance_id()]
				if _footprint(node).grow(tolerance).intersects(_footprint(other)):
					connected.append(i)
					break
	t.expect(connected.size() == 4, "four kong tiles touch: " + label)
	var sideways := tiles.filter(func(tile): return int(tile.get_meta("meld_sideways", -1)) >= 0)
	t.expect(sideways.size() == (1 if kind == "kong" else 0), "source direction retained: " + label)
	if kind == "kong" and sideways.size() == 1:
		t.expect(int(sideways[0].get_meta("meld_slot")) == G.exposed_kong_source_slot(seat, from_seat), "sideways slot identifies source: " + label)
	for i in tiles.size():
		var a: MeshInstance3D = renderer.tile_nodes[tiles[i].get_instance_id()]
		for j in range(i + 1, tiles.size()):
			var b: MeshInstance3D = renderer.tile_nodes[tiles[j].get_instance_id()]
			var interior := _footprint(a).grow(-a.basis.get_scale().x * 0.035)
			t.expect(not interior.intersects(_footprint(b).grow(-b.basis.get_scale().x * 0.035)), "kong faces do not overlap: " + label)

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.get_node("FpsOverlay").hide()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	view.auto_sort_hands = false
	for resolution in [Vector2i(1280,720), Vector2i(1600,720), Vector2i(1600,1000)]:
		root.size = resolution
		view.scale = Vector2(root.size) / G.DESIGN_SIZE
		for seat in 4:
			for from_seat in 4:
				if from_seat == seat: continue
				for kind in ["kong", "concealed", "add_kong"]:
					if kind != "kong" and from_seat != (seat + 1) % 4: continue
					var round := RoundState.new()
					round.build_players(0)
					round.controllers = [null,null,null,null]
					round.phase = RoundState.Phase.PLAYING
					round.wall = WallRing.new(TileSetFactory.create_deck())
					round.wall.set_head(0)
					for _i in 52: round.wall.draw_head()
					for player in round.players:
						player.concealed = ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tiao2","tiao3","tiao4","tong5"]
					round.players[seat].concealed.resize(10)
					round.players[seat].melds = [{"kind":"kong" if kind == "concealed" else kind,"tile":"tong2","from_seat":from_seat,"concealed":kind == "concealed","revealed":false}]
					for viewer in 4:
						view.set_round(round, viewer)
						await process_frame
						view._table_3d.sync_tiles()
						check_group(view, seat, from_seat, kind)
	view.queue_free()
	await H.quit_cleanly(self, t.finish("table_3d_kong_spacing"))
