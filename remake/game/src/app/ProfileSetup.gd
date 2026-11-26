extends PanelContainer

const UI := preload("res://src/app/AppTheme.gd")
const Room := preload("res://src/session/RoomSession.gd")
const Picker := preload("res://src/app/CharacterPicker.gd")
const TitleTile := preload("res://src/app/TitleTile.gd")
const CharacterScroll := preload("res://src/app/CharacterScroll.gd")
const NAMES := ["摸张好牌", "八筒", "七筒", "三条", "幺鸡", "清一色", "小牌友", "桌上见"]
const ERROR := Color("#ffb5a8")
const SAVE_COLORS := {"normal": Color("#efbd68"), "hover": Color("#ffda8c"), "pressed": Color("#cc9751")}

signal saved(nickname: String, avatar: int)
signal cancelled

var _heading: Control
var _gallery: VBoxContainer
var _picker := Picker.new()
var _nickname := LineEdit.new()
var _count: Label
var _error: Label
var _first := true
var typing:=false
var _character_scroll: ScrollContainer

func build(profile: Dictionary, first: bool) -> void:
	_first = first
	add_theme_stylebox_override("panel", UI.elevated_card(Color("#0f261ff2"), 20, 20, UI.GOLD_BORDER, 2, 14))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)
	_heading = _title()
	layout.add_child(_heading)
	_gallery = VBoxContainer.new()
	_gallery.add_theme_constant_override("separation", 8)
	_gallery.size_flags_vertical = SIZE_EXPAND_FILL
	var gallery_hint := UI.label("选择牌桌头像（左右滑动浏览全部 15 位形象）", 16, UI.MUTED)
	_gallery.add_child(gallery_hint)
	layout.add_child(_gallery)
	var scroll := CharacterScroll.new()
	_character_scroll=scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_gallery.add_child(scroll)
	scroll.set_meta("page_label","人物选择 · 两行横向滑动")
	scroll.set_meta("page_id","characters")
	scroll.add_child(_picker)
	_picker.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_picker.size_flags_vertical = SIZE_EXPAND_FILL
	_picker.build(profile.avatar)
	_picker.set_meta("page_label","人物选择")
	var footer_card := PanelContainer.new()
	footer_card.add_theme_stylebox_override("panel", UI.card(Color("#0a1c17cc"), 14, 12, Color("#3a5d4e"), 1))
	layout.add_child(footer_card)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 12)
	footer_card.add_child(footer_row)
	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", 8)
	footer_row.add_child(name_row)
	name_row.add_child(UI.label("昵称", 19, UI.GOLD))
	_nickname.text = NAMES[0] if first else profile.nickname
	_nickname.placeholder_text = "1–6个汉字、字母或数字"
	_nickname.accessibility_name = "昵称"
	_nickname.custom_minimum_size = Vector2(200, 46)
	_nickname.size_flags_horizontal = SIZE_EXPAND_FILL
	_nickname.text_changed.connect(_name_changed)
	name_row.add_child(_nickname)
	_count = UI.label("", 15)
	_count.custom_minimum_size.x = 38
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_row.add_child(_count)
	var rand_btn := UI.button("随机换名", _randomize_nickname)
	rand_btn.custom_minimum_size = Vector2(104, 46)
	name_row.add_child(rand_btn)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	footer_row.add_child(buttons)
	var cancel:=UI.button("取消",func():cancelled.emit())
	cancel.custom_minimum_size = Vector2(96, 46)
	cancel.disabled=first
	cancel.visible=not first
	if first:cancel.tooltip_text="首次使用请先保存个人资料"
	buttons.add_child(cancel)
	var save := UI.button("保存", _submit)
	save.custom_minimum_size = Vector2(156, 48)
	save.add_theme_font_size_override("font_size", 21)
	for state in SAVE_COLORS:
		save.add_theme_stylebox_override(state, UI.elevated_card(SAVE_COLORS[state], 14, 10, Picker.GOLD, 2, 5))
		save.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, Color("#1b2b22"))
	buttons.add_child(save)
	_error = UI.label("", 15, ERROR)
	_error.set_meta("page_label","资料校验提示")
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.custom_minimum_size.y = 20
	layout.add_child(_error)
	_name_changed(_nickname.text)
	_picker.focus_selected()

func fit(available: Vector2, keyboard_open: bool) -> void:
	typing=keyboard_open
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

func _randomize_nickname() -> void:
	var available := NAMES.filter(func(candidate): return candidate != _nickname.text)
	_nickname.text = available.pick_random()
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
	if not _first and event.is_action_pressed("ui_cancel") and not _nickname.has_ime_text():
		get_viewport().set_input_as_handled()
		cancelled.emit()
