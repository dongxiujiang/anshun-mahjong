extends PanelContainer

const UI := preload("res://src/app/AppTheme.gd")
const Room := preload("res://src/session/RoomSession.gd")
const MahjongNames := preload("res://src/domain/MahjongNames.gd")
const Picker := preload("res://src/app/CharacterPicker.gd")
const TitleTile := preload("res://src/app/TitleTile.gd")
const CharacterScroll := preload("res://src/app/CharacterScroll.gd")
const NAMES := MahjongNames.POOL
const ERROR := Color("#ffb5a8")
const SAVE_COLORS := {"normal": Color("#efbd68"), "hover": Color("#ffda8c"), "pressed": Color("#cc9751")}

signal saved(nickname: String, avatar: int)
signal cancelled

var _heading: Control
var _gallery: VBoxContainer
var _avatar_section: VBoxContainer
var _picking_name := false
var _name_picker_section: VBoxContainer
var _name_picker_grid: GridContainer
var _name_picker_btn: Button
var _name_buttons: Array[Button] = []
var _picker := Picker.new()
var _nickname := LineEdit.new()
var _count: Label
var _error: Label
var _first := true
var typing:=false
var _character_scroll: ScrollContainer

func build(profile: Dictionary, first: bool) -> void:
	_first = first
	add_theme_stylebox_override("panel", UI.elevated_card(Color("#0f261ff2"), 20, 20, UI.GOLD_BORDER, 2,
		14 if UI.MotionFX.MotionConfig.value("panel", "shadow_enabled") else 0))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	_heading = _title()
	layout.add_child(_heading)
	_gallery = VBoxContainer.new()
	_gallery.add_theme_constant_override("separation", 8)
	_gallery.size_flags_vertical = SIZE_EXPAND_FILL
	layout.add_child(_gallery)

	_avatar_section = VBoxContainer.new()
	_avatar_section.add_theme_constant_override("separation", 8)
	_avatar_section.size_flags_vertical = SIZE_EXPAND_FILL
	var gallery_hint := UI.label("选择牌桌头像（左右滑动浏览全部 15 位形象）", 16, UI.MUTED)
	_avatar_section.add_child(gallery_hint)
	var stack := MarginContainer.new()
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	_gallery.add_child(stack)
	stack.add_child(_avatar_section)
	var scroll := CharacterScroll.new()
	_character_scroll=scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_avatar_section.add_child(scroll)
	scroll.set_meta("page_label","人物选择 · 两行横向滑动")
	scroll.set_meta("page_id","characters")
	scroll.add_child(_picker)
	_picker.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_picker.size_flags_vertical = SIZE_EXPAND_FILL
	_picker.build(profile.avatar)
	_picker.set_meta("page_label","人物选择")

	_name_picker_section = _build_name_picker()
	_name_picker_section.hide()
	stack.add_child(_name_picker_section)

	var footer_card := PanelContainer.new()
	footer_card.add_theme_stylebox_override("panel", UI.card(Color("#0a1c17cc"), 14, 12, Color("#3a5d4e"), 1))
	layout.add_child(footer_card)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 10)
	footer_card.add_child(footer_row)
	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", 6)
	footer_row.add_child(name_row)
	name_row.add_child(UI.label("昵称", 19, UI.GOLD))
	_nickname.text = NAMES[0] if first else profile.nickname
	_nickname.placeholder_text = "1–6个汉字、字母或数字"
	_nickname.accessibility_name = "昵称"
	_nickname.custom_minimum_size = Vector2(148, 46)
	_nickname.size_flags_horizontal = SIZE_EXPAND_FILL
	_nickname.text_changed.connect(_name_changed)
	name_row.add_child(_nickname)
	_count = UI.label("", 15)
	_count.custom_minimum_size.x = 36
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_row.add_child(_count)
	_name_picker_btn = UI.button("挑昵称", _toggle_name_picker)
	_name_picker_btn.custom_minimum_size = Vector2(84, 46)
	_name_picker_btn.tooltip_text = "从 100 个麻将专属昵称中挑选"
	name_row.add_child(_name_picker_btn)
	var rand_btn := UI.button("随机换名", _randomize_nickname)
	rand_btn.custom_minimum_size = Vector2(92, 46)
	name_row.add_child(rand_btn)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	footer_row.add_child(buttons)
	var cancel:=UI.button("取消",func():cancelled.emit())
	cancel.custom_minimum_size = Vector2(84, 46)
	cancel.disabled=first
	cancel.visible=not first
	if first:cancel.tooltip_text="首次使用请先保存个人资料"
	buttons.add_child(cancel)
	var save := UI.button("保存", _submit)
	save.custom_minimum_size = Vector2(140, 48)
	save.add_theme_font_size_override("font_size", 21)
	for state in SAVE_COLORS:
		save.add_theme_stylebox_override(state, UI.elevated_card(SAVE_COLORS[state], 14, 10, Picker.GOLD, 2,
			5 if UI.MotionFX.MotionConfig.value("panel", "shadow_enabled") else 0))
		save.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, Color("#1b2b22"))
	buttons.add_child(save)
	_error = UI.label("", 15, ERROR)
	_error.set_meta("page_label","资料校验提示")
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.custom_minimum_size.y = 20
	layout.add_child(_error)
	_name_changed(_nickname.text)
	_picker.focus_selected()


func _build_name_picker() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_vertical = SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var hint := UI.label("麻将昵称库（共 %d 个 · 点选即填入，人机亦从中不重复抽取）" % NAMES.size(), 15, UI.GOLD)
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(hint)
	var back_btn := UI.button("返回选头像", _close_name_picker)
	back_btn.custom_minimum_size = Vector2(108, 34)
	back_btn.add_theme_font_size_override("font_size", 14)
	header.add_child(back_btn)
	box.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_child(scroll)

	_name_picker_grid = GridContainer.new()
	_name_picker_grid.columns = 5
	_name_picker_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_name_picker_grid.add_theme_constant_override("h_separation", 8)
	_name_picker_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_name_picker_grid)

	_name_buttons.clear()
	for entry in NAMES:
		var btn := UI.button(entry, _pick_preset_name.bind(entry))
		btn.custom_minimum_size = Vector2(0, 40)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		_name_picker_grid.add_child(btn)
		_name_buttons.append(btn)
	return box


func _toggle_name_picker() -> void:
	_set_picker(not _picking_name)


func _close_name_picker() -> void:
	_set_picker(false)


func _set_picker(names: bool) -> void:
	if names == _picking_name:
		return
	_picking_name = names
	var incoming := _name_picker_section if names else _avatar_section
	var outgoing := _avatar_section if names else _name_picker_section
	var spec := UI.MotionFX.MotionConfig.section("overlay")
	var duration: float = spec.badge_in
	var curve: int = UI.MotionFX.MotionConfig.value("panel", "ease_trans")
	UI.MotionFX.stop(outgoing)
	outgoing.hide()
	outgoing.modulate.a = 1.0
	outgoing.focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
	outgoing.mouse_behavior_recursive = MOUSE_BEHAVIOR_DISABLED
	incoming.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
	incoming.mouse_behavior_recursive = MOUSE_BEHAVIOR_INHERITED
	UI.MotionFX._slide(incoming, true, Vector2.DOWN * (8.0 if UI.MotionFX.MotionConfig.is_detail() else 4.0), duration, curve)
	_name_picker_btn.text = "选头像" if names else "挑昵称"
	if names:
		_refresh_name_picker_selection()


func _pick_preset_name(chosen: String) -> void:
	_nickname.text = chosen
	_name_changed(chosen)
	_close_name_picker()


func _refresh_name_picker_selection() -> void:
	var current := _nickname.text
	for btn in _name_buttons:
		var active := btn.text == current
		btn.add_theme_stylebox_override("normal",
			UI.card(Color("#2b4f3d") if active else Color("#122a23"), 8, 6, UI.GOLD_BRIGHT if active else Color("#3c5e4e"), 2 if active else 1))
		btn.add_theme_color_override("font_color", UI.GOLD_BRIGHT if active else UI.INK)


func fit(available: Vector2, keyboard_open: bool) -> void:
	typing=keyboard_open
	if typing and _picking_name:
		_close_name_picker()
	_heading.visible = not typing
	_gallery.visible = not typing
	custom_minimum_size = Vector2(minf(available.x, 1060), minf(available.y, 168 if typing else 664))
	for card in _picker._cards:card.custom_minimum_size.y=clampf((available.y-330)/2,100,158)

func show_error(message: String) -> void:
	_error.text = message

func _title() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.add_child(_title_tile("tiao1"))
	var caption := VBoxContainer.new()
	caption.add_theme_constant_override("separation", 0)
	row.add_child(caption)
	var title := UI.label("东秀麻将" if _first else "个人资料", 36, UI.GOLD_BRIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(title)
	var subtitle := UI.label("安顺捉鸡 · 选择你的牌桌形象与昵称" if _first else "东秀麻将 · 安顺捉鸡", 17, UI.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(subtitle)
	row.add_child(_title_tile("tong8"))
	return row

func _title_tile(value: String) -> Control:
	var tile := TitleTile.new()
	tile.value=value
	tile.set_meta("page_label","标题 · 幺鸡" if value=="tiao1" else "标题 · 八筒")
	tile.size_flags_vertical = SIZE_SHRINK_CENTER
	return tile

func _name_changed(value: String) -> void:
	_count.text = "%d/6" % value.length()
	_count.add_theme_color_override("font_color", ERROR if value.length() > 6 else UI.MUTED)
	show_error("")
	if _picking_name:
		_refresh_name_picker_selection()

func _randomize_nickname() -> void:
	_nickname.text = MahjongNames.pick_one([_nickname.text])
	_name_changed(_nickname.text)

func _submit() -> void:
	if _nickname.has_ime_text():
		_nickname.grab_focus()
		return
	if not Room.is_valid_nickname(_nickname.text):
		show_error("昵称须为 1–6 个汉字、字母或数字。")
		_nickname.grab_focus()
		return
	saved.emit(_nickname.text, _picker.selected_id)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _nickname.has_ime_text():
		if _picking_name:
			get_viewport().set_input_as_handled()
			_close_name_picker()
			return
		if not _first:
			get_viewport().set_input_as_handled()
			cancelled.emit()
