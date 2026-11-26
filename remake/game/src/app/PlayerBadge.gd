extends Button

const UI := preload("res://src/app/AppTheme.gd")
const ACTIVE := Color("#67d891")
const MUTED := Color("#f04f4f")

signal player_pressed(context: Dictionary)

var name_label: Label
var score_label: Label
var turn_dot: Label
var mic_dot: Control
var dealer_seal: PanelContainer
var ready_seal: PanelContainer
var voice_badge: PanelContainer
var voice_label: Label
var context := {}
var _pressed_context := {}
var _content: VBoxContainer
var _padding := 6
var _compact := false
var _is_turn := false
var _voice_state_key := ""


func _init() -> void:
	_apply_badge_style(false)
	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 2)
	add_child(_content)
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 7
	_content.offset_right = -7
	_content.offset_top = 6
	_content.offset_bottom = -6

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 4)
	_content.add_child(name_row)
	turn_dot = UI.label("▶", 12, Color.WHITE)
	turn_dot.tooltip_text = "当前出牌者"
	turn_dot.custom_minimum_size.x = 12
	name_row.add_child(turn_dot)
	dealer_seal = _make_seal("庄", Color("#9a211b"), Color("#f0cf80"), Color("#fff3cf"))
	dealer_seal.hide()
	name_row.add_child(dealer_seal)
	ready_seal = _make_seal("听", Color("#156b52"), Color("#7fe6be"), Color("#eefff8"))
	ready_seal.hide()
	name_row.add_child(ready_seal)
	name_label = UI.label("", 15, Color.WHITE)
	name_row.add_child(name_label)
	mic_dot = Control.new()
	mic_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mic_dot.custom_minimum_size = Vector2(12, 12)
	mic_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mic_dot.self_modulate = ACTIVE
	mic_dot.modulate.a = 0
	mic_dot.draw.connect(func(): mic_dot.draw_circle(mic_dot.size * 0.5, 4.0, Color.WHITE, true, -1, true))
	mic_dot.tooltip_text = "麦克风已开启"
	name_row.add_child(mic_dot)
	mic_dot.resized.connect(mic_dot.queue_redraw)

	var score_row := HBoxContainer.new()
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 5)
	_content.add_child(score_row)
	score_label = UI.label("", 13, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_row.add_child(score_label)

	voice_badge = PanelContainer.new()
	voice_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voice_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	voice_label = UI.label("", 10, Color.WHITE)
	voice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	voice_badge.add_child(voice_label)
	voice_badge.hide()
	score_row.add_child(voice_badge)

	_content.minimum_size_changed.connect(_fit_minimum)
	button_down.connect(func(): _pressed_context = context.duplicate())
	pressed.connect(_activate)
	button_up.connect(cancel_press)
	visibility_changed.connect(cancel_press)
	_fit_minimum()


static func _make_seal(glyph: String, fill: Color, border: Color, ink: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size = Vector2(19, 19)
	panel.add_theme_stylebox_override("panel", UI.card(fill, 5, 1, border, 1))
	var lbl := UI.label(glyph, 11, ink)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	return panel


func _apply_badge_style(lit: bool) -> void:
	var fill := Color("#1c4a3af2") if lit else (Color("#0c241ed9") if _compact else Color("#10251feb"))
	var border := Color("#f5cd6a") if lit else Color("#4a6d5d")
	var radius := 9 if _compact else 10
	var box := UI.elevated_card(fill, radius, 0, border, 2 if lit else 1, 8 if lit else 3)
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, box)


func _fit_minimum() -> void:
	var min_box := Vector2(106, 46) if _compact else Vector2(116, 48)
	custom_minimum_size = (_content.get_combined_minimum_size() + Vector2.ONE * _padding * 2).max(min_box)


func set_compact() -> void:
	_compact = true
	_padding = 5
	_content.offset_left = 6; _content.offset_right = -6; _content.offset_top = 4; _content.offset_bottom = -4
	name_label.add_theme_font_size_override("font_size", 14); score_label.add_theme_font_size_override("font_size", 12)
	_apply_badge_style(_is_turn)
	_fit_minimum()


func set_role_seals(is_dealer: bool, is_ready: bool) -> void:
	dealer_seal.visible = is_dealer
	ready_seal.visible = is_ready
	_fit_minimum()


func show_player(member: Dictionary, flags: PackedStringArray, is_turn: bool, target: Dictionary, interactive: bool) -> void:
	if context != target or not interactive:
		cancel_press()
	if context != target:
		set_mic_active(false)
		set_voice_indicator(false, false, false, false)
	context = target.duplicate()
	name_label.text = member.nickname
	score_label.text = "%d 分%s" % [int(member.score), " · " + " · ".join(flags) if not flags.is_empty() else ""]
	turn_dot.modulate.a = 1.0 if is_turn else 0.0
	if _is_turn != is_turn:
		_is_turn = is_turn
		_apply_badge_style(_is_turn)
	disabled = not interactive
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE


func set_mic_active(active: bool, muted: bool = false) -> void:
	name_label.add_theme_color_override("font_color", Color.WHITE)
	mic_dot.modulate.a = 1.0 if active else 0.0
	mic_dot.self_modulate = MUTED if muted else ACTIVE
	mic_dot.tooltip_text = "麦克风已开启 · 已取消收听" if muted else "麦克风已开启"


func set_voice_indicator(show_tag: bool, is_local: bool, mic_on: bool, speaker_muted: bool, pending: bool = false) -> void:
	if not show_tag:
		if voice_badge.visible:
			voice_badge.hide()
			_voice_state_key = ""
			_fit_minimum()
		return
	var key := "%s|%s|%s|%s" % [str(is_local), str(mic_on), str(speaker_muted), str(pending)]
	if key == _voice_state_key and voice_badge.visible:
		return
	_voice_state_key = key
	var text := ""
	var fill := Color("#12332a")
	var border := Color("#4e7e6c")
	var ink := Color("#d8f0e4")
	if is_local:
		if mic_on:
			text = "麦开"
			fill = Color("#185c42")
			border = ACTIVE
			ink = Color("#eafff4")
		elif pending:
			text = "开启中"
			fill = Color("#3b3015")
			border = Color("#e5bc63")
			ink = Color("#fff0c2")
		else:
			text = "麦关"
			fill = Color("#2e1e21")
			border = Color("#a86568")
			ink = Color("#ecc4c4")
	else:
		if speaker_muted:
			text = "已静音"
			fill = Color("#5d1c22")
			border = Color("#f06464")
			ink = Color("#ffe0e0")
		elif mic_on:
			text = "发言中"
			fill = Color("#185c42")
			border = ACTIVE
			ink = Color("#eafff4")
		else:
			text = "收听中"
			fill = Color("#12332a")
			border = Color("#528572")
			ink = Color("#bce0d1")
	voice_label.text = text
	voice_label.add_theme_color_override("font_color", ink)
	var style := UI.card(fill, 5, 2, border, 1)
	style.set_content_margin(SIDE_LEFT, 5)
	style.set_content_margin(SIDE_RIGHT, 5)
	voice_badge.add_theme_stylebox_override("panel", style)
	voice_badge.show()
	_fit_minimum()


func cancel_press() -> void:
	_pressed_context.clear()


func _activate() -> void:
	var target := _pressed_context.duplicate()
	cancel_press()
	if not disabled and is_visible_in_tree() and not target.is_empty() and target == context:
		player_pressed.emit(target)
