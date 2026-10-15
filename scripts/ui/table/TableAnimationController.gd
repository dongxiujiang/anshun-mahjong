extends "res://scripts/ui/table/TableComponent.gd"
## Consumes authoritative events; owns presentation only, never waits in RoundState.
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const ANIMATION_LAYER := preload("res://scripts/ui/TableAnimationLayer.gd")
var _animation_layer
var _animation_busy := false
var _animation_last_id := 0
var _animation_queue: Array = []
var _skip_visual_once := false
var _session := ""
var _masked: Array[Control] = []
var _event := {}
var _opening := false
var _dealt := [0, 0, 0, 0]
var _skip_button: Button

func input_locked() -> bool:
	if _opening: return true
	if _animation_busy and _event.get("type", "") == "draw" and int(_event.get("seat", -1)) == table.human_seat: return true
	for event in _animation_queue:
		if event.get("type", "") == "draw" and int(event.get("seat", -1)) == table.human_seat: return true
	return false

func reset() -> void:
	cancel()
	_animation_last_id = 0
	_session = ""
	_skip_visual_once = false

func cancel(skip_next_event: bool = false) -> void:
	_restore()
	_animation_queue.clear()
	_animation_busy = false
	_event = {}
	_opening = false
	_dealt = [0, 0, 0, 0]
	_skip_visual_once = skip_next_event
	if is_instance_valid(_skip_button): _skip_button.hide()
	if is_instance_valid(_animation_layer): _animation_layer.cancel()

func build() -> void:
	_animation_layer = ANIMATION_LAYER.new()
	_animation_layer.name = "AnimationLayer"
	table.add_child(_animation_layer)

func _skip_opening() -> void:
	cancel()
	table._refresh()

func _on_visual_event(event: Dictionary) -> void:
	if _animation_layer == null: return
	var incoming := str(event.get("session", ""))
	if incoming != "" and incoming != _session:
		cancel()
		_animation_last_id = 0
		_session = incoming
	var event_id := int(event.get("id", 0))
	if event_id <= _animation_last_id: return
	_animation_last_id = event_id
	if _skip_visual_once:
		_skip_visual_once = false
		return
	var copy := event.duplicate(true)
	if event.get("type", "") == "dice" and DisplayServer.get_name() != "headless":
		_opening = true
	var seat := int(event.get("seat", 0))
	if event.get("type", "") == "discard":
		copy["from"] = _discard_origin(seat, str(event.get("tile", "")), int(event.get("discard_index", -1)))
		copy["from_unit"] = table._hand_tile_unit(seat)
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(seat)]
	elif event.get("type", "") == "meld" and event.has("source"):
		copy["from"] = _origin(table.discard_scroll[int(event.source)], str(event.get("tile", "")))
	_animation_queue.append(copy)
	table._update_interactivity()
	table.call_deferred("_pump_visual_animation")

func _pump_visual_animation() -> void:
	if _animation_busy or _animation_queue.is_empty() or _animation_layer == null: return
	_event = _animation_queue.pop_front()
	if _event.get("type", "") == "deal_batch":
		var deals: Array = _event.get("deals", [])
		# Reverse insertion keeps the original clockwise deal order.
		for index in range(deals.size() - 1, -1, -1):
			var deal: Dictionary = deals[index]
			_animation_queue.push_front({"type": "deal", "seat": deal.get("seat", 0), "cards": deal.get("cards", [])})
		_pump_visual_animation()
		return
	_animation_busy = true
	if _event.get("type", "") == "dice":
		_opening = DisplayServer.get_name() != "headless"
	var seat := int(_event.get("seat", 0))
	_event["to"] = _animation_target_for_seat(seat)
	if not _event.has("from"): _event["from"] = table._table_center()
	_event["badge_at"] = table._table_center() + [Vector2(0,170), Vector2(250,0), Vector2(0,-170), Vector2(-250,0)][table._relative_seat(seat)]
	_event["destinations"] = _destinations(_event)
	if _event.get("type", "") == "draw" and seat != table.human_seat: _event["tile"] = ""
	refresh_masks()
	_animation_layer.play(_event, Callable(table, "_on_visual_animation_finished"))

func _tiles_in(node: Node) -> Array[TileView]:
	var tiles: Array[TileView] = []
	for child in node.get_children():
		if child is TileView: tiles.append(child)
		else: tiles.append_array(_tiles_in(child))
	return tiles

func _position(node: Control) -> Vector2:
	return _animation_layer.get_global_transform().affine_inverse() * node.global_position

func _origin(box: Control, card: String) -> Vector2:
	var tiles := _tiles_in(box)
	for tile in tiles:
		if tile.tile == card and tile.face_up: return _position(tile)
	return _position(tiles.back()) if not tiles.is_empty() else table._table_center()

func _discard_origin(seat: int, card: String, concealed_index: int = -1) -> Vector2:
	if concealed_index >= 0:
		for tile in _tiles_in(table.hand_box[seat]) + _tiles_in(table.draw_box[seat]):
			if tile.face_up and int(tile.get_meta("concealed_index", -1)) == concealed_index:
				return _position(tile)
	for tile in _tiles_in(table.hand_box[seat]) + _tiles_in(table.draw_box[seat]):
		if tile.face_up and tile.tile == card: return _position(tile)
	return _origin(table.draw_box[seat] if table.round.players[seat].ready else table.hand_box[seat], card)

func _targets(event: Dictionary) -> Array[TileView]:
	var seat := int(event.get("seat", 0))
	var type := str(event.get("type", ""))
	if type == "draw": return _tiles_in(table.draw_box[seat])
	if type in ["meld", "meld_reveal"]:
		var group: Array[TileView] = []
		for tile in _tiles_in(table.meld_box[seat]):
			if int(tile.get_meta("meld_index", -1)) == int(event.get("index", -2)): group.append(tile)
		return group
	if type == "discard":
		var candidates := _tiles_in(table.chicken_box[seat]) + _tiles_in(table.discard_scroll[seat])
		for index in range(candidates.size() - 1, -1, -1):
			var candidate: TileView = candidates[index]
			if event.has("discard_id") and int(candidate.get_meta("discard_id", -1)) == int(event.get("discard_id", -2)):
				return [candidate]
			if candidate.tile == str(event.get("tile", "")) and bool(candidate.get_meta("charge_chicken", false)) == bool(event.get("charge", false)): return [candidate]
	return []

func _destinations(event: Dictionary) -> Array:
	var result: Array = []
	var type := str(event.get("type", ""))
	var seat := int(event.get("seat", 0))
	if type == "deal":
		var cards: Array = event.get("cards", [])
		var real := _tiles_in(table.hand_box[seat])
		for index in cards.size():
			var count: int = mini(int(_dealt[seat]) + index, real.size() - 1)
			var to := _position(real[count]) if count >= 0 else _animation_target_for_seat(seat)
			result.append({"to": to, "tile": cards[index] if seat == table.human_seat else "", "unit": table._hand_tile_unit(seat), "rotation": UI.ROTATIONS[table._relative_seat(seat)]})
	else:
		for tile in _targets(event):
			var card := str(event.get("tile", ""))
			if type == "draw" and seat != table.human_seat: card = ""
			result.append({"to": _position(tile), "tile": card, "unit": tile.unit, "rotation": tile.get_global_transform().get_rotation() - _animation_layer.get_global_transform().get_rotation()})
	return result

func refresh_masks() -> void:
	_restore()
	if DisplayServer.get_name() == "headless": return
	if _opening:
		for seat in 4:
			var tiles := _tiles_in(table.hand_box[seat])
			for index in range(int(_dealt[seat]), tiles.size()): _mask(tiles[index])
			for tile in _tiles_in(table.draw_box[seat]): _mask(tile)
	if _animation_busy and _event.get("type", "") in ["draw", "discard", "meld", "meld_reveal"]:
		for tile in _targets(_event): _mask(tile)

func _mask(tile: Control) -> void:
	if not _masked.has(tile): _masked.append(tile)
	tile.modulate.a = 0.0
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _restore() -> void:
	for node in _masked:
		if is_instance_valid(node):
			node.modulate.a = 1.0
			if node is TileView: node.mouse_filter = Control.MOUSE_FILTER_STOP if node.interactive else Control.MOUSE_FILTER_IGNORE
	_masked.clear()

func _on_visual_animation_finished() -> void:
	if _event.get("type", "") == "deal":
		_dealt[int(_event.get("seat", 0))] += _event.get("cards", []).size()
	if _event.get("type", "") == "draw" or _animation_queue.is_empty():
		_opening = false
	_restore()
	_animation_busy = false
	table._update_interactivity()
	refresh_masks()
	table.call_deferred("_pump_visual_animation")
	if _animation_queue.is_empty() and table.round.phase == RoundState.Phase.SETTLED:
		table._refresh.call_deferred()

func _animation_target_for_seat(seat: int) -> Vector2:
	var tiles := _tiles_in(table.draw_box[seat])
	if not tiles.is_empty(): return _position(tiles[0])
	var layout: Dictionary = table._hand_layout(seat) if table.round.players.size() == 4 else {"draw_x": 0}
	var local := Vector2(float(layout.draw_x), float(table._seat_metrics(seat).hand_y))
	return _animation_layer.get_global_transform().affine_inverse() * (table.seat_roots[seat].get_global_transform() * local)
