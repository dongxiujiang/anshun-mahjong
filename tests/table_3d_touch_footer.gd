extends SceneTree

const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class Host extends Control:
	var surface: Control
	var _new_areas: Control
	var round: RoundState
	var human_seat := 0
	var online := false
	var widgets := preload("res://scripts/ui/table/TableWidgets.gd").new()
	func _net_mode() -> String: return "host" if online else ""
	func _design_size() -> Vector2: return TableV2Geometry.DESIGN_SIZE
	func _next_round() -> void: pass
	func _box(parent): return widgets._box(parent)
	func _button(text, callback, dimensions, primary = false): return widgets._button(text, callback, dimensions, primary)
	func _label(parent, text, pos, dimensions, font_size, color): return widgets._label(parent, text, pos, dimensions, font_size, color)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	root.add_child(host)
	host.surface = Control.new()
	host.surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(host.surface)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	# Load the subclass after --script has initialized autoload singletons; a
	# static nested `extends TableV2` compiles too early in this launch mode.
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.surface.add_child(view)
	host._new_areas = view
	var settlement = load("res://scripts/ui/table/v2/TableV2SettlementCard.gd").new(host)
	settlement.build()
	var touch_heights := [0.0, 110.0, 150.0]
	var meld_counts := [0, 2, 4]
	var hand := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong1", "tong2", "tong3", "tong4"]
	var cases := 0
	for viewer in 4:
		host.human_seat = viewer
		for meld_count in meld_counts:
			for settled in [false, true]:
				for online in [false, true]:
					for touch_height in touch_heights:
						var round := _make_round(viewer, meld_count, settled, hand)
						host.round = round
						host.online = online
						view.test_touch_height = touch_height
						view.set_round(round, viewer)
						await process_frame
						if settled:
							view._table_3d._own_hand_pitch = 0.0
							view._table_3d.sync_tiles()
							settlement.refresh_layout()
							settlement._post_controls.show()
							_check_settlement(view, settlement, touch_height, online, viewer, meld_count)
						else:
							view._refresh_hand_arrangement()
							# Stress the shared layout used when every sort option is present.
							for button in [view._sort_button, view._restore_button, view._previous_sort_button]: button.show()
							_check_sort(view, touch_height, viewer, meld_count)
						_check_printed_faces(view, settlement if settled else null, settled, viewer, touch_height, meld_count)
						settlement._post_controls.hide()
						cases += 1
	host.queue_free()
	await process_frame
	print("[table_3d_touch_footer] cases=", cases)
	await H.quit_cleanly(self, t.finish("table_3d_touch_footer"))

func _make_round(viewer: int, meld_count: int, settled: bool, hand: Array) -> RoundState:
	var round := RoundState.new()
	round.build_players(viewer)
	round.dealer_seat = posmod(viewer + 1, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026111700 + viewer * 100 + meld_count * 10 + int(settled)
	var built: Dictionary = WallBuilder.setup(rng, round.dealer_seat)
	round.wall = WallRing.new(built.ring, round.dealer_seat)
	round.phase = RoundState.Phase.SETTLED if settled else RoundState.Phase.PLAYING
	round.current_turn = viewer
	round.awaiting = not settled
	round.round_meta = {"dealer": round.dealer_seat, "die": 1, "die_white": 2, "chicken_multiplier": 1,
		"winners": [], "self_draw": false, "all_called_draw": true}
	round.last_result = {"items": [[], [], [], []], "deltas": [0.0, 0.0, 0.0, 0.0],
		"winners": [], "all_called_draw": true, "total_delta": 0.0}
	for player in round.players:
		player.concealed = hand.duplicate()
		player.melds.clear()
		player.ready = true # Avoid starting the production hand-arrangement worker in a geometry-only check.
	var own = round.players[viewer]
	own.concealed = hand.slice(0, 13 - 3 * meld_count)
	for index in meld_count:
		own.melds.append({"kind": "kong", "tile": "tiao%d" % (index + 1),
			"from_seat": posmod(viewer + 1, 4), "revealed": true})
	return round

func _check_sort(view, touch_height: float, viewer: int, meld_count: int) -> void:
	var minimum := maxf(48.0 * 1.3, touch_height)
	var buttons: Array = [view._sort_button, view._restore_button, view._previous_sort_button]
	var canvas := Rect2(Vector2.ZERO, G.DESIGN_SIZE)
	var label := "playing viewer=%d melds=%d touch=%d" % [viewer, meld_count, int(touch_height)]
	for index in buttons.size():
		var bounds: Rect2 = buttons[index].get_rect()
		t.expect(bounds.size.y >= minimum, "%s sort button meets touch height" % label)
		t.expect(is_equal_approx(bounds.end.y, G.DESIGN_SIZE.y), "%s sort button aligns to bottom" % label)
		t.expect(canvas.encloses(bounds), "%s sort button stays on canvas" % label)
		for other in range(index):
			t.expect(not bounds.intersects(buttons[other].get_rect()), "%s sort buttons do not overlap" % label)

func _check_settlement(view, card, touch_height: float, online: bool, viewer: int, meld_count: int) -> void:
	var minimum := maxf(80.0, touch_height)
	var bounds: Rect2 = card._post_controls.get_rect()
	var canvas := Rect2(Vector2.ZERO, G.DESIGN_SIZE)
	var label := "settled viewer=%d melds=%d online=%s touch=%d" % [viewer, meld_count, str(online), int(touch_height)]
	t.expect(bounds.size.y >= minimum, "%s footer meets touch height" % label)
	t.expect(is_equal_approx(bounds.end.y, G.DESIGN_SIZE.y), "%s footer aligns to bottom" % label)
	t.expect(canvas.encloses(bounds), "%s footer stays on canvas" % label)
	var controls: Array = [card._next_round_button]
	if online:
		controls.append(card._return_seat_button)
	for index in controls.size():
		var control: Control = controls[index]
		var control_bounds: Rect2 = control.get_global_rect()
		t.expect(control.size.y >= minimum, "%s footer button meets touch height" % label)
		t.expect(is_equal_approx(control_bounds.end.y, G.DESIGN_SIZE.y), "%s footer button aligns to bottom" % label)
		t.expect(canvas.encloses(control_bounds), "%s footer button stays on canvas" % label)
		for other in range(index):
			t.expect(not control_bounds.intersects(controls[other].get_global_rect()), "%s footer buttons do not overlap" % label)

func _check_printed_faces(view, card, settled: bool, viewer: int, touch_height: float, meld_count: int) -> void:
	var renderer = view._table_3d
	var blockers: Array[Rect2] = []
	if settled:
		for control in [card._next_round_button, card._return_seat_button]:
			if control.is_visible_in_tree(): blockers.append(control.get_global_rect())
	else:
		for control in [view._sort_button, view._restore_button, view._previous_sort_button]:
			if control.is_visible_in_tree(): blockers.append(control.get_global_rect())
	var label := "%s viewer=%d melds=%d touch=%d" % ["settled" if settled else "playing", viewer, meld_count, int(touch_height)]
	var checked := 0
	for source in view.hand_boxes[viewer].get_children() + view.draw_boxes[viewer].get_children():
		var mesh: MeshInstance3D = renderer.tile_nodes.get(source.get_instance_id())
		if mesh == null or not mesh.visible: continue
		for x in [-0.45, 0.45]:
			for z in [-0.60, 0.60]:
				var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(x, 0.31, z)) / Vector2(renderer.viewport.size) * G.DESIGN_SIZE
				for blocker in blockers:
					t.expect(not blocker.has_point(point), "%s footer does not cover a printed-face corner" % label)
		checked += 1
	t.expect(checked > 0, "%s rendered own-hand face corners are available" % label)
