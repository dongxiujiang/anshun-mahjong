extends Control
## 牌组分数只读结算项目；不持有计分状态，不修改牌或玩家分数。
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const DETAILS := preload("res://scripts/ui/table/SettlementScoreDetails.gd")

var _table_ref: WeakRef
var table:
	get: return _table_ref.get_ref()
var groups: Array = []
var labels: Dictionary = {}
var hit_buttons: Dictionary = {}
var selected_id := ""
var stage_key := ""
var completed := false

func _init(view: Control) -> void:
	_table_ref = weakref(view)
	name = "SettlementScoreAnnotations"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = UI.DESIGN_SIZE

func configure(result: Dictionary, meta: Dictionary, players: Array, plan: Dictionary) -> void:
	reset()
	DETAILS.set_debug_enabled(GameConfig.debug_enabled)
	groups = DETAILS.build(result, meta, players, plan)

func _ready() -> void:
	# The full-screen table consumes background GUI events before unhandled
	# dispatch. Listen on that control; tile buttons still stop their own clicks.
	table.gui_input.connect(_dismiss_on_background)

func reset() -> void:
	_clear_inspection_highlights()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	labels.clear()
	hit_buttons.clear()
	groups.clear()
	selected_id = ""
	stage_key = ""
	completed = false

func show_stage(key: String) -> void:
	stage_key = key
	selected_id = ""
	refresh()

func finish() -> void:
	stage_key = ""
	selected_id = ""
	completed = true
	refresh()

func select_group(id: String) -> void:
	if not completed: return
	_clear_inspection_highlights()
	selected_id = "" if selected_id == id else id
	refresh()

func _unhandled_input(event: InputEvent) -> void:
	_dismiss_on_background(event)

func _dismiss_on_background(event: InputEvent) -> void:
	if not completed or selected_id == "": return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		_clear_inspection_highlights()
		selected_id = ""
		refresh()

func refresh() -> void:
	if not is_instance_valid(table) or not is_inside_tree(): return
	var c = table._settlement_animation_controller
	if not c.has_started() or c.plan.get("all_called_draw", false): return
	var wanted: Dictionary = {}
	var clicks: Dictionary = {}
	var occupied := _obstacles()
	for group in groups:
		var tiles := _tiles_for(group)
		if tiles.is_empty(): continue
		var id := str(group.id)
		var text := ""
		var amount := 0.0
		var key := stage_key
		if completed and selected_id == id:
			text = str(group.detail)
		elif key != "" and group.stages.has(key):
			var stage: Dictionary = group.stages[key]
			amount = float(stage.amount)
			if not is_zero_approx(amount): text = str(stage.text)
		if completed:
			for tile in tiles:
				var click_id := str(tile.get_instance_id())
				clicks[click_id] = true
				var button := _button(click_id, id)
				var rect := _tile_rect(tile)
				button.position = rect.position
				button.size = rect.size
		if text == "": continue
		if c.plan.is_draw and group.area == "meld" and tiles.all(func(tile): return not tile.face_up):
			# Settlement knows the amount, but a draw does not turn this meld up.
			# Keep the identity private in the explanation as well as on the tiles.
			if completed: text += "\n未翻开"
		wanted[id] = true
		var label := _label(id, text, UI.SCORE_LOSS if amount < 0 else UI.GOLD)
		_place(label, _bounds(tiles), int(group.seat), occupied)
		occupied.append(label.get_rect().grow(8.0))
		if completed and not c.plan.is_draw and int(group.seat) != int(c.plan.burned) and bool(c.plan.called[int(group.seat)]):
			for tile in tiles: tile.set_score_highlight(true)
	for id in labels.keys():
		if not wanted.has(id): _remove(labels, id)
	for id in hit_buttons.keys():
		if not clicks.has(id): _remove(hit_buttons, id)

func _tiles_for(group: Dictionary) -> Array[TileView]:
	var c = table._settlement_animation_controller
	var boxes: Dictionary = {"hand": table.hand_box, "draw": table.draw_box, "meld": table.meld_box, "chicken": table.chicken_box}
	var box: Node = boxes.get(str(group.area), {}).get(int(group.seat))
	var result: Array[TileView] = []
	for tile in c._tiles_in(box):
		if not tile.is_visible_in_tree(): continue
		if group.area == "meld":
			if int(tile.get_meta("meld_index", -1)) == int(group.meld_index): result.append(tile)
		elif tile.face_up and tile.tile in group.tiles:
			result.append(tile)
	return result

func _clear_inspection_highlights() -> void:
	if not completed or not is_instance_valid(table): return
	table._settlement_animation_controller._clear_tile_highlights()

func _button(id: String, group_id: String) -> Button:
	if hit_buttons.has(id): return hit_buttons[id]
	var button := Button.new()
	button.name = "ScoreInspect_" + id
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(select_group.bind(group_id))
	add_child(button)
	hit_buttons[id] = button
	return button

func _make_label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", TileView._font())
	label.add_theme_font_size_override("font_size", UI.SETTLEMENT_ANNOTATION_FONT_SIZE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.17, 0.13, 0.85))
	add_child(label)
	return label

func _label(id: String, text: String, color: Color) -> Label:
	if not labels.has(id):
		labels[id] = _make_label()
		labels[id].name = "ScoreAnnotation_" + id
	var label: Label = labels[id]
	label.add_theme_color_override("font_color", color)
	var font_size := UI.SETTLEMENT_ANNOTATION_FONT_SIZE
	# Keep explanations close to the group instead of shrinking an entire
	# sentence to tiny text or pushing a wide label across the table.
	var lines: Array[String] = []
	for source_line in text.split("\n"):
		var line := ""
		for character in source_line:
			if line != "" and TileView._font().get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 340:
				lines.append(line)
				line = ""
			line += character
		lines.append(line)
	label.text = "\n".join(lines)
	var measured := TileView._font().get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	label.add_theme_font_size_override("font_size", font_size)
	label.size = measured + Vector2(12, 6)
	return label

func _tile_rect(tile: Control) -> Rect2:
	return (get_global_transform().affine_inverse() * tile.get_global_transform()) * Rect2(Vector2.ZERO, tile.size)

func _bounds(tiles: Array[TileView]) -> Rect2:
	var rect := _tile_rect(tiles[0])
	for tile in tiles.slice(1): rect = rect.merge(_tile_rect(tile))
	return rect

func _obstacles() -> Array[Rect2]:
	var occupied: Array[Rect2] = []
	var c = table._settlement_animation_controller
	for seat in 4:
		for box in [table.hand_box.get(seat), table.draw_box.get(seat), table.meld_box.get(seat), table.chicken_box.get(seat)]:
			for tile in c._tiles_in(box):
				if tile.is_visible_in_tree(): occupied.append(_tile_rect(tile))
	for control in c.boards.values() + c.identity_labels.values() + table.center_labels.values() + table.net_labels.values() + [c._flip_view, table._settings_button]:
		if is_instance_valid(control) and control.is_visible_in_tree(): occupied.append(_tile_rect(control))
	return occupied

func _place(label: Label, bounds: Rect2, seat: int, occupied: Array[Rect2]) -> void:
	var relative: int = table._relative_seat(seat)
	var span := label.size
	var center := bounds.get_center()
	var inward := Vector2(0, -1)
	var origin := Vector2(center.x - span.x / 2, bounds.position.y - span.y - 12)
	if relative == 2:
		inward = Vector2(0, 1)
		origin = Vector2(center.x - span.x / 2, bounds.end.y + 12)
	elif relative == 1:
		inward = Vector2(-1, 0)
		origin = Vector2(bounds.position.x - span.x - 12, center.y - span.y / 2)
	elif relative == 3:
		inward = Vector2(1, 0)
		origin = Vector2(bounds.end.x + 12, center.y - span.y / 2)
	var best := origin
	var best_cost := INF
	var offsets: Array[int] = [0]
	for step in range(1, 20): offsets.append_array([-step, step])
	for distance in 20:
		for offset in offsets:
			var across := Vector2(20, 0) if relative % 2 == 0 else Vector2(0, 20)
			var candidate: Vector2 = origin + inward * (distance * (span.y + 10)) + across * offset
			candidate.x = clampf(candidate.x, 32, UI.DESIGN_SIZE.x - span.x - 32)
			candidate.y = clampf(candidate.y, 90, UI.DESIGN_SIZE.y - span.y - 80)
			var rect := Rect2(candidate, span).grow(6)
			var cost := 0.0
			for other in occupied:
				if rect.intersects(other): cost += rect.intersection(other).get_area()
			if cost < best_cost:
				best_cost = cost
				best = candidate
			if is_zero_approx(cost):
				label.position = best
				return
	label.position = best

func _remove(collection: Dictionary, id: String) -> void:
	var node: Node = collection[id]
	remove_child(node)
	node.queue_free()
	collection.erase(id)
