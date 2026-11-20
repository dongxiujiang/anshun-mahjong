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
				player.ready = true
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
				t.expect(view._local_arrangement.is_empty() and view._hand_groups.get_child_count() == 0
					and not view._arrangement_caption.visible, "restore clears the local arrangement without showing annotations")
	host.queue_free()
	await process_frame
	print("[sort_annotations_layout] cases=", cases)
	await H.quit_cleanly(self, t.finish("sort_annotations_layout"))

func _check(view, host, case: String) -> void:
	var renderer = view._table_3d
	var tiles: Array = view.hand_boxes[0].get_children()
	t.expect(not view._arrangement_caption.is_visible_in_tree(), case + " the arrangement caption stays hidden")
	t.expect(not view._hand_groups.is_visible_in_tree() and view._hand_groups.get_child_count() == 0,
		case + " gold lines and discard annotations are absent")
	t.expect(host.status_label.is_visible_in_tree(), case + " teaching text stays visible")
	for button in [view._sort_button, view._restore_button, view._previous_sort_button]:
		t.expect(not button.is_visible_in_tree() and button.disabled and button.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			case + " the removed buttons cannot intercept input")
	var player: PlayerState = view.round.players[0]
	var arrangement: Dictionary = view._local_arrangement
	var cards: Array = arrangement.get("cards", [])
	t.expect(not tiles.is_empty() and tiles.size() == cards.size() and cards.size() == player.concealed.size(),
		case + " the visual arrangement shows every card in the authoritative hand")
	var indices := {}
	for slot in tiles.size():
		var tile: TileView = tiles[slot]
		var bounds: Rect2 = renderer.project_tile(tile)
		t.expect(bounds.has_area() and absf(bounds.end.y - (G.DESIGN_SIZE.y - 6.0)) <= 1.5,
			case + " every projected tile reaches the active hand baseline")
		var index: int = tile.get_meta("concealed_index", -1)
		t.expect(slot < cards.size() and index >= 0 and index < player.concealed.size()
			and not indices.has(index) and tile.tile == cards[slot] and tile.tile == player.concealed[index],
			case + " displayed order uses each real hand index once")
		indices[index] = true
	if tiles.size() == 14:
		t.expect(arrangement.has("discard") and tiles.back().tile == arrangement.discard
			and arrangement.discard in view.round.legal_turn_options(0).discards,
			case + " the calculated discard belongs to the real hand and is legal")

func _capture(screen: Vector2i, touch_height: float) -> void:
	var destination := OS.get_environment("SORT_ANNOTATIONS_CAPTURE")
	if destination.is_empty() or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(destination)
	await RenderingServer.frame_post_draw
	var path := destination.path_join("sort-%dx%d-footer%d.png" % [screen.x, screen.y, touch_height])
	t.expect(root.get_texture().get_image().save_png(path) == OK, "saves layout review screenshot")
