extends "res://scripts/ui/table/TableComponent.gd"
## 胡牌后的结算预览。只负责把已经完成的账本逐阶段展示，不能修改 RoundState。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var layer: Control
var _flip_view: TileView
var _zero_labels: Array[Label] = []
var _active := false
var _completed := false
var _cancelled := false
var _current_scores: Array = [0.0, 0.0, 0.0, 0.0]
var _target_scores: Array = [0.0, 0.0, 0.0, 0.0]
var _score_tween: Tween

func build() -> void:
	layer = table._box(table.surface)
	layer.name = "SettlementAnimationLayer"
	layer.size = UI.DESIGN_SIZE
	layer.z_index = 200
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func reset() -> void:
	_cancelled = true
	if _score_tween != null:
		_score_tween.kill()
	_score_tween = null
	_active = false
	_completed = false
	_clear_visuals()

func is_active() -> bool:
	return _active

func has_started() -> bool:
	return _active or _completed

func is_completed() -> bool:
	return _completed

func start() -> void:
	if _active or _completed or table.round == null or table.round.phase != RoundState.Phase.SETTLED:
		return
	_active = true
	_completed = false
	_cancelled = false
	# Lock every action immediately, before the first deferred visual stage.
	table._update_interactivity()
	_current_scores = []
	_target_scores = []
	var result: Dictionary = table.round.last_result
	var deltas: Array = result.get("deltas", table.round._last_deltas)
	for seat in 4:
		var final_score := float(table.round.players[seat].score)
		_target_scores.append(final_score)
		_current_scores.append(final_score - float(deltas[seat] if seat < deltas.size() else 0.0))
	for seat in 4:
		_set_score_display(seat, _current_scores[seat], UI.INK)
		_set_net_display(seat, "", UI.INK, false)
	_run_sequence.call_deferred()

func skip() -> void:
	if not _active:
		return
	_cancelled = true
	if _score_tween != null:
		_score_tween.kill()
	_score_tween = null
	var deltas: Array = table.round.last_result.get("deltas", table.round._last_deltas)
	for seat in 4:
		_current_scores[seat] = _target_scores[seat]
		_set_score_display(seat, _target_scores[seat], UI.INK)
		var delta := float(deltas[seat] if seat < deltas.size() else 0.0)
		_set_net_display(seat, _signed(delta), _net_color(delta), true)
	_finish_sequence()

func _run_sequence() -> void:
	_show_zero_labels()
	await _stage_flip()
	if not _active: return
	await _run_score_stage(_stage_flip_amounts(), _stage_flip_highlights())
	if not _active: return
	await _run_score_stage(_stage_chicken_amounts(), _stage_chicken_highlights())
	if not _active: return
	await _run_score_stage(_stage_kong_amounts(), Callable())
	if not _active: return
	await _run_score_stage(_stage_win_amounts(), Callable())
	if not _active: return
	await _stage_pairwise()
	if not _active: return
	_finish_sequence()

func _stage_flip() -> void:
	var flip := str(table.round.round_meta.get("flip_tile", ""))
	if flip == "":
		await _pause(0.16)
		return
	_flip_view = table._make_tile(flip, false, table._hand_tile_unit(table.human_seat))
	_flip_view.name = "SettlementFlipTile"
	_flip_view.pivot_offset = _flip_view.size / 2.0
	_flip_view.position = table._table_center() - _flip_view.size / 2.0
	layer.add_child(_flip_view)
	if DisplayServer.get_name() == "headless":
		_flip_view.set_card(flip, true)
		return
	var duration := _duration(0.38)
	_score_tween = table.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_score_tween.tween_property(_flip_view, "scale:x", 0.04, duration / 2.0)
	_score_tween.tween_callback(func():
		if is_instance_valid(_flip_view):
			_flip_view.set_card(flip, true))
	_score_tween.tween_property(_flip_view, "scale:x", 1.0, duration / 2.0)
	_score_tween.tween_interval(_duration(0.18))
	await _score_tween.finished
	_score_tween = null

func _show_zero_labels() -> void:
	_clear_zero_labels()
	for seat in 4:
		if not table.discard_scroll.has(seat): continue
		var river: Control = table.discard_scroll[seat]
		var global_center := river.get_global_transform() * (river.size / 2.0)
		var local_center: Vector2 = table.surface.get_global_transform().affine_inverse() * global_center
		var label := Label.new()
		label.name = "SettlementZero%d" % seat
		label.text = "0"
		label.size = Vector2(92, 62)
		label.position = local_center - label.size / 2.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", TileView._font())
		label.add_theme_font_size_override("font_size", 42)
		label.add_theme_color_override("font_color", UI.INK)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		label.add_theme_constant_override("shadow_offset_y", 3)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(label)
		_zero_labels.append(label)

func _stage_flip_highlights() -> Callable:
	var flip := str(table.round.round_meta.get("flip_tile", ""))
	var related: Array = Tiles.flip_related(flip)
	return func(): _highlight_matching(func(tile: String): return tile in related)

func _stage_chicken_highlights() -> Callable:
	return func():
		_clear_tile_highlights()
		var related: Array = Tiles.flip_related(str(table.round.round_meta.get("flip_tile", "")))
		for seat in 4:
			if not _seat_is_called(seat): continue
			_highlight_seat_matching(seat, func(tile: String): return Tiles.is_chicken(tile) and tile not in related)

func _stage_flip_amounts() -> Array:
	var amounts := [0.0, 0.0, 0.0, 0.0]
	var related: Array = Tiles.flip_related(str(table.round.round_meta.get("flip_tile", "")))
	for seat in 4:
		for item in _items_for(seat):
			var kind := str(item.get("kind", ""))
			if kind == "flip" or (kind in ["chicken", "charge"] and str(item.get("source", "")) != "kong" and _item_has_related_tile(item, related)):
				amounts[seat] += maxf(0.0, float(item.get("amount", 0.0)))
	return amounts

func _stage_chicken_amounts() -> Array:
	var amounts := [0.0, 0.0, 0.0, 0.0]
	var related: Array = Tiles.flip_related(str(table.round.round_meta.get("flip_tile", "")))
	for seat in 4:
		for item in _items_for(seat):
			var kind := str(item.get("kind", ""))
			if kind in ["chicken", "charge"] and str(item.get("source", "")) != "kong" and not _item_has_related_tile(item, related):
				amounts[seat] += maxf(0.0, float(item.get("amount", 0.0)))
	return amounts

func _stage_kong_amounts() -> Array:
	var amounts := [0.0, 0.0, 0.0, 0.0]
	for seat in 4:
		for item in _items_for(seat):
			if str(item.get("kind", "")) != "kong": continue
			if int(item.get("kong_kind", RoundState.KongKind.NONE)) == RoundState.KongKind.EXPOSED: continue
			amounts[seat] += maxf(0.0, float(item.get("amount", 0.0)))
	return amounts

func _stage_win_amounts() -> Array:
	var amounts := [0.0, 0.0, 0.0, 0.0]
	var winners: Array = table.round.round_meta.get("winners", [])
	if winners.is_empty() and int(table.round.round_meta.get("winner", -1)) >= 0:
		winners = [int(table.round.round_meta.get("winner", -1))]
	for seat in winners:
		if seat not in range(4): continue
		for item in _items_for(int(seat)):
			var kind := str(item.get("kind", ""))
			if kind in ["flip", "chicken", "charge", "kong", "penalty"]: continue
			amounts[int(seat)] += maxf(0.0, float(item.get("amount", 0.0)))
	return amounts

func _run_score_stage(amounts: Array, highlight: Callable) -> void:
	_clear_tile_highlights()
	if highlight.is_valid(): highlight.call()
	await _animate_score_additions(amounts)
	await _pause(0.12)

func _animate_score_additions(amounts: Array) -> void:
	var changed := false
	for seat in 4:
		var amount := float(amounts[seat] if seat < amounts.size() else 0.0)
		if amount > 0.0: changed = true
		_current_scores[seat] += amount
	if not changed:
		await _pause(0.10)
		return
	if DisplayServer.get_name() == "headless":
		for seat in 4: _set_score_display(seat, _current_scores[seat], UI.INK)
		return
	var ends := _current_scores.duplicate()
	var starts := []
	for seat in 4:
		starts.append(float(ends[seat]) - float(amounts[seat] if seat < amounts.size() else 0.0))
	_score_tween = table.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for seat in 4:
		var seat_index := seat
		var from := float(starts[seat])
		var to := float(ends[seat])
		_score_tween.parallel().tween_method(func(value: float): _set_score_display(seat_index, value, UI.INK), from, to, _duration(0.32))
	await _score_tween.finished
	_score_tween = null

func _stage_pairwise() -> void:
	_clear_tile_highlights()
	var deltas: Array = table.round.last_result.get("deltas", table.round._last_deltas)
	for seat in 4:
		var delta := float(deltas[seat] if seat < deltas.size() else 0.0)
		_set_net_display(seat, _signed(delta), _net_color(delta), true)
	if DisplayServer.get_name() == "headless":
		for seat in 4: _set_score_display(seat, _target_scores[seat], UI.INK)
		_current_scores = _target_scores.duplicate()
		return
	var starts := _current_scores.duplicate()
	_score_tween = table.create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	for seat in 4:
		var seat_index := seat
		var delta := float(deltas[seat] if seat < deltas.size() else 0.0)
		var color := _net_color(delta)
		_score_tween.parallel().tween_method(func(value: float): _set_score_display(seat_index, value, color), float(starts[seat]), _target_scores[seat], _score_duration_for_delta(delta))
	await _score_tween.finished
	_score_tween = null
	_current_scores = _target_scores.duplicate()
	for seat in 4: _set_score_display(seat, _target_scores[seat], UI.INK)

func _score_duration_for_delta(delta: float) -> float:
	return _duration(clampf(0.16 + absf(delta) * 0.006, 0.18, 0.72))

func _highlight_matching(predicate: Callable) -> void:
	for seat in 4:
		_highlight_seat_matching(seat, predicate)

func _highlight_seat_matching(seat: int, predicate: Callable) -> void:
	if seat < 0 or seat >= table.round.players.size(): return
	var player: PlayerState = table.round.players[seat]
	for tile in _tiles_in(table.hand_box.get(seat)):
		var index := int(tile.get_meta("concealed_index", -1))
		var value := str(player.concealed[index]) if index in range(player.concealed.size()) else tile.tile
		tile.set_score_highlight(predicate.call(value))
	for tile in _tiles_in(table.draw_box.get(seat)):
		var value := str(player.just_drew)
		tile.set_score_highlight(predicate.call(value))

func _clear_tile_highlights() -> void:
	for seat in 4:
		for tile in _tiles_in(table.hand_box.get(seat)) + _tiles_in(table.draw_box.get(seat)):
			tile.set_score_highlight(false)

func _tiles_in(node: Node) -> Array[TileView]:
	var result: Array[TileView] = []
	if node == null: return result
	for child in node.get_children():
		if child is TileView: result.append(child)
		else: result.append_array(_tiles_in(child))
	return result

func _item_has_related_tile(item: Dictionary, related: Array) -> bool:
	if related.is_empty(): return false
	var tiles: Array = item.get("tiles", [])
	if tiles.is_empty() and str(item.get("tile", "")) != "":
		tiles = [str(item.get("tile", ""))]
	for tile in tiles:
		if str(tile) in related: return true
	return false

func _items_for(seat: int) -> Array:
	var items: Array = table.round.last_result.get("items", table.round._last_items)
	return items[seat] if seat >= 0 and seat < items.size() else []

func _seat_is_called(seat: int) -> bool:
	var called: Array = table.round.last_result.get("called", [])
	return bool(called[seat]) if seat >= 0 and seat < called.size() else ScoringEngine.is_called(table.round, seat)

func _set_score_display(seat: int, value: float, color: Color) -> void:
	if not table.center_labels.has(seat): return
	var label: Label = table.center_labels[seat]
	label.text = "%.0f分" % round(value)
	label.add_theme_color_override("font_color", color)

func _set_net_display(seat: int, text: String, color: Color, visible: bool) -> void:
	if not table.net_labels.has(seat): return
	var label: Label = table.net_labels[seat]
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.visible = visible and text != ""

func _signed(value: float) -> String:
	return "%+.0f" % value if not is_zero_approx(value) else "0"

func _net_color(value: float) -> Color:
	return UI.SCORE_GAIN if value > 0.0 else (UI.SCORE_LOSS if value < 0.0 else UI.INK)

func _duration(seconds: float) -> float:
	return GameConfig.animation_duration(seconds)

func _pause(seconds: float) -> void:
	if DisplayServer.get_name() == "headless": return
	await table.get_tree().create_timer(_duration(seconds)).timeout

func _finish_sequence() -> void:
	if not _active: return
	_active = false
	_completed = true
	if _score_tween != null:
		_score_tween.kill()
	_score_tween = null
	_clear_zero_labels()
	_clear_tile_highlights()
	if is_instance_valid(table):
		table._on_settlement_animation_finished()

func _clear_zero_labels() -> void:
	for label in _zero_labels:
		if is_instance_valid(label): label.queue_free()
	_zero_labels.clear()

func _clear_visuals() -> void:
	_clear_zero_labels()
	if is_instance_valid(table):
		_clear_tile_highlights()
	if is_instance_valid(_flip_view):
		_flip_view.queue_free()
	_flip_view = null
	if is_instance_valid(table):
		for seat in 4:
			if table.net_labels.has(seat): table.net_labels[seat].hide()
