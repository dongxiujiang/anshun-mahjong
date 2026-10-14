extends Control
## Presentation only; owns temporary nodes and interruptible cubic easing.
signal finished(event_id: int)
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const DICE := preload("res://scripts/ui/DiceView.gd")
var _next_event_id := 0
var _active: Tween
var _temporary: Array[Node] = []
var _skip := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_skip(value: bool) -> void:
	_skip = value
	if _skip: cancel()

func play(event: Dictionary, target: Callable = Callable()) -> int:
	cancel()
	_next_event_id += 1
	var event_id := _next_event_id
	if DisplayServer.get_name() == "headless" or _skip:
		_finish(target, event_id)
		return event_id
	_active = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_active.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	match str(event.get("type", "")):
		"dice": _dice(event)
		"deal", "draw", "discard", "meld", "meld_reveal": _tiles(event)
		"win": _win(event)
		"ready": _badge("报听", event, _duration(0.24))
		_: _active.tween_interval(0.001)
	_active.tween_callback(func(): _finish(target, event_id))
	return event_id

func _duration(seconds: float) -> float:
	return GameConfig.animation_duration(seconds)

func _add(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	_temporary.append(node)

func _dice(event: Dictionary) -> void:
	var die := DICE.new()
	die.size = Vector2(104, 104)
	die.pivot_offset = die.size / 2.0
	die.position = UI.LANDSCAPE_CENTER - die.size / 2.0
	die.rotation = -0.45
	die.scale = Vector2.ONE * 0.72
	_add(die)
	var resting_position := die.position
	_active.tween_method(func(progress: float):
		die.rotation = lerpf(-0.45, TAU, progress)
		die.scale = Vector2.ONE * lerpf(0.72, 1.0, progress)
		die.position = resting_position + Vector2(26 * sin(progress * PI) * (1.0-progress), -18 * sin(progress * PI))
		die.value = (int(progress * 36) % 6 + 1) if progress < 1.0 else int(event.get("value", 1)), 0.0, 1.0, UI.DICE_DURATION)
	_active.tween_callback(func(): die.value = int(event.get("value", 1)))
	_active.tween_interval(GameConfig.OPENING_DICE_HOLD_SECONDS)

func _tiles(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	var destinations: Array = event.get("destinations", [])
	if destinations.is_empty():
		destinations = [{"to": event.get("to", UI.LANDSCAPE_CENTER), "tile": event.get("tile", ""), "unit": UI.ANIMATION_TILE_UNIT, "rotation": 0.0}]
	var duration := UI.DEAL_DURATION if type == "deal" else _duration(UI.DISCARD_DURATION if type == "discard" else (UI.MELD_DURATION if type == "meld" else UI.DRAW_DURATION))
	for index in destinations.size():
		var data: Dictionary = destinations[index]
		var tile := TileView.new()
		var card := str(data.get("tile", ""))
		tile.set_card(card, card != "" and card != "hidden0")
		tile.set_unit(float(data.get("unit", UI.ANIMATION_TILE_UNIT)))
		tile.rotation = float(data.get("rotation", 0.0))
		var to := Vector2(data.get("to", UI.LANDSCAPE_CENTER))
		_add(tile)
		tile.position = Vector2(event.get("from", UI.LANDSCAPE_CENTER)) + Vector2(index * 16.0, -24)
		if type == "meld_reveal":
			tile.position = to
			tile.set_card(card, false)
			tile.pivot_offset = tile.size / 2.0
			_active.parallel().tween_property(tile, "scale:x", 0.05, duration / 2.0)
		else:
			tile.scale = Vector2.ONE * (float(event.get("from_unit", tile.unit)) / tile.unit if type == "discard" else 0.78)
			var final_rotation := tile.rotation
			if type == "discard": tile.rotation = float(event.get("from_rotation", final_rotation))
			_active.parallel().tween_property(tile, "rotation", final_rotation, duration)
			_active.parallel().tween_property(tile, "position", to, duration)
			_active.parallel().tween_property(tile, "scale", Vector2.ONE, duration)
	if type == "meld_reveal":
		_active.tween_callback(func():
			for tile in _temporary:
				if tile is TileView: tile.set_card(tile.tile, true))
		for tile in _temporary:
			_active.parallel().tween_property(tile, "scale:x", 1.0, duration / 2.0)
	if type == "meld": _badge("碰" if event.get("kind", "") == "pung" else "杠", event, duration)

func _badge(text: String, event: Dictionary, duration: float) -> void:
	var badge := Label.new()
	badge.text = text
	badge.size = Vector2(170, 112)
	var anchor := Vector2(event.get("badge_at", UI.LANDSCAPE_CENTER))
	badge.position = anchor - badge.size / 2.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_override("font", TileView._font())
	badge.add_theme_font_size_override("font_size", 72)
	badge.add_theme_color_override("font_color", UI.GOLD)
	badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	badge.add_theme_constant_override("shadow_offset_y", 4)
	badge.pivot_offset = badge.size / 2.0
	badge.scale = Vector2.ONE * 0.88
	_add(badge)
	_active.parallel().tween_property(badge, "scale", Vector2.ONE, duration)
	_active.tween_interval(_duration(0.16))
	_active.tween_property(badge, "modulate:a", 0.0, _duration(0.14))

func _win(event: Dictionary) -> void:
	_badge("自摸" if event.get("self_draw", false) else "胡", event, _duration(0.24))
	_active.tween_interval(_duration(0.18))

func _finish(target: Callable, event_id: int) -> void:
	_clear_nodes()
	_active = null
	if target.is_valid(): target.call()
	finished.emit(event_id)

func cancel() -> void:
	if _active != null:
		_active.kill()
		_active = null
	_clear_nodes()

func _clear_nodes() -> void:
	for node in _temporary:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_temporary.clear()

func _exit_tree() -> void:
	cancel()
