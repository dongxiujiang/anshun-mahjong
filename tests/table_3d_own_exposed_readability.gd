extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
var t := H.new()

class BoundsOverlay extends Control:
	var outlines: Array
	func _draw() -> void:
		for row in outlines: draw_rect(row.rect, row.color, false, 2.0)

class Host extends Control:
	var round: RoundState
	var human_seat := 1
	var _table_animation_controller = null
	func _net_mode() -> String: return ""
	func _update_interactivity() -> void: pass

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	root.add_child(host)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/own-exposed-round1.json"))
	var replay: Dictionary = REPLAY.replay(data)
	t.expect(replay.ok, "recorded Android first four legal actions replay exactly")
	if not replay.ok:
		await H.quit_cleanly(self, t.finish("table_3d_own_exposed_readability"))
		return
	var cases := 0
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864)]:
		root.size = screen
		host.scale = Vector2(screen) / G.DESIGN_SIZE
		for height in [0.0, 110.0, 150.0]:
			view.test_touch_height = height
			host.round = replay.round
			for player in host.round.players: player.ready = true
			view.set_round(host.round, 1)
			await process_frame
			view._table_3d.sync_tiles()
			_check(view, "record %s footer%d" % [screen, height])
			await _capture(view, "record-%dx%d-footer%d" % [screen.x, screen.y, height])
			for melds in 5:
				for drawn in [false, true]:
					for direction in [1, 2, 3]:
						for kind in ["kong", "concealed", "add_kong"]:
							if kind != "kong" and (melds not in [1, 4] or direction != 1): continue
							host.round = _make_round(melds, drawn, direction, kind)
							view.set_round(host.round, 1)
							await process_frame
							view._table_3d.sync_tiles()
							var label := "matrix %s footer%d melds%d drawn%s direction%d %s" % [screen, height, melds, drawn, direction, kind]
							_check(view, label)
							_check_source_semantics(view, label)
							cases += 1
							if drawn and ((kind == "kong" and (melds in [0,4] and direction == 2 or melds == 1 and height == 150)) or (kind != "kong" and melds in [1,4] and height == 150)):
								await _capture(view, "%s-%d-melds-source%d-%dx%d-footer%d" % [kind, melds, direction, screen.x, screen.y, height])
							if melds == 1:
								host.round.phase = RoundState.Phase.SETTLED
								view.set_round(host.round, 1)
								view._table_3d._own_hand_pitch = 0.0
								view._table_3d.sync_tiles()
								_check_source_semantics(view, label + " settled")
	host.queue_free()
	await process_frame
	print("[table_3d_own_exposed_readability] matrix_cases=", cases, " replay_cases=6")
	await H.quit_cleanly(self, t.finish("table_3d_own_exposed_readability"))

func _make_round(melds: int, drawn: bool, direction: int, kind: String = "kong") -> RoundState:
	var round := RoundState.new()
	round.build_players(1)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	round.current_turn = 1
	round.awaiting = false
	round.dealer_seat = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026111719
	var built: Dictionary = WallBuilder.setup(rng, 0)
	round.wall = WallRing.new(built.ring, 0)
	for player in round.players:
		player.concealed.assign(["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "tong1", "tong2", "tong3", "tong4", "tong5"])
		player.ready = true
	var own: PlayerState = round.players[1]
	own.concealed.assign(own.concealed.slice(melds * 3))
	if drawn:
		own.concealed.append("tong6")
		own.just_drew = "tong6"
	own.discards.assign(["tiao1", "tong8"])
	own.discard_ids.assign([1, 2])
	own.discard_count = 2
	round.round_meta["charge_chickens"] = {
		"tiao1": {"owner": 1, "location": "discard", "discard_id": 1},
		"tong8": {"owner": 1, "location": "discard", "discard_id": 2}}
	for index in melds:
		own.melds.append({"kind": ("kong" if kind == "concealed" else kind) if index % 2 == 0 else "pung", "tile": ["wan9", "tong8", "tiao9", "tiao1"][index], "from_seat": posmod(1 + direction, 4), "concealed": kind == "concealed" and index % 2 == 0, "revealed": false})
	return round

func _check_source_semantics(view, label: String) -> void:
	var renderer = view._table_3d
	var own: PlayerState = view.round.players[1]
	for index in own.melds.size():
		var meld: Dictionary = own.melds[index]
		if meld.kind not in ["kong", "add_kong"]: continue
		var tiles: Array = []
		for layer in [view._red_layer, view._meld_layer]:
			for source in layer.get_children():
				if int(source.get_meta("v2_seat", -1)) == 1 and int(source.get_meta("meld_index", -1)) == index: tiles.append(source)
		tiles.sort_custom(func(a,b): return int(a.get_meta("meld_slot")) < int(b.get_meta("meld_slot")))
		if not t.expect(tiles.size() == 4, label + " kong preserves all four meshes"): continue
		var sideways: Array = tiles.filter(func(tile): return int(tile.get_meta("meld_sideways", -1)) >= 0)
		var has_source: bool = meld.kind == "kong" and not meld.get("concealed", false)
		t.expect(sideways.size() == (1 if has_source else 0), label + " concealed/add kong never invents a sideways source")
		var extra = sideways[0] if has_source else tiles[3]
		var main: Array = tiles.filter(func(tile): return tile != extra)
		var first: MeshInstance3D = renderer.tile_nodes[main[0].get_instance_id()]
		var fourth: MeshInstance3D = renderer.tile_nodes[extra.get_instance_id()]
		var factor := first.basis.get_scale().x
		var along := (fourth.position.x - first.position.x) / factor
		var inward := (fourth.position.z - first.position.z) / factor
		var direction := posmod(int(meld.from_seat) - 1, 4)
		var expected := (0.17 if direction == 1 else (1.0 if direction == 2 else 1.83)) if has_source else 1.0
		t.expect(absf(along - expected) < 0.001, label + " own fourth tile identifies left / opposite / right source, or centered without source")
		t.expect(absf(inward - (-1.17 if has_source else -1.34)) < 0.001, label + " fourth tile touches above the three-tile row")

func _check(view, label: String) -> void:
	var renderer = view._table_3d
	var checked := 0
	var groups := {}
	var own_before := {}
	for layer in [view._red_layer, view._meld_layer]:
		for source in layer.get_children():
			if not source is TileView or int(source.get_meta("v2_seat", -1)) != 1: continue
			var mesh: MeshInstance3D = renderer.tile_nodes.get(source.get_instance_id())
			if mesh == null or not mesh.visible: continue
			var meld := int(source.get_meta("meld_index", -1))
			var key := "meld%d" % meld if meld >= 0 else "red%d" % source.get_instance_id()
			var face := _printed_rect(renderer, mesh)
			groups[key] = groups[key].merge(face) if groups.has(key) else face
			var sideways: bool = int(source.get_meta("meld_sideways", -1)) >= 0
			for x in ([-0.45, 0.0, 0.45] if sideways else [-0.38, 0.0, 0.38]):
				for z in ([-0.60, 0.0, 0.60] if sideways else [-0.50, 0.0, 0.50]):
					var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(x, 0.311, z)) / Vector2(renderer.viewport.size) * renderer.size
					var picked: TileView = renderer.pick_tile(point, false)
					t.expect(picked == source, "%s %s meld%d slot%d printed point %s visible (picked %s seat%d kind%s)" % [label, source.tile, source.get_meta("meld_index", -1), source.get_meta("meld_slot", -1), Vector2(x,z), picked.tile if picked != null else "none", picked.get_meta("v2_seat", -1) if picked != null else -1, picked.get_meta("new_kind", "") if picked != null else ""])
					t.expect(Rect2(Vector2.ZERO, G.DESIGN_SIZE).has_point(point), label + " exposed artwork stays on screen")
			checked += 1
	t.expect(checked >= 1, label + " has real exposed meshes")
	var order: Array = groups.keys()
	var connected: Array = [order[0]] if not order.is_empty() else []
	for _pass in order.size():
		for key in order:
			if key in connected: continue
			if connected.any(func(other): return groups[key].grow(8.0).intersects(groups[other])): connected.append(key)
	t.expect(connected.size() == order.size(), label + " own chickens and melds remain one nearby cluster")
	var revision: int = renderer.geometry_revision
	renderer.sync_tiles()
	t.expect(renderer.geometry_revision == revision, label + " unchanged geometry does not redraw")
	var layout_key: int = renderer._own_exposed_layout_key
	for id in renderer.tile_nodes:
		var source = renderer._sources[id].get_ref()
		if is_instance_valid(source) and int(source.get_meta("v2_seat", -1)) == 1: own_before[id] = renderer.tile_nodes[id].transform
	var foreign: TileView = view.hand_boxes[0].get_child(0)
	var highlighted := foreign.highlight
	foreign.highlight = not highlighted
	renderer.sync_tiles()
	t.expect(renderer._own_exposed_layout_key == layout_key, label + " opponent-only changes reuse the cached own layout")
	for id in own_before: t.expect(renderer.tile_nodes[id].transform == own_before[id], label + " opponent-only changes leave own hand and exposed transforms unchanged")
	foreign.highlight = highlighted
	renderer.sync_tiles()

func _printed_rect(renderer, mesh: MeshInstance3D) -> Rect2:
	var rect := Rect2()
	var first := true
	for x in [-0.45, 0.45]:
		for z in [-0.60, 0.60]:
			var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(x, 0.31, z)) / Vector2(renderer.viewport.size) * renderer.size
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	return rect

func _capture(view, label: String) -> void:
	var path := OS.get_environment("OWN_EXPOSED_CAPTURE")
	if path.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join(label + ".png"))
	var renderer = view._table_3d
	var boxes := []
	var overlay := BoundsOverlay.new()
	overlay.z_index = 200
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in renderer.tile_nodes:
		var source = renderer._sources[id].get_ref()
		var mesh: MeshInstance3D = renderer.tile_nodes[id]
		if not is_instance_valid(source) or not mesh.visible: continue
		var kind := str(source.get_meta("new_kind", ""))
		var seat := int(source.get_meta("v2_seat", -1))
		if seat != 1 and kind != "wall": continue
		var face := _printed_rect(renderer, mesh)
		var body: Rect2 = renderer._project_mesh(mesh)
		boxes.append({"kind": kind, "tile": source.tile, "body": [body.position.x, body.position.y, body.size.x, body.size.y], "face": [face.position.x, face.position.y, face.size.x, face.size.y]})
		if kind in ["hand", "draw"]:
			overlay.outlines.append({"rect": body, "color": Color.CORNFLOWER_BLUE})
			overlay.outlines.append({"rect": face, "color": Color.GREEN})
		elif kind == "wall": overlay.outlines.append({"rect": body, "color": Color.RED})
		else: overlay.outlines.append({"rect": face, "color": Color.YELLOW})
	var file := FileAccess.open(path.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"design_size": [2280, 1280], "tiles": boxes}))
	view.get_parent().add_child(overlay)
	var legend := Label.new()
	legend.text = "BLUE: hand body   GREEN: hand print\nRED: wall body   YELLOW: own exposed print"
	legend.position = Vector2(600, 400)
	legend.add_theme_font_size_override("font_size", 24)
	overlay.add_child(legend)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join(label + "-geometry.png"))
	overlay.queue_free()
	await process_frame
