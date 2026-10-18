extends "res://scripts/ui/table/TableComponent.gd"
## 设计画布、安全区、四向几何、背景和骰子绘制。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var surface: Control
var _felt: NoiseTexture2D
var _landscape := false
var _remaining_label: Label
var center_info: Label
var round_label: Label
var status_label: Label
var turn_indicator: Control

func center_rect() -> Rect2:
	return Rect2(table._table_center() - UI.CENTER_SIZE / 2.0, UI.CENTER_SIZE)

func refresh_turn_indicator() -> void:
	var side := -1
	if table.round != null:
		var seat: int = table.round.presentation_turn_seat()
		if seat >= 0:
			side = table._relative_seat(seat)
	turn_indicator.set_active(side)

func _build_static_ui() -> void:
	var theme_resource = Theme.new()
	theme_resource.default_font = TileView._font()
	theme_resource.default_font_size = UI.DEFAULT_FONT_SIZE
	table.theme = theme_resource
	surface = Control.new()
	surface.name = "TableSurface"
	surface.size = UI.DESIGN_SIZE
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(surface)
	var noise = FastNoiseLite.new()
	noise.seed = 81
	noise.frequency = 0.7
	_felt = NoiseTexture2D.new()
	_felt.width = 512
	_felt.height = 512
	_felt.noise = noise
	_felt.changed.connect(table.queue_redraw)
	table._label(surface, "安顺麻将", Vector2(36, 21), Vector2(180, 36), 27)
	table._label(surface, "捉鸡  /  万 · 条 · 筒", Vector2(222, 28), Vector2(250, 30), 16, UI.MUTED)
	round_label = table._label(surface, "", Vector2(570, 28), Vector2(300, 30), 16, UI.MUTED)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table._sound_settings = SoundSettings.new()
	table._sound_settings.table_mode = true
	table.add_child(table._sound_settings)
	table._speed_buttons = table._sound_settings.speed_buttons
	table._sound_settings.ai_speed_selected.connect(table._set_ai_speed)
	table._update_speed_buttons()
	var sound_button: Button = table._button("设置", table._sound_settings.open, UI.SETTINGS_BUTTON_SIZE)
	sound_button.set_script(preload("res://scripts/ui/table/SettingsButton.gd"))
	sound_button.name = "SoundButton"
	sound_button.add_theme_font_size_override("font_size", UI.SETTINGS_FONT_SIZE)
	sound_button.position = Vector2(1287, 20)
	surface.add_child(sound_button)
	table._sound_button = sound_button
	# 返回、声音和 AI 速度统一收进大号设置面板，避免右上角小按钮难以点击。
	table._sound_settings.exit_requested.connect(table._confirm_quit)
	table._sound_settings.exit_confirmed.connect(table._on_quit)
	table._sound_settings.replay_export_requested.connect(table._export_current_replay)
	table._settings_button = sound_button
	turn_indicator = preload("res://scripts/ui/table/CenterTurnIndicator.gd").new()
	turn_indicator.name = "CenterTurnIndicator"
	turn_indicator.size = UI.CENTER_SIZE
	surface.add_child(turn_indicator)
	table._player_tile_areas.build()
	_remaining_label = table._label(surface, "余牌", Vector2(680, 705), Vector2(80, 24), 14, UI.MUTED)
	_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_info = table._label(surface, "", Vector2(664, 733), Vector2(112, 58), 40)
	center_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	table._table_actions.build()
	status_label = table._label(surface, "", Vector2(60, 1464), Vector2(710, 30), 20, UI.MUTED)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.hide()
	table._settlement_card.build()
	table._table_animation_controller.build()
	table._settlement_animation_controller.build()

func _layout() -> void:
	if surface == null:
		return
	var available: Rect2 = table._usable_rect()
	# The product layout is always landscape, including square and portrait
	# windows used by editor previews.  The canvas simply letterboxes there.
	var changed = not _landscape
	_landscape = true
	var design: Vector2 = table._design_size()
	var factor = minf(available.size.x / design.x, available.size.y / design.y)
	surface.size = design
	surface.scale = Vector2.ONE * factor
	surface.position = available.position + (available.size - design * factor) / 2.0
	table._animation_layer.position = surface.position
	table._animation_layer.size = design
	table._animation_layer.scale = Vector2.ONE * factor
	table.result_layer.size = design
	for seat in 4:
		table.seat_roots[seat].position = table._table_center()
		table.seat_roots[seat].show()
		var metrics: Dictionary = table._seat_metrics(seat)
		# Release the previous content width before shrinking the scroll container.
		# Otherwise its minimum size keeps the wider landscape river in portrait.
		var content: Control = table.discard_scroll[seat].get_child(0)
		content.custom_minimum_size.x = metrics.river_size.x - UI.RIVER_CONTENT_MARGIN
		table.discard_scroll[seat].position = metrics.river_position
		table.discard_scroll[seat].size = metrics.river_size
	_remaining_label.position = center_rect().position + Vector2(0, 24)
	_remaining_label.size = Vector2(UI.CENTER_SIZE.x, 24)
	center_info.position = center_rect().position + Vector2(0, 54)
	center_info.size = Vector2(UI.CENTER_SIZE.x, 58)
	turn_indicator.position = center_rect().position
	round_label.position.x = (design.x - round_label.size.x) / 2.0
	table._sound_button.position = Vector2(design.x - UI.SETTINGS_BUTTON_SIZE.x - UI.SETTINGS_EDGE_GAP, UI.SETTINGS_TOP_GAP)
	table._sound_button.custom_minimum_size = UI.SETTINGS_BUTTON_SIZE
	table._sound_button.size = table._sound_button.custom_minimum_size
	# Actions sit immediately above the local player's draw slot.
	table._layout_actions()
	status_label.position = Vector2(60, design.y - 54)
	if table.round != null and changed:
		# Rebuild after the resize notification, even if nobody is taking a turn.
		table._refresh_layout_contents.call_deferred()
	table.queue_redraw()

func _refresh_layout_contents() -> void:
	var had_result = table._result_panel != null and is_instance_valid(table._result_panel) and table._result_shown
	var showing_result = had_result and table._result_panel.visible
	table._refresh()
	if had_result and table.round.phase == RoundState.Phase.SETTLED:
		table._show_result()
		table._toggle_result_panel(showing_result)
	if table._result_restore != null and is_instance_valid(table._result_restore):
		table._result_restore.position = table.panel_position_for_result_toggle()

func _usable_rect() -> Rect2:
	var bounds = Rect2(Vector2.ZERO, table.size)
	if OS.has_feature("android"):
		var safe = Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			var transform = table.get_viewport().get_screen_transform() * table.get_global_transform()
			bounds = bounds.intersection(transform.affine_inverse() * safe)
	if OS.has_feature("android") and bounds.has_area():
		bounds = bounds.grow(-UI.SAFE_MARGIN)
	return bounds

func _design_size() -> Vector2:
	return UI.LANDSCAPE_SIZE

func _table_center() -> Vector2:
	return UI.LANDSCAPE_CENTER

func _table_bounds() -> Rect2:
	return UI.TABLE_BOUNDS if _landscape else UI.LEGACY_TABLE_BOUNDS

func _seat_metrics(seat: int) -> Dictionary:
	var side = table._relative_seat(seat) % 2 == 1
	var exposed_y = UI.SIDE_EXPOSED_Y if side else (UI.OWN_EXPOSED_Y if seat == table.human_seat else UI.OPPONENT_EXPOSED_Y)
	# Keep the local hand's bottom edge; the larger faces grow upwards.
	var hand_y = exposed_y - TileView.BASE_H * (UI.OWN_HAND_TILE_UNIT - UI.OWN_PLAYER_TILE_UNIT) if seat == table.human_seat else exposed_y
	return {"hand_y": hand_y, "exposed_y": exposed_y,
		"left": UI.SIDE_EXPOSED_LEFT if side else UI.EXPOSED_LEFT, "overflow_x": UI.SIDE_OVERFLOW_LEFT if side else UI.EXPOSED_LEFT,
		"overflow_right": UI.SIDE_OVERFLOW_RIGHT if side else UI.OVERFLOW_RIGHT,
		# Side-player discard zones are wider in their local axis.  River tiles use
		# their own readable size; hand and meld tile units remain independent.
		"river_position": UI.SIDE_RIVER_POSITION if side else UI.MAIN_RIVER_POSITION,
		"river_size": UI.SIDE_RIVER_SIZE if side else UI.MAIN_RIVER_SIZE, "river_columns": UI.RIVER_COLUMNS}

func _player_tile_unit(seat: int) -> float:
	return UI.OWN_PLAYER_TILE_UNIT if seat == table.human_seat else UI.PLAYER_TILE_UNIT

func _hand_tile_unit(seat: int) -> float:
	return UI.OWN_HAND_TILE_UNIT if seat == table.human_seat else UI.PLAYER_TILE_UNIT

func _hand_layout(seat: int) -> Dictionary:
	var player: PlayerState = table.round.players[seat]
	var width = TileView.BASE_W * table._hand_tile_unit(seat)
	var count = player.concealed.size() - (1 if player.just_drew != "" and player.concealed.has(player.just_drew) else 0)
	var span = maxf(0.0, count * (width + UI.TILE_GAP) - UI.TILE_GAP)
	var right = (span + UI.DRAW_GAP + width) / 2.0
	return {"draw_x": right - width, "hand_x": right - width - UI.DRAW_GAP - span, "count": count}

func _draw() -> void:
	table.draw_rect(Rect2(Vector2.ZERO, table.size), UI.BACKGROUND)
	if surface == null:
		return
	table.draw_set_transform(surface.position, 0.0, surface.scale)
	var bounds: Rect2 = table._table_bounds()
	table.draw_style_box(table._style(UI.TABLE_FRAME, UI.TABLE_FRAME_BORDER, 8, 2), bounds)
	table.draw_style_box(table._style(UI.FELT, UI.FELT_BORDER, 8, 1), bounds.grow(-12))
	if _felt != null:
		table.draw_texture_rect(_felt, bounds.grow(-38), false, UI.FELT_TEXTURE_TINT)
	table.draw_style_box(table._style(UI.TRANSPARENT_FILL, UI.FELT_INNER_BORDER, 8, 1), bounds.grow(-40))
	table.draw_line(Vector2(30, 68), Vector2(table._design_size().x - 30, 68), UI.HEADER_LINE, 1)
	table.draw_style_box(table._style(UI.CENTER_BACKGROUND, UI.CENTER_BORDER, 8, 2), center_rect())
	if table.round == null:
		return
	table._draw_die(int(table.round.round_meta.get("die", 1)), center_rect().position + Vector2(66, 126))

func _draw_die(value: int, pos: Vector2) -> void:
	table.draw_style_box(table._style(UI.DICE_FACE, UI.DICE_BORDER, 5, 1), Rect2(pos, Vector2(36, 36)))
	var points: Array = []
	if value % 2 == 1:
		points.append(Vector2(18, 18))
	if value >= 2:
		points.append_array([Vector2(9, 9), Vector2(27, 27)])
	if value >= 4:
		points.append_array([Vector2(27, 9), Vector2(9, 27)])
	if value == 6:
		points.append_array([Vector2(9, 18), Vector2(27, 18)])
	for point in points:
		table.draw_circle(pos + point, 3.0, UI.DICE_RED if value == 1 else UI.DICE_DOT)

func _relative_seat(seat: int) -> int:
	return posmod(seat - table.human_seat, 4)
