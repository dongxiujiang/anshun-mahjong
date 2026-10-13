class_name TableAnimationLayer
extends Control
## 牌桌视觉动画层。它只负责临时节点和 Tween，不推动 RoundState。

signal finished(event_id: int)

const DICE_DURATION := 0.72
const DEAL_DURATION := 0.28
const DRAW_DURATION := 0.22
const TILE_UNIT := 1.15

var _next_event_id := 0
var _active: Tween
var _temporary: Array[Node] = []
var _skip := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_skip(value: bool) -> void:
	_skip = value
	if _skip:
		_clear_active()

func play(event: Dictionary, target: Callable = Callable()) -> int:
	_next_event_id += 1
	var event_id := _next_event_id
	if _is_headless() or _skip:
		_call_target(target)
		finished.emit(event_id)
		return event_id
	_clear_active()
	match str(event.get("type", "")):
		"dice": _play_dice(event, target, event_id)
		"deal": _play_deal(event, target, event_id)
		"draw": _play_draw(event, target, event_id)
		_:
			_call_target(target)
			finished.emit(event_id)
	return event_id

func cancel() -> void:
	_clear_active()

func _play_dice(event: Dictionary, target: Callable, event_id: int) -> void:
	var die := Label.new()
	die.text = str(event.get("value", 1))
	die.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	die.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	die.add_theme_font_size_override("font_size", 46)
	die.add_theme_color_override("font_color", Color("#f5f3e8"))
	die.position = Vector2(1060, 590)
	die.size = Vector2(160, 120)
	add_child(die)
	_temporary.append(die)
	_active = create_tween()
	_active.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active.tween_property(die, "rotation", TAU * 1.5, DICE_DURATION)
	_active.parallel().tween_property(die, "scale", Vector2(1.18, 1.18), DICE_DURATION * 0.45)
	_active.tween_property(die, "scale", Vector2.ONE, DICE_DURATION * 0.25)
	_active.tween_callback(func(): _finish(die, target, event_id))

func _play_deal(event: Dictionary, target: Callable, event_id: int) -> void:
	var cards: Array = event.get("cards", [])
	var destination := Vector2(event.get("to", Vector2(1140, 650)))
	if cards.is_empty():
		_call_target(target)
		finished.emit(event_id)
		return
	var group: Array[Node] = []
	for index in cards.size():
		var tile := _tile(str(cards[index]))
		tile.position = destination + Vector2(-index * 18.0, -22.0)
		tile.modulate.a = 0.0
		add_child(tile)
		_temporary.append(tile)
		group.append(tile)
	_active = create_tween()
	_active.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for index in group.size():
		_active.parallel().tween_property(group[index], "position", destination + Vector2(index * 6.0, 0), DEAL_DURATION)
		_active.parallel().tween_property(group[index], "modulate:a", 1.0, DEAL_DURATION)
	_active.tween_callback(func(): _finish_group(group, target, event_id))

func _play_draw(event: Dictionary, target: Callable, event_id: int) -> void:
	var tile := _tile(str(event.get("tile", "")))
	var from := Vector2(event.get("from", Vector2(1140, 650)))
	var to := Vector2(event.get("to", from))
	tile.position = from
	tile.modulate.a = 0.0
	add_child(tile)
	_temporary.append(tile)
	_active = create_tween()
	_active.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active.tween_property(tile, "position", to, DRAW_DURATION)
	_active.parallel().tween_property(tile, "modulate:a", 1.0, DRAW_DURATION)
	_active.tween_callback(func(): _finish(tile, target, event_id))

func _tile(card: String) -> TileView:
	var tile := TileView.new()
	tile.set_card(card, card != "")
	tile.set_unit(TILE_UNIT)
	return tile

func _finish(node: Node, target: Callable, event_id: int) -> void:
	if is_instance_valid(node): node.queue_free()
	_call_target(target)
	finished.emit(event_id)

func _finish_group(nodes: Array[Node], target: Callable, event_id: int) -> void:
	for node in nodes:
		if is_instance_valid(node): node.queue_free()
	_call_target(target)
	finished.emit(event_id)

func _call_target(target: Callable) -> void:
	if target.is_valid(): target.call()

func _clear_active() -> void:
	if _active != null:
		_active.kill()
		_active = null
	for node in _temporary:
		if is_instance_valid(node): node.queue_free()
	_temporary.clear()

func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
