extends SceneTree
## Real rendering and pointer routing: run with a display, not --headless.
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const OUT := "res://build/table-3d-review"
var t := H.new()
var _events: Array = []

func _initialize() -> void:
	call_deferred("run")

func fixture() -> RoundState:
	var round := RoundState.new()
	round.build_players(0)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	round.current_turn = 0
	round.wall = WallRing.new(TileSetFactory.create_deck())
	round.wall.set_head(0)
	for _i in 52: round.wall.draw_head()
	for player in round.players:
		# Repeated values must remain distinct physical and input entities.
		player.concealed = ["wan1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tiao2", "tiao3", "tiao4", "tong6", "tong7", "tong8", "tong9"]
		player.just_drew = "tong9"
		player.discards = ["wan8", "tiao1", "tong2"]
		player.discard_ids = [0, 1, 2]
		player.discard_count = 3
	return round

func _sources(view) -> Array:
	var out: Array = []
	for layer in view._render_layers() + [view._deal_layer]:
		for source in layer.get_children():
			if source is TileView and source.is_visible_in_tree(): out.append(source)
	return out

func _check_entities(view, renderer) -> void:
	var side_tiles: Array = []
	for source in _sources(view):
		var kind := str(source.get_meta("new_kind", ""))
		var seat := int(source.get_meta("v2_seat", -1))
		if kind not in ["ordinary", "red", "meld"] or G.relative_seat(view.human_seat, seat) not in [1, 3]: continue
		if absf(cos(source.rotation)) > 0.01: continue
		var center: Vector2 = source.position + source.size / 2.0
		for other in side_tiles:
			if other.get_meta("v2_seat") != seat or other.get_meta("new_kind") != kind: continue
			if other.get_meta("meld_index", -1) != source.get_meta("meld_index", -1): continue
			var other_center: Vector2 = other.position + other.size / 2.0
			var width: float = source.size.x * source.scale.x
			if absf(center.x - other_center.x) > 0.01 or absf(absf(center.y - other_center.y) - width - 4.0) > 0.01: continue
			var a: MeshInstance3D = renderer.tile_nodes[source.get_instance_id()]
			var b: MeshInstance3D = renderer.tile_nodes[other.get_instance_id()]
			var scale_3d := a.basis.get_scale().x
			var gap := absf(a.position.z - b.position.z) / scale_3d - 1.0
			t.expect(gap >= -0.01 and gap <= 0.025, "adjacent side discards and meld tiles touch without overlapping")
		side_tiles.append(source)
	for label in view._name_labels + view._labels:
		var text_size: Vector2 = label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
		text_size.x = minf(text_size.x, label.size.x)
		var offset := Vector2(0, (label.size.y - text_size.y) / 2.0)
		if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER: offset.x = (label.size.x - text_size.x) / 2.0
		var badge := Rect2(label.position + offset, text_size)
		t.expect(Rect2(Vector2.ZERO, view.size).encloses(badge), "player information stays on screen")
		for source in _sources(view):
			t.expect(not badge.intersects(renderer.project_tile(source)),
				"player text %s at %s avoids %s at %s" % [label.text, badge, source.get_meta("new_kind", ""), renderer.project_tile(source)])
	var sources := _sources(view)
	var expected := {}
	for source in sources:
		var id: int = source.get_instance_id()
		expected[id] = true
		if not t.expect(renderer.tile_nodes.has(id), "visible source has a real 3D mesh"):
			continue
		var entity = renderer.tile_nodes[id]
		var scale_3d: Vector3 = entity.basis.get_scale()
		t.expect(is_equal_approx(scale_3d.x, scale_3d.y) and is_equal_approx(scale_3d.x, scale_3d.z),
			"a tile preserves its original proportions in every seat and phone aspect")
		t.expect(entity is MeshInstance3D and entity.mesh != null and entity.is_visible_in_tree(),
			"the mesh is present and visible, including public discards")
		t.expect(source.presentation_3d, "table source disables its old artwork")
		var kind := str(source.get_meta("new_kind", ""))
		if not source.face_up and kind in ["hand", "draw"]:
			var at: Vector2 = renderer.camera.unproject_position(entity.transform * Vector3(0, 0, -0.65)) / Vector2(renderer.viewport.size) * renderer.size
			var cover = renderer.pick_tile(at, false)
			t.expect(cover == source, "viewer %d can count the top edge of %s at seat %s (covered by %s)" % [view.human_seat, kind, source.get_meta("v2_seat", -1), cover.get_meta("new_kind", "") if cover else "nothing"])
		if source.face_up and kind in ["ordinary", "red", "meld", "hand", "draw"]:
			var obstruction := ""
			var visible_points := 0
			var own_exposed: bool = kind in ["red", "meld"] and int(source.get_meta("v2_seat", -1)) == view.human_seat and view.round.phase != RoundState.Phase.SETTLED
			for offset in [Vector2.ZERO, Vector2(-0.29,-0.40), Vector2(0.29,-0.40), Vector2(-0.29,0.40), Vector2(0.29,0.40)]:
				var face: Vector2 = renderer.camera.unproject_position(entity.transform * Vector3(offset.x, 0.31, offset.y))
				var hit: TileView = renderer.pick_tile(face / Vector2(renderer.viewport.size) * renderer.size, false)
				if hit != source:
					if own_exposed and hit != null and str(hit.get_meta("new_kind", "")) in ["hand", "draw"] and int(hit.get_meta("v2_seat", -1)) == view.human_seat: continue
					obstruction = "%s %s" % [hit.get_meta("new_kind", ""), hit.tile] if hit else "no hit"
					break
				visible_points += 1
			t.expect(obstruction.is_empty(), "viewer %d sees the printed area of %s %s at seat %d (blocked by %s)" % [view.human_seat, kind, source.tile, source.get_meta("v2_seat", -1), obstruction])
			if own_exposed: t.expect(visible_points >= 2, "the local hand may cover the lower meld edge while its face stays identifiable")
	for id in renderer.tile_nodes:
		var entity = renderer.tile_nodes[id]
		t.expect(expected.has(id) or not is_instance_valid(entity) or not entity.visible,
			"a removed or hidden source never leaves a visible 3D ghost")

func _record(event: InputEvent, source: TileView) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_events.append({"source": source, "pressed": event.pressed,
			"inside": source._has_point(event.position), "touch": event is InputEventScreenTouch})

func _touch(renderer, point: Vector2, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = renderer.get_global_transform() * point
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	root.push_input(event)

func _mouse(renderer, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = renderer.get_global_transform() * point
	event.global_position = event.position
	root.push_input(event)

func _check_own_input(view, renderer) -> void:
	var indices := {}
	t.expect(Rect2(Vector2.ZERO, renderer.size).encloses(view._sort_button.get_rect())
		and view._sort_button.position.x > renderer.size.x * 0.75
		and view._sort_button.get_rect().end.y <= view._own_hand_top() - 10.0,
		"sorting stays on screen to the right and above the local hand")
	for source in view.hand_boxes[view.human_seat].get_children() + view.draw_boxes[view.human_seat].get_children():
		var bounds: Rect2 = renderer.project_tile(source)
		t.expect(not bounds.intersects(view._sort_button.get_rect()), "sorting never covers the hand or separate draw: %s" % bounds)
		t.expect(absf(bounds.end.y - (renderer.size.y - 44.0)) < 2.0, "the local hand rests close to the bottom table edge: %s" % bounds)
		t.expect(bounds.has_area() and Rect2(Vector2.ZERO, renderer.size).encloses(bounds),
			"the complete local tile remains in the viewport")
		var hit = renderer.pick_tile(bounds.get_center())
		t.expect(hit == source, "projected tile center picks this exact copy, not its equal-valued neighbour")
		var index: int = source.get_meta("concealed_index", -1)
		t.expect(index >= 0 and not indices.has(index)
			and view.round.players[view.human_seat].concealed[index] == source.tile,
			"physical tile retains the authoritative concealed index")
		indices[index] = true
		source.gui_input.connect(_record.bind(source))
		_events.clear()
		_mouse(renderer, bounds.get_center(), true)
		await process_frame
		_mouse(renderer, bounds.get_center(), false)
		await process_frame
		t.expect(_events.size() == 2 and _events.all(func(e): return e.source == source and e.inside),
			"real GUI input forwards one press and release for seat %d tile %d at %s" % [view.human_seat, index, root.size])
		source.gui_input.disconnect(_record.bind(source))
	t.expect(indices.size() == 14, "all thirteen hand tiles and the separate draw remain selectable")
	var first: TileView = view.hand_boxes[view.human_seat].get_child(0)
	first.gui_input.connect(_record.bind(first))
	_events.clear()
	_mouse(renderer, renderer.project_tile(first).get_center(), true)
	await process_frame
	_mouse(renderer, Vector2(1140, 640), false)
	await process_frame
	t.expect(_events.size() == 2 and _events[0].inside and not _events[1].inside,
		"releasing away from the pressed tile reaches that source as an invalid tap")
	first.gui_input.disconnect(_record.bind(first))

func _check_touch(view, renderer) -> void:
	var first: TileView = view.hand_boxes[view.human_seat].get_child(0)
	var second: TileView = view.hand_boxes[view.human_seat].get_child(1)
	first.gui_input.connect(_record.bind(first))
	second.gui_input.connect(_record.bind(second))
	_events.clear()
	_touch(renderer, renderer.project_tile(first).get_center(), true)
	await process_frame
	_touch(renderer, renderer.project_tile(second).get_center(), true, 1)
	_touch(renderer, renderer.project_tile(second).get_center(), false, 1)
	_touch(renderer, renderer.project_tile(first).get_center(), false)
	await process_frame
	var touches := _events.filter(func(e): return e.touch)
	t.expect(touches.size() == 2 and touches.all(func(e): return e.source == first and e.inside),
		"Android touch keeps the first finger's exact tile and ignores a second finger")
	_touch(renderer, renderer.project_tile(first).get_center(), true)
	_touch(renderer, renderer.project_tile(first).get_center(), false, 0, true)
	await process_frame
	t.expect(renderer._pointer == -1, "canceled Android touch releases the pointer")
	first.gui_input.disconnect(_record.bind(first))
	second.gui_input.disconnect(_record.bind(second))

func _dense_round(action_count := -1) -> RoundState:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/meld_layout_replay.json"))
	var result := RoundState.new()
	result.set_rng_seed(int(record.seed))
	result.next_dealer_seat = int(record.dealer)
	result.controllers = [null, null, null, null]
	result.pause_after_opening = true
	result.start_round(1, int(record.red), int(record.white))
	result.resume_after_opening()
	var actions: Array = record.actions
	for action in actions.slice(0, action_count if action_count >= 0 else actions.size()):
		var accepted: bool = result.submit_turn(int(action.seat), action.decision) if action.kind == "turn" else result.submit_response(int(action.seat), str(action.tile), action.decision)
		t.expect(accepted, "public tile visibility is checked against a legal replay")
	return result

func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT.path_join(filename))
	t.expect(error == OK, "rendered review screenshot is saved")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("table_3d requires a rendering display")
		quit(1)
		return
	root.get_node("UpdateManager").auto_check = false
	root.get_node("FpsOverlay").hide()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	view.scale = Vector2(root.size) / G.DESIGN_SIZE
	view.auto_sort_hands = false
	var round := fixture()
	for viewer in 4:
		round.current_turn = viewer
		view.set_round(round, viewer)
		await process_frame
		var renderer = view._table_3d
		if not t.expect(renderer != null, "the normal table enables its 3D renderer"):
			view.queue_free()
			await H.quit_cleanly(self, t.finish("table_3d"))
			return
		renderer.sync_tiles()
		await process_frame
		t.expect(renderer.viewport.size == root.size, "the table keeps native screen resolution without upscaling")
		_check_entities(view, renderer)
		var concealed_mesh = null
		for seat in 4:
			for source in view.hand_boxes[seat].get_children() + view.draw_boxes[seat].get_children():
				t.expect(source.face_up == (seat == viewer), "only the viewer knows a live concealed hand")
				if seat == viewer: continue
				t.expect(source.tile == "", "the 3D source contains no opponent tile identity")
				var mesh = renderer.tile_nodes[source.get_instance_id()].mesh
				if concealed_mesh == null: concealed_mesh = mesh
				t.expect(mesh == concealed_mesh, "all concealed opponents use the same anonymous mesh")
		await _check_own_input(view, renderer)
		await _check_touch(view, renderer)
		await _capture("seat-%d.png" % viewer)
	# Emulate Android's independent horizontal and vertical surface scaling.
	root.size = Vector2i(1600, 720)
	view.scale = Vector2(root.size) / G.DESIGN_SIZE
	await process_frame
	await RenderingServer.frame_post_draw
	t.expect(absf(Vector2(view._table_3d.viewport.size).aspect() - Vector2(root.size).aspect()) < 0.003,
		"the 3D camera renders at the actual wide phone aspect ratio")
	_check_entities(view, view._table_3d)
	await _check_own_input(view, view._table_3d)
	await _capture("wide.png")
	var renderer = view._table_3d
	var masked = view._tile(view._deal_layer, "hidden0", true, G.CENTER, G.WALL_UNIT, 0.0)
	masked.flight_pitch = 0.0
	renderer.sync_tiles()
	var masked_mesh: MeshInstance3D = renderer.tile_nodes[masked.get_instance_id()]
	t.expect(masked_mesh.mesh == renderer._meshes["wan1"], "a masked online event uses the anonymous mesh without a missing-key error")
	t.expect(masked_mesh.basis.y.normalized().dot(Vector3.UP) < -0.999, "a stale face-up flag and flight pose never expose a masked online card")
	view._release_visual_node(masked)
	renderer.sync_tiles()
	var latest: TileView = view._discard_layer.get_child(0)
	latest.set_latest_highlight(true)
	renderer.sync_tiles()
	await process_frame
	t.expect(renderer.discard_marker.visible and renderer.discard_marker.mesh is CylinderMesh,
		"the latest discard has a real three-sided 3D pointer")
	var tip: Vector2 = renderer.camera.unproject_position(renderer.discard_marker.transform * Vector3(0, 0.275, 0)) / Vector2(renderer.viewport.size) * renderer.size
	var discard_bounds: Rect2 = renderer.project_tile(latest)
	t.expect(absf(tip.x - discard_bounds.get_center().x) < 6 and tip.y < discard_bounds.position.y,
		"the pointer aims at the latest discard without covering its printed face")
	await _capture("discard-pointer.png")
	latest.modulate.a = 0.0
	renderer.sync_tiles()
	t.expect(not renderer.discard_marker.visible, "a discard hidden for its flight never leaves a pointer over empty felt")
	latest.modulate.a = 1.0
	renderer.sync_tiles()
	t.expect(renderer.discard_marker.visible, "the pointer returns when the latest discard lands visibly")
	var landed_parent = latest.get_parent()
	latest.reparent(view._deal_layer)
	renderer.sync_tiles()
	t.expect(not renderer.discard_marker.visible, "a claimed or flying actor has no resting discard pointer")
	latest.reparent(landed_parent)
	renderer.sync_tiles()
	t.expect(renderer.discard_marker.visible, "the landed discard regains its pointer after the flight")
	latest.set_latest_highlight(false)
	renderer.sync_tiles()
	t.expect(not renderer.discard_marker.visible, "claiming or clearing the latest discard removes its pointer")
	view.animate_dice(2, 5)
	view._dice_tween.kill()
	var center: Vector2 = view.UI.LANDSCAPE_CENTER
	view._tick_dice(1.0, 2, 5, center + Vector2(-view.UI.DICE_SIZE - 4, -view.UI.DICE_SIZE / 2),
		center + Vector2(4, -view.UI.DICE_SIZE / 2))
	renderer.sync_tiles()
	await process_frame
	t.expect(renderer.dice_nodes.size() == 2, "both result dice have exactly one 3D entity")
	t.expect(view._dice_red.value == 2 and view._dice_white.value == 5,
		"3D dice preserve the two independent authoritative results")
	for value in range(1, 7):
		for source in [view._dice_red, view._dice_white]:
			source.value = value
		renderer.sync_tiles()
		for source in [view._dice_red, view._dice_white]:
			var color := "red" if source == view._dice_red else "black"
			var raw: Array = renderer._dice_normals[color][str(value)]
			var normal := Vector3(raw[0], raw[1], raw[2])
			var mesh: MeshInstance3D = renderer.dice_nodes[source.get_instance_id()]
			t.expect((mesh.basis * normal).normalized().dot(Vector3.UP) > 0.999,
				"each die physically exposes its authoritative number on top")
	view._dice_red.value = 2
	view._dice_white.value = 5
	renderer.sync_tiles()
	await _capture("dice.png")
	view.clear_dice_visual()
	renderer.sync_tiles()
	await process_frame
	t.expect(renderer.dice_nodes.is_empty(), "clearing the dice removes their 3D entities")
	round.phase = RoundState.Phase.SETTLED
	view.refresh()
	renderer.sync_tiles()
	await create_timer(0.35).timeout
	for source in view.hand_boxes[view.human_seat].get_children() + view.draw_boxes[view.human_seat].get_children():
		var mesh: MeshInstance3D = renderer.tile_nodes[source.get_instance_id()]
		t.expect(mesh.basis.y.normalized().dot(Vector3.UP) > 0.999, "the local hand lies face-up and flat after settlement")
	_check_entities(view, renderer)
	await _capture("revealed-hands.png")
	var midgame := _dense_round(46)
	view.set_round(midgame, midgame.current_turn)
	renderer.sync_tiles()
	await process_frame
	_check_entities(view, renderer)
	await _capture("midgame.png")
	var dense := _dense_round()
	for viewer in 4:
		view.set_round(dense, viewer)
		renderer.sync_tiles()
		await create_timer(0.35).timeout
		_check_entities(view, renderer)
		await _capture("public-seat-%d.png" % viewer)
	await create_timer(0.1).timeout
	t.expect(RenderingServer.viewport_get_update_mode(renderer.viewport.get_viewport_rid()) == RenderingServer.VIEWPORT_UPDATE_DISABLED,
		"an unchanged mobile table stops rendering its 3D viewport")
	# The view survives new rounds and renderer meshes must survive pool reuse correctly.
	var next_round := fixture()
	next_round.players[view.human_seat].concealed = ["wan9"]
	next_round.players[view.human_seat].just_drew = ""
	view.set_round(next_round, view.human_seat)
	renderer.sync_tiles()
	await process_frame
	_check_entities(view, renderer)
	t.expect(view.hand_boxes[view.human_seat].get_child_count() == 1,
		"new round drops all stale local hand sources")
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_3d"))
