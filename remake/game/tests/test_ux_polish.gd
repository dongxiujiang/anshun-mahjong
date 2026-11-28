extends SceneTree

const Table = preload("res://src/presentation/TableView.gd")
const TileArt = preload("res://src/presentation/TileArt.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Main = preload("res://scenes/Main.tscn")
const Settings = preload("res://src/app/AppSettings.gd")
const Settlement = preload("res://src/app/SettlementView.gd")
const ActionButton = preload("res://src/app/TableActionButton.gd")
const UI = preload("res://src/app/AppTheme.gd")
const AudioRetirement = preload("res://tests/AudioRetirement.gd")
const Assist = preload("res://src/app/TingAssistantOverlay.gd")
const ActionFX = preload("res://src/app/ActionEffectsStage.gd")
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL UX polish: " + message)

func _run() -> void:
	root.size = Vector2i(2400, 1080)
	await _test_overlay_clearance()
	await _test_table()
	await _test_main()
	await _test_settlement()
	print("UX polish: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func _test_overlay_clearance() -> void:
	var fx := ActionFX.new()
	fx.size = Vector2(2400, 1080)
	root.add_child(fx)
	var anchors := [Vector2(1200, 648), Vector2(1440, 496.8), Vector2(1200, 291.6), Vector2(960, 496.8)]
	for seat in 4:
		_check(fx._anchor_for_seat(seat).is_equal_approx(anchors[seat]), "seat %d action stays in the inner felt gap at 2400x1080" % seat)
	fx.free()
	var overlay := Assist.new()
	overlay.size = Vector2(2400, 1080)
	root.add_child(overlay)
	await process_frame
	overlay.set_discard_drag_hint(true, true)
	_check(overlay._drag_hint.visible and overlay._drag_hint_label.text == "✓ 松手立即打出", "release-ready swipe shows the exact discard instruction")
	_check(overlay._drag_hint.get_rect().get_center().y >= 1080.0 * 0.74, "swipe hint center clears the front wall into the lower felt gap")
	_check(is_equal_approx(overlay._drag_hint.get_rect().get_center().y, 1080.0 * 0.765), "swipe hint uses the calibrated 0.765 vertical center")
	var hand := []
	var values := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "wan2", "wan3", "wan5", "wan5", "tiao9"]
	for i in values.size():
		hand.append({"id": i, "value": values[i]})
	var view := {"prompt_id": 1, "phase": "turn", "choices": {"discard_ids": range(14)}, "players": [
		{"seat": 0, "hand": hand, "discards": [], "melds": []},
		{"seat": 1, "hand": [], "discards": [{"value": "wan1"}, {"value": "wan4"}, {"value": "wan4"}, {"value": "tiao9"}], "melds": []}]}
	for x in [0.0, 1200.0, 2400.0]:
		overlay.sync_state(view, 0, 13, true, Rect2(), Vector2(x, 870))
		await process_frame
		await process_frame
		_check(overlay._popup.visible and overlay._popup_label.text == "9条 · 已出 1 张", "tenpai preview keeps the played-count label unchanged")
		_check(overlay._popup_tenpai_row.visible, "lifting the tenpai discard shows the second preview row")
		var rect := overlay._popup.get_rect()
		_check(rect.position.x >= 16.0 and rect.end.x <= 2400.0 - 16.0, "two-line preview keeps 16-pixel side clearance at lifted x=%.0f" % x)
	var row: HBoxContainer = overlay._popup_tenpai_row
	_check(row.get_child_count() == 7 and row.get_child(0).text.begins_with("打后听"), "preview shows its title, four wait chips, overflow and remaining total")
	var waits := [{"tile": "wan6", "remaining": 3}, {"tile": "wan7", "remaining": 3}, {"tile": "wan9", "remaining": 3}, {"tile": "wan1", "remaining": 2}]
	for i in waits.size():
		var chip := row.get_child(i + 1)
		_check(chip is VBoxContainer and chip.get_child(0).get_child(0).texture == TileArt.face(waits[i].tile) and chip.get_child(1).text == "余%d" % waits[i].remaining, "wait chip %d shows the expected tile face and visible remaining count" % i)
	_check(row.get_child(5).text == "+1", "preview indicates the fifth wait beyond the four displayed chips")
	_check(row.get_child(row.get_child_count() - 1).text == "余12张", "preview total includes all twelve remaining winning tiles")
	overlay.sync_state(view, 0, 3, true, Rect2(), Vector2(1200, 870))
	_check(overlay._popup.visible and overlay._popup_label.text == "4万 · 已出 2 张", "non-tenpai lift still shows only the played-count label")
	_check(not row.visible, "lifting a non-tenpai discard hides the preview row")
	overlay.free()

func _tile_point(table: Node3D, id: int) -> Vector2:
	return table.camera.unproject_position(table.tiles[id].global_position)

func _find_blank_point(table: Node3D) -> Vector2:
	for x in [-4.5, -2.2, 0.0, 2.2, 4.5]:
		for z in [-3.5, -1.8, 0.0, 1.9, 3.5]:
			var pt: Vector2 = table.camera.unproject_position(Vector3(x, 0.0, z))
			if table.tile_at(pt) < 0 and table._blank_at(pt):
				return pt
	return Vector2.ZERO

func _hold_tile(table: Node3D, id: int) -> Vector2:
	var point := _tile_point(table, id)
	var pressed: bool = table._press(point, 0, false) and table._press_id == id and table._hold.is_running()
	_check(pressed, "physical tile press starts the long-press timer")
	if pressed:
		table._hold.custom_step(Table.HOLD_SECONDS + 0.01)
	return point

func _test_table() -> void:
	var table := Table.new()
	root.add_child(table)
	await process_frame
	var game := Round.new()
	_check(game.start(1, 4, 2, Catalog.values(418)), "fixture deals a real round")
	table.apply_view(game.snapshot_for(1))
	_check(game.begin_dealer_turn(), "fixture draws from the wall")
	var view := game.snapshot_for(1)
	var draw_id: int = view.players[1].draw_id
	var wall_node: MeshInstance3D = table.tiles[draw_id]
	var origin := wall_node.transform
	table.apply_view(view)
	var draw_tween: Tween = table._motions[draw_id]
	var target: Transform3D = table._destinations[draw_id]
	_check(table.tiles[draw_id] == wall_node, "the actual draw reuses the physical wall tile")
	var draw_spec := MotionConfig.section("tile", table.quality)
	var draw_duration: float = float(draw_spec.draw_duration)
	draw_tween.custom_step(draw_duration * 0.25)
	var progress: float = Tween.interpolate_value(0.0, 1.0, 0.25, 1.0, draw_spec.sort_trans, Tween.EASE_OUT)
	var arc_y := lerpf(origin.origin.y, target.origin.y, progress) + float(draw_spec.draw_arc_h) * 4.0 * progress * (1.0 - progress)
	_check(is_equal_approx(wall_node.position.y, arc_y), "normal draw follows the MotionConfig eased arc from the wall")
	draw_tween.custom_step(draw_duration * 0.75 + 0.0001)
	_check(not draw_tween.is_running() and wall_node.transform.is_equal_approx(target), "draw lands at the configured action duration")
	table._render(false)

	var id: int = view.choices.discard_ids[0]
	var second: int = view.choices.discard_ids[1]
	var hint := TileArt.highlight_material("hint")
	table.set_hint_tiles([id, second, second, -1])
	_check(table.tiles[id].material_override == hint and table.tiles[second].material_override == hint, "both legal hand tiles glow")
	table.set_hint_tile(-1)
	_check(table._hint_tile_ids.is_empty() and table.tiles[id].material_override != hint and table.tiles[second].material_override != hint, "legacy clear removes every glow")

	var events := []
	var swipes := []
	var hints := []
	table.drag_finished.connect(func(slot): events.append(["drag", slot]))
	table.tile_clicked.connect(func(tile): events.append(["click", tile]))
	table.swipe_discard.connect(func(tile): swipes.append(tile))
	table.discard_drag_state_changed.connect(func(active, ready): hints.append([active, ready]))
	_check(Table.HOLD_SECONDS >= 0.28, "hold threshold allows a slower tap")
	var point := _hold_tile(table, id)
	var jitter := point + Vector2(2, 0)
	table._motion(jitter)
	table._release(jitter)
	_check(events == [["drag", -1], ["click", id]], "stationary held release finishes drag before emitting a tap")
	table._render(false)
	events.clear()
	point = _hold_tile(table, id)
	var other_slot := _tile_point(table, second)
	table._motion(other_slot)
	_check(table._last_drag_slot >= 0, "fixture crosses to a hand slot")
	table._motion(point)
	table._release(point)
	_check(events.size() == 1 and events[0][0] == "drag", "a move through a slot stays a drag after returning")
	table._render(false)
	events.clear()
	point = _hold_tile(table, id)
	table._motion(point + Vector2(0, 280))
	_check(table._last_drag_slot == -1, "distant motion is outside the hand slots")
	table._release(point)
	_check(events == [["drag", table._slot_at_drag(point)]], "exceeding tap tolerance suppresses a tap even without a slot change")
	table._render(false)

	point = _tile_point(table, draw_id)
	_check(table._press(point, 0, false), "upward drag starts on the draw")
	var across := point - Vector2(0, 120)
	table._motion(across)
	_check(hints == [[true, false], [true, true]], "upward drag emits start and crossing states")
	var carried: Vector3 = table._held_point(across)
	_check(is_equal_approx(table.tiles[draw_id].position.y, carried.y + table._carry_offset.y + 0.22), "ready drag lifts another 0.22")
	table._motion(across)
	table._motion(point)
	table._cancel_press()
	_check(hints == [[true, false], [true, true], [false, false]] and swipes.is_empty(), "pulling back clears the hint exactly once")
	table._render(false)
	table._press(point, 0, false)
	table._motion(across)
	table._cancel_press()
	_check(hints.slice(3) == [[true, false], [true, true], [false, false]], "canceling above the line clears the hint")
	table._render(false)
	hints.clear()
	point = _hold_tile(table, draw_id)
	table._motion(point - Vector2(0, 120))
	_check(hints == [[true, true]], "a hold used for sorting can turn into a release-ready upward drag")
	table._cancel_press()
	table._render(false)

	var waiting := view.duplicate(true)
	waiting.choices.discard_ids = []
	table.apply_view(waiting)
	events.clear()
	point = _hold_tile(table, id)
	table._release(point)
	table._render(false)
	table._press(point, 0, false)
	table._motion(point - Vector2(0, 120))
	table._release(point - Vector2(0, 120))
	_check(events == [["drag", -1]] and swipes.is_empty() and hints == [[true, true], [false, false]], "off-turn holds still sort but cannot tap, swipe, or show a discard hint")
	await _test_table_effects(table, id)
	table.free()

func _test_table_effects(table: Node3D, id: int) -> void:
	var base: Transform3D = table._destinations[id]
	var raised := base.translated(Vector3.UP * 0.56)
	# Smooth tier: crisp no-overshoot lift and quick settle from MotionConfig.
	table.apply_quality("smooth")
	var smooth_spec := MotionConfig.section("tile", "smooth")
	table._place(id, table.tiles[id].get_meta("value"), raised, "hand", true)
	var smooth_lift: Tween = table._motions[id]
	smooth_lift.custom_step(float(smooth_spec.select_up_duration) * 0.6)
	_check(table.tiles[id].position.y <= raised.origin.y + 0.0001, "smooth selection lifts cleanly without overshoot")
	smooth_lift.custom_step(float(smooth_spec.select_up_duration) * 0.4 + 0.0002)
	_check(not smooth_lift.is_running() and table.tiles[id].transform.is_equal_approx(raised), "smooth selection settles at configured duration")
	table._place(id, table.tiles[id].get_meta("value"), base, "hand", true)
	var smooth_lower: Tween = table._motions[id]
	smooth_lower.custom_step(float(smooth_spec.select_down_duration) + 0.0002)
	_check(not smooth_lower.is_running() and table.tiles[id].transform.is_equal_approx(base), "smooth deselection lands at configured duration")
	# Detail tier: iOS BACK spring overshoot on lift and smooth cubic settle.
	table.apply_quality("detail")
	var detail_spec := MotionConfig.section("tile", "detail")
	table._place(id, table.tiles[id].get_meta("value"), raised, "hand", true)
	var lift: Tween = table._motions[id]
	lift.custom_step(float(detail_spec.select_up_duration) * 0.65)
	_check(table.tiles[id].position.y > raised.origin.y, "detail selection lifts with a light overshoot")
	lift.custom_step(float(detail_spec.select_up_duration) * 0.35 + 0.0002)
	_check(not lift.is_running() and table.tiles[id].transform.is_equal_approx(raised), "detail selection settles at configured duration")
	table._place(id, table.tiles[id].get_meta("value"), base, "hand", true)
	var lower: Tween = table._motions[id]
	lower.custom_step(float(detail_spec.select_down_duration) + 0.0002)
	_check(not lower.is_running() and table.tiles[id].transform.is_equal_approx(base), "detail deselection lands at configured duration")
	var chicken := base.translated(Vector3(0, -0.5, -2))
	table._place(id, table.tiles[id].get_meta("value"), chicken, "chicken", true)
	var landing: Tween = table._motions[id]
	landing.custom_step(Table.MOVE_SECONDS + 0.0001)
	_check(not landing.is_running() and _ripple_count(table) == 1, "first gold ripple starts at landing without extending tile travel")
	var deadline := Time.get_ticks_msec() + 500
	while _ripple_count(table) < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_ripple_count(table) == 2, "second gold ripple follows the landing")

func _ripple_count(table: Node3D) -> int:
	return table.get_children().filter(func(node): return node is MeshInstance3D and node.mesh == table._ripple_mesh).size()

func _test_main() -> void:
	var path := "user://ux-polish-%d.cfg" % Time.get_ticks_usec()
	var app = Main.instantiate()
	app.table_play_only = true
	app._settings = Settings.new(path)
	_check(app._settings.save_profile("触控测试", 1), "save isolated test profile")
	root.add_child(app)
	await process_frame
	app._choose_mode("solo")
	var deadline := Time.get_ticks_msec() + 20000
	while (not app._choices().get("actions", []).has("discard") or not app._table.can_play_hand()) and Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(1)
	var real_view: Dictionary = app._view.duplicate(true)
	var ids: Array = app._choices().get("discard_ids", [])
	_check(ids.size() >= 3, "real solo opening reaches a stable human turn")
	if ids.size() >= 3:
		await _test_main_controls(app, real_view, ids)
		await app._client.leave()
		await process_frame
	_check(await AudioRetirement.release_app(app, self), "application audio retires")
	DirAccess.remove_absolute(path)

func _test_main_controls(app, real_view: Dictionary, ids: Array) -> void:
	var table: Node3D = app._table
	var projected := real_view.duplicate(true)
	var ready_ids := ids.slice(0, 2)
	if not projected.round.choices.actions.has("ready"):
		projected.round.choices.actions.append("ready")
	projected.round.choices.ready_ids = ready_ids
	app._view_changed(projected)
	var ready: Button
	for button in app._buttons.get_children():
		if button.action == "ready":
			ready = button
	_check(is_instance_valid(ready) and not ready.disabled, "ready button is actionable")
	if not is_instance_valid(ready):
		return
	ready.pressed.emit()
	_check(app._tile_action == "ready" and table._hint_tile_ids.keys() == ready_ids, "ready button lights every legal discard")
	_check(app._ting_overlay._toast_label.text.contains("请点击亮起的牌"), "ready mode shows a visible instruction with the notice hidden")
	app._tile_clicked(ids[2])
	_check(app._tile_action == "ready" and app._ting_overlay._toast_label.text.begins_with("该牌不能报听"), "invalid tile leaves ready mode active and explains the correction")
	ready.pressed.emit()
	_check(app._tile_action.is_empty() and table._hint_tile_ids.is_empty(), "pressing ready again clears the mode and lights")
	ready.pressed.emit()
	var blank := _find_blank_point(table)
	_check(blank != Vector2.ZERO and table._press(blank, 0, false) and table._press_id == -1, "fixture taps a real blank table point with no tile selected")
	table._release(blank)
	_check(app._tile_action.is_empty() and table._hint_tile_ids.is_empty(), "blank tap cancels ready when no tile is selected")
	ready.pressed.emit()
	var next := real_view.duplicate(true)
	next.round.choices.actions.erase("ready")
	next.round.choices.ready_ids = []
	next.round.prompt_id += 1
	next.round.choices.prompt_id = next.round.prompt_id
	app._view_changed(next)
	_check(app._tile_action.is_empty() and table._hint_tile_ids.is_empty(), "a prompt without ready clears the mode and lights")
	app._view_changed(real_view)
	if app._ting_overlay.has_method("set_discard_drag_hint"):
		var drag_point := _tile_point(table, ids[0])
		table._press(drag_point, 0, false)
		table._motion(drag_point - Vector2(0, 120))
		_check(app._ting_overlay._drag_hint.visible, "Main forwards the upward gesture to the overlay")
		app._cancel_table_input()
		table._render(false)
		_check(not app._ting_overlay._drag_hint.visible, "canceling table input hides the upward gesture hint")

	var banner: Button = app._auto_play_banner
	var nav: Button = app._auto_play_button
	var leave: Button = app._hud_controls.leave
	_check(leave.get_theme_stylebox("normal").border_color == Color("#8c4a50") and not app._hud_controls.values().has(banner), "leave keeps its HUD slot and has a distinct red border")
	_check(not banner.visible and not nav.has_theme_stylebox_override("normal"), "manual play starts with the banner hidden and default navigation style")
	nav.pressed.emit()
	_check(app._auto_play_active() and banner.is_visible_in_tree() and nav.text == "取消代打", "delegation shows the shortcut and updates the existing button")
	_check(not banner.text.contains("取消代打") and nav.has_theme_stylebox_override("normal"), "banner text is distinct and active styling marks the nav button")
	await process_frame
	var center := banner.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = center
		event.global_position = center
		root.push_input(event, true)
	_check(not app._auto_play_active() and not banner.visible and not nav.has_theme_stylebox_override("normal"), "clicking the banner restores manual play and original styling")
	nav.pressed.emit()
	app._show("settings")
	_check(not banner.visible and app._auto_play_active(), "the banner is hidden away from the playing screen")
	app._show("play")
	app._refresh_hud()
	nav.pressed.emit()
	_test_hud_sizes(app)
	_test_settlement_clearance(app)

	var id: int = ids[0]
	_check(table.can_play_hand(), "hand stays still before a deliberately slow tap")
	var point := _hold_tile(table, id)
	table._release(point)
	_check(app._order.view().selected_id == id, "a slow first tap selects the tile through Main")
	point = _hold_tile(table, id)
	table._release(point)
	_check(not app._round_projection.players[int(real_view.seat)].hand.any(func(face): return int(face.id) == id), "a slow second tap submits the already selected tile")
	_check(table._discard_marker.visible and table._discard_marker.mesh.material.emission_energy_multiplier > 0.72, "latest discard remains marked with brighter gold")

func _test_hud_sizes(app) -> void:
	var hud: Dictionary = app._table.custom_profile.data.hud
	var saved: Dictionary = hud.actions
	hud.actions = saved.duplicate()
	hud.actions.erase("button_scale")
	hud.actions.width = 460.0 / app._safe.size.x
	hud.actions.height = 110.0 / app._safe.size.y
	var buttons: HBoxContainer = app._buttons
	var original := buttons.get_children()
	for button in original:
		buttons.remove_child(button)
	for count in [2, 6]:
		while buttons.get_child_count() < count:
			var button := ActionButton.new()
			button.configure("pass", "过", func(): pass)
			buttons.add_child(button)
		app._fit_action_buttons(false)
		var diameter: float = buttons.get_child(0).custom_minimum_size.x
		var sep := buttons.get_theme_constant("separation")
		_check(sep == (10 if count == 2 else 8) and is_equal_approx(diameter, 90.0 if count == 2 else 70.0), "action row allocates suitable slots for %d buttons" % count)
	hud.actions.button_scale = 62.0 * 692.0 / (90.0 * app._safe.size.y)
	app._fit_action_buttons(false)
	_check(is_equal_approx(buttons.get_child(0).custom_minimum_size.x, 62.0), "response row honors an explicit button scale")
	for button in buttons.get_children():
		button.free()
	for button in original:
		buttons.add_child(button)
	hud.actions = saved
	app._fit_action_buttons(false)

func _test_settlement_clearance(app) -> void:
	var panel := Settlement.new()
	app._frame.add_child(panel)
	panel.show_result(_settlement_result(), "solo", func(): pass, func(): pass, null, true)
	app._constrain_settlement()
	var original: Rect2 = app._settlement_area
	var safe: Rect2 = app._safe.get_global_rect()
	var min_bottom := safe.position.y + safe.size.y * 0.22 + 220.0
	var visible_y := original.end.y - 18.0
	var table: Node3D = app._table
	var chicken := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.10
	chicken.mesh = mesh
	chicken.set_meta("zone", "chicken")
	chicken.set_meta("seat", app._view.seat)
	table.add_child(chicken)
	table.tiles["ux_chicken"] = chicken
	var to_view: Vector2 = Vector2(app._board_world.size) / app._board.size
	var visible_point := Vector2(original.get_center().x, visible_y)
	chicken.global_position = table.camera.project_position((visible_point - app._board.global_position) * to_view, 25.0)
	app._constrain_settlement()
	_check(app._settlement_area.end.y < visible_y, "settlement yields above a nearby chicken when there is enough height (original %s, actual %s, chicken %s, projected %s)" % [original, app._settlement_area, visible_point, app._table_screen_point(chicken.global_position)])
	var tight_point := Vector2(visible_point.x, min_bottom - 30.0)
	chicken.global_position = table.camera.project_position((tight_point - app._board.global_position) * to_view, 25.0)
	app._constrain_settlement()
	_check(app._settlement_area.is_equal_approx(original), "soft clearance falls back when remaining height is below the minimum")
	table.tiles.erase("ux_chicken")
	chicken.free()
	panel.free()

func _settlement_result() -> Dictionary:
	var seats := []
	var items := []
	var pairwise := []
	for seat in 4:
		seats.append({"nickname": "牌友%d" % seat})
		items.append([
			{"kind": "charge", "label": "冲锋鸡", "amount": 2, "opponents": [1, 2, 3], "tiles": ["tiao1"]},
			{"kind": "flip", "label": "翻鸡", "amount": 4, "opponents": [1, 2, 3], "tiles": ["wan1", "wan2", "wan3"]},
			{"kind": "pattern", "label": "自摸", "amount": 4, "opponents": [1, 2, 3], "tiles": []}])
		pairwise.append([0, 0, 0, 0])
	return {"viewer_seat": 0, "seats": seats, "round_meta": {"self_draw": true},
		"ledger": {"winners": [0], "multiplier": 1, "status": ["胡牌", "未听", "未听", "未听"],
			"items": items, "deltas": [9, -3, -3, -3], "pairwise": pairwise}}

func _test_settlement() -> void:
	var result := _settlement_result()
	for width in [395.0, 620.0]:
		var panel := Settlement.new()
		panel.theme = UI.build()
		panel.custom_minimum_size.x = width
		root.add_child(panel)
		var callback := func(): pass
		panel.show_result(result, "solo", callback, callback, null, true, callback)
		_check(panel.modulate.a == 0.0, "overlay starts transparent")
		var fade: Tween = panel._fade_in
		fade.pause()
		panel.show_result(result, "solo", callback, callback, null, true, callback)
		_check(not fade.is_valid(), "reusing the settlement retires the old fade")
		panel._fade_in.pause()
		for frame in 5:
			await process_frame
		panel.reset_size()
		await process_frame
		var rect := panel.get_global_rect()
		_check(is_equal_approx(panel.size.y, panel.height_for_width(width)), "height estimate matches actual overlay at width %.0f (%.1f vs %.1f)" % [width, panel.height_for_width(width), panel.size.y])
		_check(panel._rows_info.size() == 4 and panel._rows_info.all(func(row): return rect.encloses(row.card.get_global_rect())), "all four score rows fit without clipping")
		_check(panel._headings[0].get_child_count() == 3 and panel.next_button.size.y == 34.0, "compact footer keeps the title structure and 34-pixel controls")
		_check(panel._rows_info[0].items.get_child(0).get_child(0).get_child(0).size == Vector2(32, 24), "charge tile icon preserves sideways orientation")
		_check(panel._rows_info[0].items.get_child(1).get_child(0).get_child(0).size == Vector2(22, 29), "upright score tile icon uses the compact dimensions")
		panel._fade_in.custom_step(0.1801)
		_check(is_equal_approx(panel.modulate.a, 1.0) and panel.get_global_rect() == rect, "0.18-second fade leaves the panel rect stable")
		panel.free()
