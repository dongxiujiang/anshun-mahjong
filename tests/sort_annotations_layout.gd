extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class Host extends Control:
	var round: RoundState
	var human_seat := 0
	var _table_animation_controller = null
	var status_label: Label
	func _net_mode() -> String: return ""
	func _update_interactivity() -> void: pass

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	root.add_child(host)
	host.status_label = Label.new()
	host.status_label.position = Vector2(60, 1192)
	host.status_label.size = Vector2(430, 64)
	host.status_label.text = "先打9万。\n也可以考虑1万、5万。"
	host.add_child(host.status_label)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	var cases := 0
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864)]:
		root.size = screen
		host.scale = Vector2(screen) / G.DESIGN_SIZE
		for touch_height in [0.0, 110.0, 150.0]:
			view.test_touch_height = touch_height
			for setup in [Vector2i(0, 13), Vector2i(2, 7), Vector2i(4, 1), Vector2i(0, 14)]:
				var melds: int = setup.x
				var round := RoundState.new()
				round.build_players(0)
				round.controllers = [null, null, null, null]
				round.phase = RoundState.Phase.PLAYING
				round.awaiting = false
				var player: PlayerState = round.players[0]
				var hand: Array = []
				for digit in "1112223334445": hand.append("wan" + digit)
				if setup.y == 14:
					hand.append("wan5")
					player.just_drew = "wan5"
				player.concealed.assign(hand.slice(melds * 3))
				player.ready = true # Geometry check does not need the asynchronous suggestion search.
				for i in melds: player.melds.append({"kind": "pung", "tile": "tiao%d" % (i + 1), "from_seat": 1})
				host.round = round
				view.set_round(round, 0)
				view._sort_own_hand()
				for choice in 2:
					await process_frame
					view._table_3d.sync_tiles()
					view._layout_arrangement_controls()
					_check(view, host, "%dx%d touch=%d cards=%d choice=%d" % [screen.x, screen.y, touch_height, setup.y, choice])
					if choice == 0 and setup.y == 13: await _capture(screen, touch_height)
					view._sort_own_hand()
				cases += 1
				view._restore_own_hand()
				t.expect(view._hand_groups.get_child_count() == 0 and not view._arrangement_caption.visible, "restore clears both annotation layers")
	host.queue_free()
	await process_frame
	print("[sort_annotations_layout] cases=", cases)
	await H.quit_cleanly(self, t.finish("sort_annotations_layout"))

func _mesh_bounds(renderer, source) -> Rect2:
	var mesh: MeshInstance3D = renderer.tile_nodes.get(source.get_instance_id())
	if mesh == null: return Rect2()
	var bounds := Rect2()
	for corner in 8:
		var point: Vector2 = renderer.camera.unproject_position(mesh.transform * mesh.mesh.get_aabb().get_endpoint(corner)) / Vector2(renderer.viewport.size) * renderer.size
		bounds = Rect2(point, Vector2.ZERO) if corner == 0 else bounds.expand(point)
	return bounds

func _check(view, host, case: String) -> void:
	var renderer = view._table_3d
	var tiles: Array = view.hand_boxes[0].get_children()
	var hand := Rect2()
	for tile in tiles:
		var bounds := _mesh_bounds(renderer, tile)
		hand = bounds if not hand.has_area() else hand.merge(bounds)
	var caption: Label = view._arrangement_caption
	var font := caption.get_theme_font("font")
	var font_size := caption.get_theme_font_size("font_size")
	var text_lines := caption.text.split("\n")
	t.expect(hand.has_area() and caption.visible and text_lines.size() == 2, case + " has projected hand and both information lines")
	t.expect(caption.size.y >= font.get_height(font_size) * 2 and caption.get_theme_constant("line_spacing") >= 0, case + " reserves two complete CJK lines")
	t.expect(Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(caption.get_rect()), case + " caption stays fully on canvas")
	t.expect(caption.position.y >= hand.end.y + 5.0 and caption.position.y - hand.end.y <= 6.2, case + " caption follows the actual hand bottom")
	t.expect(not caption.get_rect().intersects(view._seat_hud_rect(0)), case + " caption clears the player name")
	t.expect(not caption.get_global_rect().intersects(host.status_label.get_global_rect()), case + " caption clears teaching text")
	for text_line in text_lines:
		t.expect(font.get_string_size(text_line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= caption.size.x, case + " caption line fits its width")
	for button in [view._sort_button, view._restore_button, view._previous_sort_button]:
		t.expect(not caption.get_global_rect().intersects(button.get_global_rect()), case + " caption clears every sorting button")
	var slot := 0
	var groups: Array = view._local_arrangement.lengths
	var has_discard: bool = view._local_arrangement.has("discard")
	t.expect(view._hand_groups.get_child_count() == groups.size() + int(has_discard), case + " preserves every group and discard annotation")
	if tiles.size() == 14:
		t.expect(has_discard and view._hand_groups.get_node_or_null("ArrangementDiscardMark") != null, case + " retains the actual discard hint")
	for index in view._hand_groups.get_child_count():
		var length: int = groups[index] if index < groups.size() else 1
		var start := slot if index < groups.size() else tiles.size() - 1
		var group := Rect2()
		for offset in length:
			var bounds := _mesh_bounds(renderer, tiles[start + offset])
			group = bounds if not group.has_area() else group.merge(bounds)
		var line: Control = view._hand_groups.get_child(index)
		t.expect(absf(line.position.y - group.end.y - 2.0) < 0.2 and line.size.y == 3.0, case + " gold rule follows its projected group")
		t.expect(absf(line.position.x - group.position.x - 8.0) < 0.2 and absf(line.size.x - group.size.x + 16.0) < 0.2, case + " gold rule spans the actual group")
		t.expect(line.get_rect().end.y < caption.position.y, case + " gold rule clears the information text")
		t.expect(not line.get_rect().intersects(hand), case + " gold rule clears the hand and printed faces")
		slot += length

func _capture(screen: Vector2i, touch_height: float) -> void:
	var destination := OS.get_environment("SORT_ANNOTATIONS_CAPTURE")
	if destination.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(destination)
	await RenderingServer.frame_post_draw
	var path := destination.path_join("sort-%dx%d-footer%d.png" % [screen.x, screen.y, touch_height])
	t.expect(root.get_texture().get_image().save_png(path) == OK, "saves layout review screenshot")
