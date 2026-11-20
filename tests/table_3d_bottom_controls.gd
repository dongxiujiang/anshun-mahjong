extends SceneTree
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class Host extends Control:
	var surface: Control
	var _new_areas: Control
	var round: RoundState
	var human_seat := 0
	var online := false
	var _table_animation_controller = null
	func _local_voice_enabled() -> bool: return false
	func _can_toggle_voice_chat() -> bool: return false
	var widgets := preload("res://scripts/ui/table/TableWidgets.gd").new()
	var card: RefCounted
	var round_number := 1
	var lobby := {"ready_round": 1, "seats": [{}, {}, {}, {}]}
	var next_calls := 0
	var ready_calls := 0
	var return_calls := 0
	func _net_mode() -> String: return "host" if online else ""
	func _net_node() -> Node: return self
	func _settlement_animation_done() -> bool: return true
	func _design_size() -> Vector2: return TableV2Geometry.DESIGN_SIZE
	func _next_round() -> void: card._next_round()
	func new_game() -> void: next_calls += 1
	func set_ready(_ready: bool) -> void: ready_calls += 1
	func request_return_to_lobby() -> void: return_calls += 1
	func _box(parent): return widgets._box(parent)
	func _button(text, callback, dimensions, primary = false): return widgets._button(text, callback, dimensions, primary)
	func _label(parent, text, pos, dimensions, font_size, color): return widgets._label(parent, text, pos, dimensions, font_size, color)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var host := Host.new()
	viewport.add_child(host)
	host.surface = Control.new()
	host.add_child(host.surface)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	host.surface.add_child(view)
	host._new_areas = view
	view.table = host
	var card = load("res://scripts/ui/table/v2/TableV2SettlementCard.gd").new(host)
	host.card = card
	card.build()
	for pixels in [Vector2(1600, 1000), Vector2(1920, 1080), Vector2(2400, 1080)]:
		viewport.size = Vector2i(pixels)
		host.scale = pixels / G.DESIGN_SIZE
		for viewer in 4:
			for melds in [0, 2, 4]:
				var round := RoundState.new()
				round.build_players(viewer)
				host.round = round
				host.human_seat = viewer
				for player in round.players:
					player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong1", "tong2", "tong3", "tiao2"].slice(0, 13 - melds * 3)
					player.ready = true
					for i in melds: player.melds.append({"kind": "kong", "tile": "wan6", "from_seat": posmod(player.seat + 1, 4), "revealed": true})
				for touch_height in [0.0, 150.0]:
					view.test_touch_height = touch_height
					view.reset_native_settlement()
					round.phase = RoundState.Phase.PLAYING
					view._table_3d._own_hand_pitch = deg_to_rad(63.0)
					view.set_round(round, viewer)
					for tile in view.hand_boxes[viewer].get_children():
						var tile_bounds: Rect2 = view._table_3d.project_tile(tile)
						t.expect(absf(tile_bounds.end.y - (G.DESIGN_SIZE.y - 6.0)) <= 1.5, "playing hands still use the table edge at every touch height")
					round.phase = RoundState.Phase.SETTLED
					view._table_3d._own_hand_pitch = 0.0
					view.set_round(round, viewer)
					view.start_native_settlement(true)
					for online in [false, true]:
						host.online = online
						card.show_post_settlement_controls()
						await process_frame
						view._table_3d.sync_tiles()
						_check_footer(host, view, touch_height)
						card.hide_post_settlement_controls()
	host.card = null
	viewport.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_3d_bottom_controls"))

func _check_footer(host: Host, view, touch_height: float) -> void:
	var card = host.card
	var online := host.online
	var bounds: Rect2 = card._post_controls.get_rect()
	t.expect(is_equal_approx(bounds.size.y, maxf(touch_height, 104.0 if online else 80.0)), "online controls are 30 percent taller at the base size and both meet the touch minimum")
	t.expect(is_equal_approx(bounds.end.y, G.DESIGN_SIZE.y), "next/ready controls align with the screen bottom")
	t.expect(Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(bounds), "both solo and online controls stay fully on screen")
	t.expect(card._next_round_button.is_visible_in_tree() and not card._next_round_button.disabled, "next/ready button is available after settlement")

	var calls := host.ready_calls if online else host.next_calls
	_click(card._next_round_button)
	t.expect((host.ready_calls if online else host.next_calls) == calls + 1, "next/ready button reaches the expected action")
	t.expect(card._return_seat_button.is_visible_in_tree() == online, "the return button appears only in online rooms")
	if online:
		var previous := host.return_calls
		_click(card._return_seat_button)
		t.expect(not card._return_seat_button.disabled and host.return_calls == previous + 1, "the return button reaches the independent vote action")
	for tile in view.hand_boxes[host.human_seat].get_children() + view.draw_boxes[host.human_seat].get_children():
		var mesh: MeshInstance3D = view._table_3d.tile_nodes[tile.get_instance_id()]
		for x in [-0.5, 0.5]:
			for z in [-0.67, 0.67]:
				var point: Vector2 = view._table_3d.camera.unproject_position(mesh.transform * Vector3(x, 0.31, z)) / Vector2(view._table_3d.viewport.size) * G.DESIGN_SIZE
				t.expect(point.y + 4.0 <= bounds.position.y, "next/ready controls leave the entire printed face clear")
	for tile: TileView in view._native_meld_tiles(host.human_seat):
		var renderer = view._table_3d
		var mesh: MeshInstance3D = renderer.tile_nodes[tile.get_instance_id()]
		for x in [-0.33, 0.33]:
			for z in [-0.45, 0.45]:
				var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(x, 0.31, z)) / Vector2(renderer.viewport.size) * G.DESIGN_SIZE
				var hit: TileView = renderer.pick_tile(point, false)
				t.expect(hit == tile and point.y < bounds.position.y, "the lifted settlement hand and buttons leave the exposed meld faces readable")

func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = point
		mouse.global_position = point
		mouse.pressed = pressed
		button.get_viewport().push_input(mouse, true)
