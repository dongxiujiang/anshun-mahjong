extends VBoxContainer

const UI := preload("res://src/app/AppTheme.gd")
const VoicePacks := preload("res://src/audio/VoicePacks.gd")
const TableTheme := preload("res://src/presentation/TableTheme.gd")
const SUIT_ORDERS := [
	["wan", "tiao", "tong"], ["wan", "tong", "tiao"], ["tiao", "wan", "tong"],
	["tiao", "tong", "wan"], ["tong", "wan", "tiao"], ["tong", "tiao", "wan"],
]

signal saved(changes: Dictionary)
signal cancelled
signal edit_profile_requested
signal table_requested

var _fields := {}
var _error: Label
var content: VBoxContainer
var _difficulty_hint: Label
var _room_difficulty := ""
var _can_edit_difficulty := true
var tabs: TabContainer
var _operation_notice: Control


func build(profile: Dictionary, can_edit_profile: bool) -> void:
	add_theme_constant_override("separation", 8)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	add_child(header)
	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	header.add_child(title_col)
	title_col.add_child(UI.label("设置", 28, UI.GOLD_BRIGHT))
	title_col.add_child(UI.label("牌桌外观、理牌偏好与语音音效", 14, UI.MUTED))
	var profile_button: Button
	if can_edit_profile:
		profile_button = UI.button("个人资料", func(): edit_profile_requested.emit())
		profile_button.custom_minimum_size = Vector2(124, 42)
		header.add_child(profile_button)

	var notice_card := PanelContainer.new()
	notice_card.add_theme_stylebox_override("panel", UI.card(Color("#3a2912e8"), 10, 10, UI.GOLD_BORDER, 1))
	var notice_row := HBoxContainer.new()
	notice_row.add_theme_constant_override("separation", 12)
	notice_card.add_child(notice_row)
	var notice_label := UI.label("轮到你操作，可随时返回牌桌出牌", 16, UI.GOLD_BRIGHT)
	notice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_row.add_child(notice_label)
	var return_btn := UI.button("返回牌桌", func(): table_requested.emit(), true)
	return_btn.custom_minimum_size = Vector2(110, 38)
	notice_row.add_child(return_btn)
	_operation_notice = notice_card
	add_child(_operation_notice)
	_operation_notice.hide()

	tabs = TabContainer.new()
	tabs.custom_minimum_size.y = 446
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)

	# 页签 1：对局（双栏分区：左侧牌桌外观与提示 + 右侧理牌与对局规则，零滚动完整展示）
	content = _page("对局", "match")
	var match_cols := HBoxContainer.new()
	match_cols.add_theme_constant_override("separation", 14)
	match_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(match_cols)

	var look_fields := _section_card(match_cols, "牌桌外观与辅助")
	var theme_opt := _option_with_swatch(look_fields, "牌桌主题", "table_theme", TableTheme.table_labels(), TableTheme.TABLE_ORDER, profile.get("table_theme", "jade_classic"), true)
	_option_with_swatch(look_fields, "牌背样式", "tile_back", TableTheme.tile_back_labels(), TableTheme.TILE_BACK_ORDER, profile.get("tile_back", "jade"), false)
	_toggle(look_fields, "省电帧率 (30 FPS)", "power_save", profile.get("power_save", false))
	_option(look_fields, "画质", "quality", ["流畅", "精致"], ["smooth", "detail"], profile.quality)
	_toggle(look_fields, "听牌与同牌提示", "smart_hints", profile.get("smart_hints", true))
	_toggle(look_fields, "AI出牌参谋", "teaching_enabled", profile.get("teaching_enabled", false))

	var play_fields := _section_card(match_cols, "理牌与对局习惯")
	_option(play_fields, "拿牌动作", "draw_style", ["A", "B", "随机"], ["a", "b", "random"], profile.draw_style)
	_option(play_fields, "花色顺序", "suit_order", ["万 · 条 · 筒", "万 · 筒 · 条", "条 · 万 · 筒", "条 · 筒 · 万", "筒 · 万 · 条", "筒 · 条 · 万"], SUIT_ORDERS, profile.suit_order)
	_option(play_fields, "理牌优先", "hand_priority", ["多张优先", "大牌优先"], ["multiple", "pattern"], profile.hand_priority)
	_toggle(play_fields, "新手排法", "novice", profile.novice)
	_option(play_fields, "人机难度", "difficulty", ["低", "中", "高"], ["low", "medium", "high"], profile.difficulty)
	_difficulty_hint = UI.label("人机难度：新建牌局时生效", 12, UI.MUTED)
	play_fields.get_parent().add_child(_difficulty_hint)

	# 页签 2：声音（仅包含音频与语音控制，双栏分组清爽排布）
	var sound_page := _page("声音", "sound")
	var sound_cols := HBoxContainer.new()
	sound_cols.add_theme_constant_override("separation", 14)
	sound_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_page.add_child(sound_cols)

	var bgm_fields := _section_card(sound_cols, "音乐与牌桌音效")
	_toggle(bgm_fields, "背景音乐", "music", profile.music)
	_slider(bgm_fields, "音乐音量", "music_volume", profile.music_volume)
	_toggle(bgm_fields, "牌桌音效", "effects_enabled", profile.effects_enabled)
	_slider(bgm_fields, "音效音量", "effects_volume", profile.effects_volume)
	var credit_lbl := UI.label("配乐：《Ripples》 · Kevin MacLeod · CC BY 4.0", 12, UI.MUTED)
	credit_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bgm_fields.get_parent().add_child(credit_lbl)

	var voice_fields := _section_card(sound_cols, "报牌语音与联机通话")
	_toggle(voice_fields, "报牌声音", "voice_enabled", profile.voice_enabled)
	_option(voice_fields, "报牌音色", "voice_pack", VoicePacks.ORDER.map(func(id): return VoicePacks.LABELS[id]), VoicePacks.ORDER, profile.voice_pack)
	_slider(voice_fields, "报牌音量", "voice_volume", profile.voice_volume)
	_slider(voice_fields, "麦克风音量", "microphone_gain", profile.microphone_gain)
	_slider(voice_fields, "听筒音量", "speaker_gain", profile.speaker_gain)

	_error = UI.label("", 15, Color("#ffb2a4"))
	_error.set_meta("page_label", "设置保存提示")
	add_child(_error)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	var cancel_btn := UI.button("取消", func(): cancelled.emit())
	cancel_btn.custom_minimum_size = Vector2(108, 44)
	buttons.add_child(cancel_btn)
	var save_btn := UI.button("保存", func(): saved.emit(values()), true)
	save_btn.custom_minimum_size = Vector2(128, 44)
	buttons.add_child(save_btn)
	UI.focus_later(profile_button if can_edit_profile else theme_opt)


func _page(title: String, id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.set_meta("page_id", id)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(margin)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	return page


func _section_card(parent: Control, heading: String) -> GridContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.card(Color("#0c201be6"), 12, 10, Color("#3e6253"), 1))
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	card.add_child(col)
	col.add_child(UI.label(heading, 15, UI.GOLD))
	var fields := GridContainer.new()
	fields.columns = 2
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("h_separation", 12)
	fields.add_theme_constant_override("v_separation", 5)
	col.add_child(fields)
	return fields


func show_operation_reminder(active: bool) -> void:
	_operation_notice.visible = active


func show_error(text: String) -> void:
	_error.text = text


func apply_room(room: Dictionary, can_edit: bool) -> void:
	var chosen: String = room.get("next_difficulty", room.get("difficulty", "medium"))
	var option: OptionButton = _fields.difficulty
	if chosen != _room_difficulty or can_edit != _can_edit_difficulty:
		for index in option.item_count:
			if option.get_item_metadata(index) == chosen:
				option.select(index)
	_room_difficulty = chosen
	_can_edit_difficulty = can_edit
	option.disabled = not can_edit
	var pending: bool = room.get("difficulty", chosen) != chosen
	_difficulty_hint.text = ("下一局生效" if pending else "局中修改从下一局生效") if can_edit else ("房主设置 · 下一局生效" if pending else "房主设置")


func _add_field(fields: GridContainer, text: String, key: String, control: Control) -> void:
	var lbl := UI.label(text, 15, UI.INK)
	lbl.custom_minimum_size.x = 108
	fields.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 38
	fields.add_child(control)
	_fields[key] = control


func _toggle(fields: GridContainer, text: String, key: String, value: bool, credit: String = "") -> void:
	var toggle := CheckButton.new()
	toggle.text = "已开启" if value else "已关闭"
	toggle.button_pressed = value
	toggle.toggled.connect(func(pressed: bool): toggle.text = "已开启" if pressed else "已关闭")
	if credit.is_empty():
		_add_field(fields, text, key, toggle)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(toggle)
	var credit_lbl := UI.label(credit, 12, UI.MUTED)
	credit_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credit_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(credit_lbl)
	_add_field(fields, text, key, row)
	_fields[key] = toggle


func _slider(fields: GridContainer, text: String, key: String, value: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var amount := UI.label("%d%%" % roundi(value * 100.0), 14, UI.GOLD)
	amount.custom_minimum_size.x = 44
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	slider.value_changed.connect(func(level): amount.text = "%d%%" % roundi(level * 100.0))
	_add_field(fields, text, key, row)
	_fields[key] = slider


func _option(fields: GridContainer, text: String, key: String, labels: Array, option_values: Array, chosen) -> OptionButton:
	var option := OptionButton.new()
	for index in labels.size():
		option.add_item(labels[index])
		option.set_item_metadata(index, option_values[index])
		if chosen == option_values[index]:
			option.select(index)
	_add_field(fields, text, key, option)
	return option


func _option_with_swatch(fields: GridContainer, text: String, key: String, labels: Array, option_values: Array, chosen, is_table: bool) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in labels.size():
		option.add_item(labels[index])
		option.set_item_metadata(index, option_values[index])
		if chosen == option_values[index]:
			option.select(index)
	row.add_child(option)

	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(72, 38)
	preview.add_theme_stylebox_override("panel", UI.card(Color("#091713"), 8, 4, Color("#4a6e5e"), 1))
	row.add_child(preview)
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 4)
	preview.add_child(chips)
	var chip_nodes: Array[ColorRect] = []
	for _i in (3 if is_table else 2):
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(16 if is_table else 24, 22)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chips.add_child(c)
		chip_nodes.append(c)

	var refresh_swatch := func(idx: int) -> void:
		var id := str(option.get_item_metadata(maxi(0, idx)))
		if is_table:
			var data := TableTheme.table_data(id)
			chip_nodes[0].color = data.felt_center
			chip_nodes[1].color = data.wood
			chip_nodes[2].color = data.trim_gold
		else:
			var data := TableTheme.tile_back_data(id)
			chip_nodes[0].color = data.back
			chip_nodes[1].color = data.ivory
	refresh_swatch.call(option.selected)
	option.item_selected.connect(refresh_swatch)

	_add_field(fields, text, key, row)
	_fields[key] = option
	return option


func values() -> Dictionary:
	var changes := {}
	for key in _fields:
		var field: Control = _fields[key]
		if field is OptionButton:
			changes[key] = field.get_item_metadata(field.selected)
		elif field is CheckButton:
			changes[key] = field.button_pressed
		elif field is HSlider:
			changes[key] = field.value
	return changes
