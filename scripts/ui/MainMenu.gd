extends Control

const MENU_SIZE := Vector2(1800, 1000)
const ENTRY_BUTTON_SIZE := Vector2(760, 184)
var content: Control
var sound_settings: SoundSettings
var update_panel: UpdatePanel
var update_button: Button
var update_status_label: Label
var rule_guide: Control

func _ready() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font = TileView._font()
	theme_resource.default_font_size = 22
	theme = theme_resource
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("#102e29"), Color("#205b45")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.ONE
	var background := TextureRect.new()
	background.texture = texture
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	content = Control.new()
	content.size = MENU_SIZE
	add_child(content)
	var hero := Panel.new()
	hero.position = Vector2(28, 84)
	hero.size = Vector2(858, 830)
	hero.add_theme_stylebox_override("panel", _style(Color("#173c32"), Color("#37614c")))
	content.add_child(hero)
	_label(hero, "安 顺 麻 将", Vector2(68, 72), Vector2(722, 116), 82, Color("#f2deb0"))
	_label(hero, "捉鸡 · 熟悉的牌，熟悉的玩法", Vector2(72, 202), Vector2(716, 54), 32, Color("#b6cbb9"))
	var tiles := HBoxContainer.new()
	tiles.position = Vector2(70, 326)
	tiles.size = Vector2(716, 226)
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_theme_constant_override("separation", 24)
	for card in ["wan1", "tiao1", "tong8"]:
		var tile := TileView.new()
		tile.set_card(card, true)
		tile.set_unit(2.3)
		tiles.add_child(tile)
	hero.add_child(tiles)
	_label(hero, "幺鸡 · 八筒 · 碰杠成局", Vector2(68, 626), Vector2(722, 54), 32, Color("#e1ce9b"))
	_label(hero, "与朋友同桌，也能独自练牌", Vector2(68, 700), Vector2(722, 50), 28, Color("#a9c5b4"))
	_label(content, "开始一局", Vector2(984, 98), Vector2(760, 70), 46, Color("#f2deb0"))
	_label(content, "选择你的游戏方式", Vector2(984, 178), Vector2(760, 48), 28, Color("#b6cbb9"))
	var solo := _button("单机对局    ›", func(): get_tree().change_scene_to_file("res://scenes/GameTable.tscn"), true)
	solo.name = "SoloButton"
	solo.position = Vector2(984, 272)
	content.add_child(solo)
	var multiplayer_button := _button("联机房间    ›", func(): get_tree().change_scene_to_file("res://scenes/Lobby.tscn"), true)
	multiplayer_button.name = "MultiplayerButton"
	multiplayer_button.position = Vector2(984, 484)
	content.add_child(multiplayer_button)
	sound_settings = SoundSettings.new()
	add_child(sound_settings)
	var sound := _button("声音设置", sound_settings.open)
	sound.position = Vector2(984, 724)
	content.add_child(sound)
	rule_guide = load("res://scripts/ui/RuleGuide.gd").new()
	add_child(rule_guide)
	var rules := _button("新手规则", rule_guide.open)
	rules.position = Vector2(984, 838)
	content.add_child(rules)
	update_panel = UpdatePanel.new()
	add_child(update_panel)
	update_button = _button("检查更新", func():
		if UpdateManager.state == "error": UpdateManager.check_updates()
		update_panel.open())
	update_button.position = Vector2(1252, 724)
	content.add_child(update_button)
	var exit := _button("退出游戏", func(): get_tree().quit())
	exit.position = Vector2(1520, 724)
	content.add_child(exit)
	_label(content, "版本 " + UpdateManager.current_version(), Vector2(984, 906), Vector2(760, 48), 26, Color("#adc6b5"))
	update_status_label = _label(content, "启动时自动检查更新", Vector2(984, 950), Vector2(760, 42), 22, Color("#adc6b5"))
	UpdateManager.state_changed.connect(_update_badge)
	_update_badge()
	resized.connect(_layout)
	_layout()
	UpdateManager.maybe_check()
	PatchBoot.confirm_boot()

func _update_badge() -> void:
	match UpdateManager.state:
		"checking":
			update_button.text = "正在检查更新…"
			update_status_label.text = UpdateManager.message
		"available", "ready":
			update_button.text = "有新版 · " + str(UpdateManager.latest.version)
			update_status_label.text = UpdateManager.message
		"current", "no_release":
			update_button.text = "检查更新"
			update_status_label.text = UpdateManager.message
		"error":
			update_button.text = "检查失败 · 重试"
			update_status_label.text = UpdateManager.message
		_:
			update_button.text = "检查更新"
			update_status_label.text = "启动时自动检查更新"
	if UpdateManager.claim_startup_prompt(): update_panel.open()

func _layout() -> void:
	var factor := minf((size.x - 48) / MENU_SIZE.x, (size.y - 48) / MENU_SIZE.y)
	content.scale = Vector2.ONE * maxf(0.1, factor)
	content.position = (size - MENU_SIZE * content.scale) / 2.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if update_panel != null and update_panel.is_open(): update_panel.close()
		elif sound_settings != null and sound_settings.is_open(): sound_settings.close()

func _label(parent: Control, text: String, position_value: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position_value
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	return style

func _button(text: String, callback: Callable, entry: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = ENTRY_BUTTON_SIZE if entry else Vector2(224, 108)
	button.size = button.custom_minimum_size
	button.add_theme_font_size_override("font_size", 44 if entry else 28)
	button.add_theme_color_override("font_color", Color("#f7eccb") if entry else Color("#dceadd"))
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for state in ["normal", "hover", "pressed", "focus"]:
		var background := Color("#35694d") if entry else Color("#214737")
		if state == "hover": background = background.lightened(0.1)
		if state == "pressed": background = background.darkened(0.15)
		button.add_theme_stylebox_override(state, _style(background, Color("#c7af73") if entry else Color("#52775d")))
	button.pressed.connect(callback)
	return button
