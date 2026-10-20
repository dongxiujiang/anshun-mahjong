extends "res://scripts/ui/table/TableComponent.gd"
## 只呈现已完成的账本。一个可取消的 Tween 持有整个时间线，没有遗留 Timer/await。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const PLAN := preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
const ANNOTATIONS := preload("res://scripts/ui/table/SettlementScoreAnnotations.gd")

var layer: Control
var boards: Dictionary = {}
## 数组始终按该座位自己的 [上、对、下] 索引，布局顺序另行处理。
var payment_labels: Dictionary = {}
var identity_labels: Dictionary = {}
var score_annotations
var current_pairs: Array = []
var plan: Dictionary = {}
var _flip_view: TileView
var _skip_button: Button
var _notice: Label
var _burn_badge: Label
var _particles: Array = []
var _tween: Tween
var _active := false
var _completed := false
var _rivers_hidden := false
var _river_alpha := 1.0
var _stage_key := ""
var _target_scores: Array = []
var _start_scores: Array = []
var _display_scores: Array = []
var _display_colors: Array = []
var _net_visible := false
var _count_duration := 0.0
var _flip_tile := ""

func build() -> void:
	layer = table._box(table.surface)
	layer.name = "SettlementAnimationLayer"
	layer.size = UI.DESIGN_SIZE
	layer.z_index = 200
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_button = table._button("跳过动画", skip, Vector2(228, 72))
	_skip_button.name = "SkipSettlementAnimation"
	_skip_button.add_theme_font_size_override("font_size", 30)
	layer.add_child(_skip_button)
	_skip_button.hide()
	score_annotations = ANNOTATIONS.new(table)
	layer.add_child(score_annotations)
	refresh_layout()

func reset() -> void:
	_kill_timeline()
	if is_instance_valid(score_annotations): score_annotations.reset()
	AudioManager.stop_settlement_cue(table)
	_clear_tile_highlights()
	_active = false
	_completed = false
	_stage_key = ""
	_net_visible = false
	_rivers_hidden = false
	_set_river_alpha(1.0)
	_clear_particles()
	for board in boards.values(): _remove_visual(board)
	boards.clear()
	payment_labels.clear()
	for label in identity_labels.values(): _remove_visual(label)
	identity_labels.clear()
	for node in [_flip_view, _notice, _burn_badge]: _remove_visual(node)
	_flip_view = null
	_notice = null
	_burn_badge = null
	plan.clear()
	current_pairs.clear()
	if is_instance_valid(_skip_button): _skip_button.hide()
	if is_instance_valid(table):
		for label in table.net_labels.values():
			label.hide()
			label.modulate = Color.WHITE
		for label in table.center_labels.values(): label.add_theme_color_override("font_color", Color.WHITE)

func is_active() -> bool:
	return _active

func has_started() -> bool:
	return _active or _completed

func is_completed() -> bool:
	return _completed

func start(immediate: bool = false) -> void:
	if not _prepare(): return
	if immediate or DisplayServer.get_name() == "headless" or (GameConfig.settlement_speed == "instant" and not plan.all_called_draw):
		skip()
	else:
		_play()

func _prepare() -> bool:
	if has_started() or table.round == null or table.round.phase != RoundState.Phase.SETTLED or table.round.players.size() != 4:
		return false
	plan = PLAN.build(table.round.last_result, table.round.round_meta, table.round.players, table.human_seat)
	score_annotations.configure(table.round.last_result, table.round.round_meta, table.round.players, plan)
	_active = true
	_completed = false
	_stage_key = ""
	_net_visible = false
	_start_scores.clear()
	_target_scores.clear()
	_display_colors = [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
	for seat in 4:
		var score := float(table.round.players[seat].score)
		_target_scores.append(score)
		_start_scores.append(score - float(plan.deltas[seat]))
	_display_scores = _start_scores.duplicate()
	current_pairs = ScoringEngine.pairwise_payments([])
	_flip_tile = "" if plan.is_draw else str(table.round.round_meta.get("flip_tile", ""))
	table._clear_actions()
	table._settlement_card.hide_post_settlement_controls()
	table._update_interactivity()
	_build_identities()
	if plan.all_called_draw:
		_notice = _text(layer, "黄牌，下局鸡分 × 2", 34, UI.GOLD)
		_notice.name = "AllCalledDrawNotice"
		_notice.size = Vector2(1000, 70)
		_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		_build_boards()
		_create_flip()
		_skip_button.show()
	refresh_layout()
	apply_displays()
	return true

func _play() -> void:
	_kill_timeline()
	_tween = table.create_tween()
	if plan.all_called_draw:
		# 提示属于终局控制，不播放分拍、翻鸡或翻手牌。
		_tween.tween_interval(1.5)
		_tween.tween_callback(_finish_all_called)
		return
	_tween.tween_method(_set_river_alpha, 1.0, 0.0, UI.SETTLEMENT_FADE_SECONDS)
	_tween.tween_callback(func(): _rivers_hidden = true)
	if is_instance_valid(_flip_view):
		_tween.tween_callback(func(): _flip_view.show())
		_tween.tween_property(_flip_view, "scale:x", 0.02, UI.SETTLEMENT_FLIP_SECONDS / 2.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_tween.tween_callback(func(): _flip_view.set_card(_flip_tile, true))
		_tween.tween_property(_flip_view, "scale:x", 1.0, UI.SETTLEMENT_FLIP_SECONDS / 2.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var cumulative := current_pairs.duplicate(true)
	for stage in plan.stages:
		var before := cumulative.duplicate(true)
		var after := _add_matrix(before, stage.matrix)
		cumulative = after.duplicate(true)
		if not _matrix_changed(stage.matrix):
			_tween.tween_interval(0.24)
			continue
		_tween.tween_callback(_begin_stage.bind(str(stage.key)))
		_tween.tween_interval(UI.SETTLEMENT_HIGHLIGHT_SECONDS)
		_tween.tween_interval(UI.SETTLEMENT_PAUSE_SECONDS)
		_tween.tween_method(_roll_pairs.bind(before, after), 0.0, 1.0, UI.SETTLEMENT_ROLL_SECONDS)
		_tween.tween_interval(UI.SETTLEMENT_PAUSE_SECONDS)
		_tween.tween_callback(_end_stage)
	_count_duration = UI.SETTLEMENT_PARTICLE_SECONDS
	for delta in plan.deltas: _count_duration = maxf(_count_duration, _score_duration_for_delta(float(delta)))
	_tween.tween_callback(_begin_final)
	_tween.tween_method(_roll_final, 0.0, 1.0, _count_duration)
	_tween.tween_callback(_complete)
	update_speed()

func update_speed() -> void:
	if not _active or plan.all_called_draw: return
	if GameConfig.settlement_speed == "instant":
		skip()
	elif _tween != null and _tween.is_valid():
		# 更改速度只调整同一条时间线，不重播任何计分拍或重建累计分。
		_tween.set_speed_scale(1.0 / GameConfig.settlement_duration(1.0))

func skip() -> void:
	if not _active: return
	_kill_timeline()
	AudioManager.stop_settlement_cue(table)
	_complete()

func _complete() -> void:
	if not _active: return
	current_pairs = plan.final.duplicate(true)
	_display_scores = _target_scores.duplicate()
	_display_colors = [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
	_net_visible = not plan.all_called_draw
	_stage_key = ""
	_clear_tile_highlights()
	_clear_particles()
	if not plan.all_called_draw:
		_rivers_hidden = true
		_set_river_alpha(0.0)
	if is_instance_valid(_flip_view):
		_flip_view.set_card(_flip_tile, true)
		_flip_view.scale = Vector2.ONE
		_flip_view.show()
	_skip_button.hide()
	_active = false
	_completed = true
	# kill() also handles a skip during a callback; no deferred stage can reappear.
	_kill_timeline()
	apply_displays()
	score_annotations.finish()
	table._on_settlement_animation_finished()

func _finish_all_called() -> void:
	_remove_visual(_notice)
	_notice = null
	_complete()
	if table._net_mode() == "": table._next_round()

func _build_boards() -> void:
	for seat in 4:
		var board := Control.new()
		board.name = "SettlementScoreboard%d" % seat
		board.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(board)
		boards[seat] = board
		var labels: Array[Label] = []
		for index in 3:
			var row := Control.new()
			row.name = "RelativePayment%d" % index
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.size = UI.SETTLEMENT_PAYMENT_ROW_SIZE
			board.add_child(row)
			var tag := _text(row, ["上", "对", "下"][index], UI.SETTLEMENT_DIRECTION_FONT_SIZE, UI.MUTED)
			tag.name = "Direction"
			tag.size = Vector2(30, 52)
			var value := _text(row, "0", UI.SETTLEMENT_PAYMENT_FONT_SIZE, UI.MUTED)
			value.name = "Amount"
			value.position = Vector2(32, 0)
			value.size = Vector2(row.size.x - 32, row.size.y)
			labels.append(value)
		payment_labels[seat] = labels
	if int(plan.burned) in range(4):
		_burn_badge = _text(layer, "烧鸡", 22, UI.SCORE_LOSS)
		_burn_badge.name = "BurnedChickenBadge"
		_burn_badge.size = Vector2(90, 34)
		_burn_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_identities() -> void:
	for seat in 4:
		var identity: Dictionary = plan.identities[seat]
		var caption := str(identity.title)
		var font_size := UI.SETTLEMENT_IDENTITY_FONT_SIZE
		while font_size > 18 and TileView._font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > UI.SETTLEMENT_IDENTITY_SIZE.x:
			font_size -= 1
		var line := ""
		for detail in str(identity.detail).split(" · ", false):
			var next := detail if line == "" else line + " · " + detail
			if line != "" and TileView._font().get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > UI.SETTLEMENT_IDENTITY_SIZE.x:
				caption += "\n" + line
				line = detail
			else:
				line = next
		if line != "": caption += "\n" + line
		var color: Color = UI.GOLD if identity.winner else (UI.MUTED if identity.called else UI.SCORE_LOSS)
		var label := _text(layer, caption, UI.SETTLEMENT_IDENTITY_FONT_SIZE, color)
		label.name = "SettlementIdentity%d" % seat
		label.size = UI.SETTLEMENT_IDENTITY_SIZE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		while font_size > 18 and TileView._font().get_multiline_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
			font_size -= 1
		label.add_theme_font_size_override("font_size", font_size)
		label.size.y = maxf(label.size.y, TileView._font().get_multiline_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).y)
		identity_labels[seat] = label

func _create_flip() -> void:
	if _flip_tile == "": return
	_flip_view = table._make_tile(_flip_tile, false, table._hand_tile_unit(table.human_seat))
	_flip_view.name = "SettlementFlipTile"
	_flip_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flip_view.pivot_offset = _flip_view.size / 2.0
	layer.add_child(_flip_view)
	_flip_view.hide()

func refresh_layout() -> void:
	if not is_instance_valid(layer): return
	layer.size = UI.DESIGN_SIZE
	_skip_button.position = Vector2(UI.DESIGN_SIZE.x - UI.SETTINGS_BUTTON_SIZE.x - 272, UI.SETTINGS_TOP_GAP)
	for seat in identity_labels:
		var score: Label = table.center_labels[seat]
		var label: Label = identity_labels[seat]
		label.position = score.position + Vector2((score.size.x - label.size.x) / 2.0, score.size.y + 6.0)
	for seat in boards:
		var relative: int = table._relative_seat(seat)
		var board: Control = boards[seat]
		var vertical := relative % 2 == 1
		var row_size: Vector2 = UI.SETTLEMENT_PAYMENT_ROW_SIZE
		var gap: float = UI.SETTLEMENT_PAYMENT_VERTICAL_GAP if vertical else UI.SETTLEMENT_PAYMENT_GAP
		board.size = Vector2(row_size.x, row_size.y * 3 + gap * 2) if vertical else Vector2(row_size.x * 3 + gap * 2, row_size.y)
		var river: Control = table.discard_scroll[seat]
		var center: Vector2 = layer.get_global_transform().affine_inverse() * (river.get_global_transform() * (river.size / 2.0))
		if vertical:
			# 两侧恢复竖排，保留桌心外侧的留白，避开累计分与身份说明。
			center = table._table_center() + Vector2(UI.SETTLEMENT_SIDE_BOARD_OFFSET * (1 if relative == 1 else -1), 0)
		board.position = center - board.size / 2.0
		var order := [2, 1, 0] if relative in [1, 2] else [0, 1, 2]
		for slot in 3:
			var row: Control = payment_labels[seat][order[slot]].get_parent()
			row.position = Vector2(0, slot * (row_size.y + gap)) if vertical else Vector2(slot * (row_size.x + gap), 0)
	if is_instance_valid(_flip_view): _flip_view.position = table._table_center() - _flip_view.size / 2.0
	if is_instance_valid(_notice): _notice.position = table._table_center() - _notice.size / 2.0
	if is_instance_valid(_burn_badge) and boards.has(int(plan.burned)):
		var board: Control = boards[int(plan.burned)]
		_burn_badge.position = board.position + Vector2((board.size.x - _burn_badge.size.x) / 2.0, -38)
	if is_instance_valid(score_annotations): score_annotations.refresh()

func apply_displays() -> void:
	if not has_started() or _display_scores.size() != 4: return
	refresh_layout()
	_render_pairs()
	for seat in 4:
		var label: Label = table.center_labels[seat]
		label.text = "%.0f分" % float(_display_scores[seat])
		label.add_theme_color_override("font_color", _display_colors[seat])
		var width := TileView._font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		var delta := float(plan.deltas[seat])
		var net: Label = table.net_labels[seat]
		net.position = label.position + Vector2((label.size.x + width) / 2.0 + 8.0, 0)
		net.text = _signed(delta)
		net.add_theme_color_override("font_color", _net_color(delta))
		net.visible = _net_visible
		if _net_visible: table.dealer_badges[seat].hide()
		if _completed: net.modulate = Color.WHITE
	if _rivers_hidden: _set_river_alpha(0.0)
	if _active and _stage_key != "": _highlight_stage(_stage_key)

func _set_river_alpha(value: float) -> void:
	_river_alpha = value
	if not is_instance_valid(table): return
	for river in table.discard_scroll.values():
		if river.get_child_count() > 0:
			var content: Control = river.get_child(0)
			content.modulate.a = value
			content.visible = value > 0.0

func _begin_stage(key: String) -> void:
	_stage_key = key
	_highlight_stage(key)
	score_annotations.show_stage(key)
	AudioManager.play_settlement_cue(key, table)

func _end_stage() -> void:
	_stage_key = ""
	_clear_tile_highlights()
	score_annotations.show_stage("")

func _highlight_stage(key: String) -> void:
	_clear_tile_highlights()
	if key in ["kong", "other"]:
		for group in score_annotations.groups:
			var seat := int(group.seat)
			if group.area != "meld" or not group.stages.has(key) or seat == int(plan.burned) or not bool(plan.called[seat]): continue
			if float(group.stages[key].amount) <= 0.0: continue
			for tile in score_annotations._tiles_for(group): tile.set_score_highlight(true)
		return
	if plan.is_draw or key not in ["flip", "chicken"]: return
	var called: Array = plan.get("called", [false, false, false, false])
	for seat in 4:
		if seat == int(plan.burned) or seat >= called.size() or not bool(called[seat]): continue
		for box in [table.hand_box.get(seat), table.draw_box.get(seat), table.meld_box.get(seat), table.chicken_box.get(seat)]:
			for tile in _tiles_in(box):
				var value: String = tile.tile
				var matches: bool = value in plan.flip_tiles if key == "flip" else (Tiles.is_chicken(value) and value not in plan.gold_tiles)
				tile.set_score_highlight(matches)

func _clear_tile_highlights() -> void:
	if not is_instance_valid(table): return
	for seat in 4:
		for box in [table.hand_box.get(seat), table.draw_box.get(seat), table.meld_box.get(seat), table.chicken_box.get(seat)]:
			for tile in _tiles_in(box): tile.set_score_highlight(false)

func _roll_pairs(progress: float, before: Array, after: Array) -> void:
	# 逐对只取一次整数，镜像赋值保证滚动过程也始终两两相抵。
	for first in 4:
		for second in range(first + 1, 4):
			var amount := roundf(lerpf(float(before[first][second]), float(after[first][second]), progress))
			current_pairs[first][second] = amount
			current_pairs[second][first] = -amount
	_render_pairs()

func _render_pairs() -> void:
	if current_pairs.size() != 4: return
	for seat in payment_labels:
		var values := ScoringEngine.relative_payments(current_pairs, seat)
		for index in 3:
			var label: Label = payment_labels[seat][index]
			label.text = _signed(float(values[index]))
			label.add_theme_color_override("font_color", _net_color(float(values[index])))

func _begin_final() -> void:
	_end_stage()
	current_pairs = plan.final.duplicate(true)
	_net_visible = true
	for seat in 4: _display_colors[seat] = _net_color(float(plan.deltas[seat]))
	apply_displays()
	_spawn_particles()
	if not _particles.is_empty(): AudioManager.play_settlement_cue("coins", table)

func _roll_final(progress: float) -> void:
	var elapsed := progress * _count_duration
	for seat in 4:
		var delta := float(plan.deltas[seat])
		var duration := _score_duration_for_delta(delta)
		var fraction := clampf(elapsed / duration, 0.0, 1.0) if duration > 0 else 1.0
		_display_scores[seat] = counted_score(float(_start_scores[seat]), float(_target_scores[seat]), fraction)
		_display_colors[seat] = Color.WHITE if fraction >= 1.0 else _net_color(delta)
		var net: Label = table.net_labels[seat]
		net.modulate.a = lerpf(0.25, 1.0, clampf(elapsed / UI.SETTLEMENT_PARTICLE_SECONDS, 0.0, 1.0))
	_animate_particles(clampf(elapsed / UI.SETTLEMENT_PARTICLE_SECONDS, 0.0, 1.0))
	apply_displays()

static func counted_score(from: float, to: float, progress: float) -> float:
	if progress >= 1.0: return to
	var difference := to - from
	var step := 2.0 if absf(difference) > 60.0 else 1.0
	var ticks := floorf(clampf(progress, 0.0, 1.0) * ceilf(absf(difference) / step))
	return from + signf(difference) * minf(absf(difference), ticks * step)

func _score_duration_for_delta(delta: float) -> float:
	var step := 2.0 if absf(delta) > 60.0 else 1.0
	return minf(UI.SETTLEMENT_COUNT_MAX_SECONDS, ceilf(absf(delta) / step) * UI.SETTLEMENT_COUNT_SECONDS)

func _spawn_particles() -> void:
	_clear_particles()
	for seat in 4:
		if is_zero_approx(float(plan.deltas[seat])): continue
		var source: Label = table.net_labels[seat]
		var target: Label = table.center_labels[seat]
		for index in source.text.length():
			var glyph := _text(layer, source.text[index], UI.CENTER_SCORE_FONT_SIZE, _net_color(float(plan.deltas[seat])))
			glyph.name = "SettlementDigitParticle"
			glyph.size = Vector2(24, 42)
			glyph.pivot_offset = glyph.size / 2.0
			var start := source.position + Vector2(index * 17, 0)
			var spread := start + Vector2((index - 1) * 16, -32 - (index % 3) * 14)
			var end := target.position + target.size / 2.0 - glyph.size / 2.0
			glyph.position = start
			_particles.append({"node": glyph, "start": start, "spread": spread, "end": end})

func _animate_particles(progress: float) -> void:
	for particle in _particles:
		var glyph: Label = particle.node
		if not is_instance_valid(glyph): continue
		if progress < 0.33:
			glyph.position = Vector2(particle.start).lerp(particle.spread, progress / 0.33)
		else:
			var p := (progress - 0.33) / 0.67
			glyph.position = Vector2(particle.spread).lerp(particle.end, p * p)
		glyph.scale = Vector2.ONE * lerpf(0.9, 0.08, progress)
		glyph.modulate.a = 1.0 - progress

func _clear_particles() -> void:
	for particle in _particles: _remove_visual(particle.node)
	_particles.clear()

func _kill_timeline() -> void:
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null

func _remove_visual(node: Node) -> void:
	if not is_instance_valid(node): return
	if node.get_parent() != null: node.get_parent().remove_child(node)
	node.queue_free()

func _text(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", TileView._font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label

func _tiles_in(node: Node) -> Array[TileView]:
	var tiles: Array[TileView] = []
	if not is_instance_valid(node): return tiles
	for child in node.get_children():
		if child is TileView: tiles.append(child)
		else: tiles.append_array(_tiles_in(child))
	return tiles

func _add_matrix(first: Array, second: Array) -> Array:
	var sum := first.duplicate(true)
	for seat in 4:
		for other in 4: sum[seat][other] += float(second[seat][other])
	return sum

func _matrix_changed(matrix: Array) -> bool:
	for row in matrix:
		for value in row:
			if not is_zero_approx(float(value)): return true
	return false

func _signed(value: float) -> String:
	return "%+.0f" % value if not is_zero_approx(value) else "0"

func _net_color(value: float) -> Color:
	return UI.SCORE_GAIN if value > 0.0 else (UI.SCORE_LOSS if value < 0.0 else UI.MUTED)
