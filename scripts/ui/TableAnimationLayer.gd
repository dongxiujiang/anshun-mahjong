extends Control
## Presentation only; owns temporary nodes and interruptible cubic easing.
signal finished(event_id: int)
signal discard_landed
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const DICE := preload("res://scripts/ui/DiceView.gd")

# 对象池实例（由 GameTable 注入）
var tile_pool = null
var _next_event_id := 0
var _active: Tween
var _temporary: Array[Node] = []
var _skip := false
var _speed_scale := 1.0
var _flight_tiles: Array[TileView] = []
var _discard_arrived := false
var _completion := Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_skip(value: bool) -> void:
	_skip = value
	if _skip: cancel()

func play(event: Dictionary, target: Callable = Callable()) -> int:
	cancel()
	_next_event_id += 1
	var event_id := _next_event_id
	_completion = target
	var type := str(event.get("type", ""))
	_speed_scale = float(event.get("speed_scale", GameConfig.animation_scale_for(type)))
	_discard_arrived = false
	# Instant discards can still leave an independently timed hand insertion.
	var hand_motion := type == "discard" and bool(event.get("discard_from_hand", false)) and _hand_duration(event) > 0.0
	if (_speed_scale <= 0.0 and not hand_motion) or DisplayServer.get_name() == "headless" or _skip:
		_finish(target, event_id)
		return event_id
	_active = create_tween().set_trans(Tween.TRANS_LINEAR)
	_active.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	match str(event.get("type", "")):
		"dice": _dice(event)
		"deal", "draw", "discard", "meld", "meld_reveal": _tiles(event)
		"sort_hand": _sort_hand(event)
		"win": _win(event)
		# 报听只保留动作/语音节奏，不在分数旁弹出文字。
		"ready": _active.tween_interval(_duration(0.24))
		_: _active.tween_interval(0.001)
	_active.tween_callback(func(): _finish(target, event_id))
	return event_id

func _duration(seconds: float) -> float:
	return seconds * _speed_scale

func _hand_duration(event: Dictionary) -> float:
	return UI.DISCARD_DURATION * float(event.get("hand_speed_scale", GameConfig.animation_scale_for("sort_hand")))

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
		die.value = (int(progress * 36) % 6 + 1) if progress < 1.0 else int(event.get("value", 1)), 0.0, 1.0, _duration(UI.DICE_DURATION))
	_active.tween_callback(func(): die.value = int(event.get("value", 1)))
	_active.tween_interval(_duration(GameConfig.OPENING_DICE_HOLD_SECONDS))

func _tiles(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	var destinations: Array = event.get("destinations", [])
	if destinations.is_empty() and not event.has("destinations"):
		destinations = [{"to": event.get("to", UI.LANDSCAPE_CENTER), "from": event.get("from", UI.LANDSCAPE_CENTER), "tile": event.get("tile", ""), "unit": UI.ANIMATION_TILE_UNIT, "rotation": 0.0}]
	var duration := _duration(UI.DEAL_DURATION) if type == "deal" else _duration(UI.REVEAL_DURATION if type == "meld_reveal" else (UI.DISCARD_DURATION if type == "discard" else (UI.MELD_DURATION if type == "meld" else UI.DRAW_DURATION)))
	var stagger := _duration(UI.DEAL_TILE_STAGGER) if type == "deal" else (_duration(UI.DRAW_TILE_STAGGER) if type == "draw" else (_duration(UI.DISCARD_TILE_STAGGER) if type == "discard" else _duration(UI.MELD_TILE_STAGGER)))
	var arc_height := UI.DEAL_ARC_HEIGHT if type == "deal" else (UI.DRAW_ARC_HEIGHT if type == "draw" else (UI.DISCARD_ARC_HEIGHT if type == "discard" else UI.MELD_ARC_HEIGHT))
	if type == "discard" and duration <= 0.0:
		_discard_arrived = true
		discard_landed.emit()
		destinations = []
	for index in destinations.size():
		var data: Dictionary = destinations[index]
		var tile: TileView = (tile_pool.acquire() if tile_pool else TileView.new())
		var card := str(data.get("tile", ""))
		tile.set_card(card, type != "draw" and card != "" and card != "hidden0")
		tile.set_unit(float(data.get("unit", UI.ANIMATION_TILE_UNIT)))
		var to := Vector2(data.get("to", UI.LANDSCAPE_CENTER))
		var from := Vector2(data.get("from", event.get("from", UI.LANDSCAPE_CENTER)))
		var final_rotation := float(data.get("rotation", 0.0))
		var start_rotation := float(data.get("from_rotation", event.get("from_rotation", final_rotation)))
		_add(tile)
		tile.position = from
		if type == "discard":
			_flight_tiles.append(tile)
			tile.visible = not bool(event.get("claimed", false))
			tile.set_meta("charge_chicken", bool(event.get("charge", false)))
		if type == "meld_reveal":
			tile.position = to
			tile.rotation = final_rotation
			tile.set_card(card, false)
			tile.pivot_offset = tile.size / 2.0
			_active.parallel().tween_property(tile, "scale:x", 0.05, duration / 2.0)
		else:
			var start_scale: float = float(event.get("from_unit", tile.unit)) / tile.unit if type == "discard" and tile.unit > 0.0 else 0.78
			tile.scale = Vector2.ONE * start_scale
			tile.rotation = start_rotation
			var delay := stagger * float(index)
			var flight_duration := duration + delay
			var apex := from.lerp(to, 0.5) + Vector2(0, -arc_height)
			var motion := func(progress: float):
				var elapsed := progress * flight_duration
				var local := clampf((elapsed - delay) / duration, 0.0, 1.0)
				if local <= 0.0:
					tile.position = from
					tile.rotation = start_rotation
					tile.scale = Vector2.ONE * start_scale
					return
				var eased := _smoothstep(local)
				tile.position = _quad_bezier(from, apex, to, eased)
				tile.rotation = lerp_angle(start_rotation, final_rotation, eased)
				var settle := 0.0
				if local > 0.82:
					settle = _smoothstep((local - 0.82) / 0.18)
					tile.position = tile.position.lerp(to, settle) + Vector2(0, -sin(settle * PI) * UI.TILE_SETTLE_LIFT)
				var bounce := 1.0 + sin(settle * PI) * (UI.TILE_SETTLE_SCALE - 1.0)
				tile.scale = Vector2.ONE * lerpf(start_scale, 1.0, eased) * bounce
				if type == "discard" and local >= 1.0 and not _discard_arrived:
					_discard_arrived = true
					hide_discard_flight()
					discard_landed.emit()
			_active.parallel().tween_method(motion, 0.0, 1.0, flight_duration)
	if type == "draw":
		# Arrive face down, flip in place, then leave a brief readable pause.
		for tile in _temporary:
			if tile is TileView and tile.tile not in ["", "hidden0"]:
				tile.pivot_offset = tile.size / 2.0
				_active.tween_property(tile, "scale:x", 0.05, _duration(0.09))
				_active.tween_callback(func(): tile.set_card(tile.tile, true))
				_active.tween_property(tile, "scale:x", 1.0, _duration(0.09))
		_active.tween_interval(_duration(0.12))
	if type == "meld_reveal":
		_active.tween_callback(func():
			for tile in _temporary:
				if tile is TileView: tile.set_card(tile.tile, true))
		for tile in _temporary:
			_active.parallel().tween_property(tile, "scale:x", 1.0, duration / 2.0)
	if type == "meld": _badge("碰" if event.get("kind", "") == "pung" else "杠", event, duration)
	if type == "discard" and bool(event.get("discard_from_hand", false)):
		_hand_motion(event, duration)

func _sort_hand(event: Dictionary) -> void:
	# Move the persistent hand nodes themselves.  The opening hand is already
	# visible in deal order; moving these nodes gives the player a real
	# interleaving/sort pass without a masked duplicate row underneath.
	# Opening timing is shared across clients, just like dice and deal packets.
	var duration := _duration(UI.SORT_DURATION)
	var destinations: Array = event.get("destinations", [])
	for index in destinations.size():
		var data: Dictionary = destinations[index]
		var tile = data.get("node")
		if not is_instance_valid(tile) or not (tile is TileView): continue
		var from: Vector2 = tile.position
		var to := Vector2(data.get("to", from))
		var start_rotation := float(tile.rotation)
		var final_rotation := float(data.get("rotation", start_rotation))
		var delay := _duration(float(data.get("delay", UI.SORT_TILE_STAGGER * float(index))))
		var flight_duration := duration + delay
		var apex := from.lerp(to, 0.5) + Vector2(0, -UI.SORT_ARC_HEIGHT)
		var motion := func(progress: float):
			var elapsed := progress * flight_duration
			var local := clampf((elapsed - delay) / duration, 0.0, 1.0)
			if local <= 0.0:
				tile.position = from
				tile.rotation = start_rotation
				return
			var eased := _smoothstep(local)
			tile.position = _quad_bezier(from, apex, to, eased)
			tile.rotation = lerp_angle(start_rotation, final_rotation, eased)
		_active.parallel().tween_method(motion, 0.0, 1.0, flight_duration)

func _hand_motion(event: Dictionary, flight_duration: float) -> void:
	# During a hand discard the authoritative refresh is held. The discarded
	# slot stays visibly empty while the remaining row shifts horizontally; only
	# after that gap is ready does the drawn tile slide in from the draw slot.
	var move_required := bool(event.get("hand_move_required", false))
	var duration := _hand_duration(event)
	var move_start := flight_duration
	var insert_start := flight_duration + (duration if move_required else 0.0)
	var total_duration := maxf(flight_duration + duration, insert_start + duration if not event.get("hand_insert", {}).is_empty() else 0.0)
	for data in event.get("hand_moves", []):
		var persistent_node = data.get("node")
		var persistent := is_instance_valid(persistent_node) and persistent_node is TileView
		var tile: TileView
		if persistent:
			tile = persistent_node
			tile.set_interactive(false)
		else:
			tile = (tile_pool.acquire() if tile_pool else TileView.new())
			var card := str(data.get("tile", ""))
			tile.set_card(card, card != "" and card != "hidden0")
			tile.set_unit(float(data.get("unit", UI.ANIMATION_TILE_UNIT)))
			_add(tile)
			# Keep the fallback safe for snapshots that arrived without a live node.
			tile.set_table_position(Vector2(data.get("from", UI.LANDSCAPE_CENTER)))
			tile.rotation = float(data.get("rotation", 0.0))
		var move_from := Vector2(data.get("from", UI.LANDSCAPE_CENTER))
		var move_to := Vector2(data.get("to", move_from))
		var layer_transform := get_global_transform()
		var from_global := layer_transform * move_from
		if persistent:
			tile.global_position = from_global
		var motion := func(progress: float):
			var elapsed := progress * total_duration
			var local := (clampf((elapsed - move_start) / duration, 0.0, 1.0) if duration > 0.0 else float(elapsed >= move_start)) if move_required else 0.0
			var eased := _smoothstep(local)
			# This is a table-plane translation. For side seats the parent rotation
			# turns it vertical on screen, while each player's own row still moves
			# horizontally along the hand.
			if persistent:
				if is_instance_valid(tile): tile.global_position = get_global_transform() * move_from.lerp(move_to, eased)
			else:
				tile.position = move_from.lerp(move_to, eased)
		_active.parallel().tween_method(motion, 0.0, 1.0, total_duration)
	if not event.get("hand_insert", {}).is_empty():
		var data: Dictionary = event.get("hand_insert", {})
		var tile: TileView = (tile_pool.acquire() if tile_pool else TileView.new())
		var card := str(data.get("tile", ""))
		tile.set_card(card, card != "" and card != "hidden0")
		tile.set_unit(float(data.get("unit", UI.ANIMATION_TILE_UNIT)))
		var initial_scale := (float(data.get("from_unit", tile.unit)) / tile.unit if tile.unit > 0.0 else 1.0) * 0.9
		tile.scale = Vector2.ONE * initial_scale
		_add(tile)
		# As above, set the captured draw-slot position after the node enters the
		# tree so TileView._ready() cannot overwrite it with (0, 0).
		tile.set_table_position(Vector2(data.get("from", UI.LANDSCAPE_CENTER)))
		tile.rotation = float(data.get("rotation", 0.0))
		var insert_from: Vector2 = tile.position
		var insert_to := Vector2(data.get("to", tile.position))
		# Keep the whole discard effect continuous while delaying the insert until
		# the row has moved out of the way (when a new gap is required).
		var source_node = data.get("source_node")
		var has_source := is_instance_valid(source_node) and source_node is TileView
		if has_source:
			tile.modulate.a = 0.0
		var motion := func(progress: float):
			var elapsed := progress * total_duration
			var local := clampf((elapsed - insert_start) / duration, 0.0, 1.0) if duration > 0.0 else float(elapsed >= insert_start)
			var eased := _smoothstep(local)
			if has_source and is_instance_valid(source_node) and elapsed >= insert_start:
				source_node.visible = false
			tile.modulate.a = eased if has_source else 1.0
			tile.position = insert_from.lerp(insert_to, eased) + Vector2(0, -sin(eased * PI) * 1.5)
			tile.scale = Vector2.ONE * lerpf(initial_scale, 1.0, eased)
		_active.parallel().tween_method(motion, 0.0, 1.0, total_duration)

func _smoothstep(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _quad_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c

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
	_completion = Callable()
	if target.is_valid(): target.call()
	finished.emit(event_id)

func finish_now() -> void:
	var callback := _completion
	cancel()
	if callback.is_valid(): callback.call()

func discard_position(fallback: Vector2) -> Vector2:
	return _flight_tiles[0].position if not _flight_tiles.is_empty() and is_instance_valid(_flight_tiles[0]) else fallback

func hide_discard_flight() -> void:
	for tile in _flight_tiles:
		if is_instance_valid(tile): tile.hide()

func cancel() -> void:
	_completion = Callable()
	if _active != null:
		_active.kill()
		_active = null
	_clear_nodes()

func _clear_nodes() -> void:
	for node in _temporary:
		if is_instance_valid(node):
			remove_child(node)
			# 使用对象池回收 TileView
			if tile_pool and node is TileView:
				tile_pool.release(node)
			else:
				node.queue_free()
	_temporary.clear()
	_flight_tiles.clear()

func _exit_tree() -> void:
	cancel()
