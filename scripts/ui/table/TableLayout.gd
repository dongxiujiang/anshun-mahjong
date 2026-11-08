extends "res://scripts/ui/table/TableComponent.gd"
## 设计画布、安全区、四向几何、背景和骰子绘制。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var surface: Control
var _felt: NoiseTexture2D
var _landscape := false
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
	if turn_indicator != null: turn_indicator.set_active(side)

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
	table._sound_settings = SoundSettings.new()
	table._sound_settings.table_mode = true
	table.add_child(table._sound_settings)
	table._sound_settings.ai_speed_selected.connect(table._set_ai_speed)
	table._sound_settings.ai_strength_selected.connect(table._set_ai_strength)
	table._sound_settings.auto_test_requested.connect(table.start_auto_test)
	table._sound_settings.voice_pack_open_requested.connect(table.open_voice_packs)
	GameConfig.settlement_speed_changed.connect(table._on_settlement_speed_changed)
	var sound_button: Button = table._button("设置", table._sound_settings.open, UI.SETTINGS_BUTTON_SIZE)
	sound_button.set_script(preload("res://scripts/ui/table/SettingsButton.gd"))
	sound_button.name = "SoundButton"
	sound_button.add_theme_font_size_override("font_size", UI.SETTINGS_FONT_SIZE)
	sound_button.position = Vector2(1287, 20)
	surface.add_child(sound_button)
	table._sound_button = sound_button
	var ai_proxy_button: Button = table._button("AI代打", table.toggle_ai_proxy, Vector2(148, UI.SETTINGS_BUTTON_SIZE.y))
	ai_proxy_button.name = "AiProxyButton"
	ai_proxy_button.add_theme_font_size_override("font_size", UI.SETTINGS_FONT_SIZE - 6)
	ai_proxy_button.tooltip_text = "AI 代替你操作当前座位"
	ai_proxy_button.visible = false
	surface.add_child(ai_proxy_button)
	table._ai_proxy_button = ai_proxy_button
	var voice_button: Button = table._button("麦克风 关", table._toggle_voice_chat, Vector2(164, UI.SETTINGS_BUTTON_SIZE.y))
	voice_button.name = "VoiceChatButton"
	voice_button.add_theme_font_size_override("font_size", UI.SETTINGS_FONT_SIZE - 6)
	voice_button.tooltip_text = "联机语音聊天，默认关闭"
	voice_button.visible = false
	surface.add_child(voice_button)
	table._voice_button = voice_button
	var test_button: Button = table._button("测试牌型", table._on_test_pattern_pressed,
		Vector2(136, UI.SETTINGS_BUTTON_SIZE.y))
	test_button.name = "TestPatternButton"
	test_button.add_theme_font_size_override("font_size", UI.SETTINGS_FONT_SIZE - 8)
	test_button.tooltip_text = "联机测试牌型，需要全部真人同意"
	test_button.visible = false
	surface.add_child(test_button)
	table._test_pattern_button = test_button
	var ai_teach: Button = table._button("AI教学", table._on_ai_assist_pressed, Vector2(148, UI.SETTINGS_BUTTON_SIZE.y))
	ai_teach.name = "AITeachButton"
	ai_teach.toggle_mode = true
	ai_teach.add_theme_font_size_override("font_size", 20)
	ai_teach.tooltip_text = "开启后每到自己出牌、可碰杠时自动提示，关闭后不提示"
	surface.add_child(ai_teach)
	table._ai_teach_button = ai_teach
	# 返回、声音和 AI 速度统一收进大号设置面板，避免右上角小按钮难以点击。
	table._sound_settings.exit_requested.connect(table._confirm_quit)
	table._sound_settings.exit_confirmed.connect(table._on_quit)
	table._sound_settings.replay_export_requested.connect(table._export_current_replay)
	table._settings_button = sound_button
	table._player_tile_areas.build()
	# 旧牌区仅保留输入/动画接口，视觉全部隐藏；由 TableV2 接管。
	_hide_legacy_table(table._player_tile_areas)
	var v2 = load("res://scenes/table/TableV2.tscn").instantiate()
	v2.name = "TableV2"
	v2.mouse_filter = Control.MOUSE_FILTER_PASS
	surface.add_child(v2)
	# TableV2 固定设计尺寸并在可用区域居中，宽屏 expand 时不会偏左。
	v2.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	v2.size = UI.DESIGN_SIZE
	v2.position = ((surface.size - UI.DESIGN_SIZE) * 0.5).floor()
	# TableV2 放在最底层，按钮/设置仍绘制在其上方。
	surface.move_child(v2, 0)
	v2.set_table(table)
	table._new_areas = v2

func _hide_legacy_visuals(areas) -> void:
	if turn_indicator != null: turn_indicator.hide()
	if areas == null: return
	for seat in 4:
		if areas.seat_roots.has(seat): areas.seat_roots[seat].hide()
		if areas.center_labels.has(seat): areas.center_labels[seat].hide()
		if areas.net_labels.has(seat): areas.net_labels[seat].hide()
		if areas.name_labels.has(seat): areas.name_labels[seat].hide()
		if areas.dealer_badges.has(seat): areas.dealer_badges[seat].hide()
		if areas.discard_scroll.has(seat): areas.discard_scroll[seat].hide()
		if areas.meld_box.has(seat): areas.meld_box[seat].hide()
		if areas.chicken_box.has(seat): areas.chicken_box[seat].hide()
		if areas.voice_speaker_buttons.has(seat): areas.voice_speaker_buttons[seat].hide()

func _hide_legacy_table(areas) -> void:
	# 只有首次构建时做一次建层；_refresh 里只需藏旧视觉，避免反复重建。
	_hide_legacy_visuals(areas)
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
	# Android 的屏幕比例通常比 2280×1280 设计稿更宽。若继续按短边等比缩放，
	# 左右会留下大块黑边；这里只对 Android 使用安全区内的非等比铺满，
	# 保证整张牌桌都显示在屏幕上。桌面/编辑器仍保持等比居中。
	var android_fill := OS.has_feature("android")
	surface.size = design
	if android_fill:
		surface.scale = Vector2(available.size.x / design.x, available.size.y / design.y)
		surface.position = available.position
	else:
		var factor = minf(available.size.x / design.x, available.size.y / design.y)
		surface.scale = Vector2.ONE * factor
		surface.position = available.position + (available.size - design * factor) / 2.0
	table._animation_layer.position = surface.position
	table._animation_layer.size = design
	table._animation_layer.scale = surface.scale
	for seat in 4:
		table.seat_roots[seat].position = table._table_center()
		# V2 接管后旧座位根节点只保留给 headless/兼容测试；图形模式不能再次弹出。
		if table._new_areas == null or DisplayServer.get_name() == "headless":
			table.seat_roots[seat].show()
		else:
			table.seat_roots[seat].hide()
		var metrics: Dictionary = table._seat_metrics(seat)
		# Release the previous content width before shrinking the scroll container.
		# Otherwise its minimum size keeps the wider landscape river in portrait.
		var content: Control = table.discard_scroll[seat].get_child(0)
		content.custom_minimum_size.x = metrics.river_size.x - UI.RIVER_CONTENT_MARGIN
		table.discard_scroll[seat].position = metrics.river_position
		table.discard_scroll[seat].size = metrics.river_size
	if turn_indicator != null: turn_indicator.position = center_rect().position
	table._sound_button.position = Vector2(design.x - UI.SETTINGS_BUTTON_SIZE.x - UI.SETTINGS_EDGE_GAP, UI.SETTINGS_TOP_GAP)
	table._sound_button.custom_minimum_size = UI.SETTINGS_BUTTON_SIZE
	table._sound_button.size = table._sound_button.custom_minimum_size
	if table._ai_teach_button != null:
		table._ai_teach_button.position = table._sound_button.position - Vector2(table._ai_teach_button.size.x + 10.0, 0.0)
	if table._voice_button != null:
		table._voice_button.visible = table._net_mode() != ""
		table._voice_button.position = table._ai_teach_button.position - Vector2(table._voice_button.size.x + 10.0, 0.0)
		table._refresh_voice_button()
	if table._ai_proxy_button != null:
		table._ai_proxy_button.visible = table._net_mode() != ""
		table._ai_proxy_button.position = table._voice_button.position - Vector2(table._ai_proxy_button.size.x + 10.0, 0.0)
		table._refresh_ai_proxy_button()
	if table._test_pattern_button != null:
		# 测试牌型只对调试构建/开启 debug 的测试环境开放，正式包不显示。
		var test_net = table._net_node()
		table._test_pattern_button.visible = table._net_mode() != "" and GameConfig.debug_enabled \
			and test_net != null and bool(test_net.test_mode)
		var test_anchor = table._ai_proxy_button if table._ai_proxy_button.visible else table._voice_button
		table._test_pattern_button.position = test_anchor.position - Vector2(table._test_pattern_button.size.x + 10.0, 0.0)
	# Actions sit immediately above the local player's draw slot.
	table._layout_actions()
	status_label.position = Vector2(60, design.y - 54)
	table._settlement_card.refresh_layout()
	table._settlement_animation_controller.refresh_layout()
	if table.round != null and changed:
		# Rebuild after the resize notification, even if nobody is taking a turn.
		table._refresh_layout_contents.call_deferred()
	table.queue_redraw()

func _refresh_layout_contents() -> void:
	table._refresh()

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
	# 新布局：本地坐标中所有手牌靠外侧，手牌底边距桌框 20。
	var hand_h: float = TileView.BASE_H * float(table._hand_tile_unit(seat))
	var outer_local_y: float = UI.TABLE_BOUNDS.size.y * 0.5 - UI.HAND_OUTER_MARGIN
	var hand_y: float = outer_local_y - hand_h
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
	var width: float = TileView.BASE_W * float(table._hand_tile_unit(seat))
	var count: int = player.concealed.size() - (1 if player.just_drew != "" and player.concealed.has(player.just_drew) else 0)
	var span: float = maxf(0.0, count * (width + UI.TILE_GAP) - UI.TILE_GAP)
	# 绿色手牌自身居中；摸牌单独放在右端，与手牌间隔一个牌宽。
	var hand_x: float = -span / 2.0
	var draw_x: float = hand_x + span + width * UI.HAND_DRAW_GAP_TILES
	return {"draw_x": draw_x, "hand_x": hand_x, "count": count}

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
	if table.round != null and not _should_show_dice():
		# 动画结束后骰子节点保留到庄家第二次拿牌；超过时机统一移除。
		if table._animation_layer != null:
			table._animation_layer.clear_dice()

func _should_show_dice() -> bool:
	if table.round == null or table.round.phase == RoundState.Phase.IDLE:
		return false
	if table.round.phase != RoundState.Phase.DEALING:
		return false
	var dealer := int(table.round.dealer_seat)
	var dealt: int = table._table_animation_controller.dealt_count(dealer)
	# 庄家第二次拿两蹲（已落地8张）时隐藏。
	return dealt < 8

func _relative_seat(seat: int) -> int:
	# 逆时针回合：本地座位的下家是编号 -1 的座位，显示在右侧。
	return posmod(table.human_seat - seat, 4)
