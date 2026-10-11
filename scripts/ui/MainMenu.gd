extends Control

var content: VBoxContainer

func _ready() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font = TileView._font()
	theme_resource.default_font_size = 22
	theme = theme_resource
	var background := ColorRect.new()
	background.color = Color("#174f3c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	content = VBoxContainer.new()
	content.size = Vector2(460, 410)
	content.add_theme_constant_override("separation", 18)
	add_child(content)
	var title := Label.new()
	title.text = "安顺麻将 · 捉鸡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#edcc80"))
	content.add_child(title)
	var tiles := HBoxContainer.new()
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles.add_theme_constant_override("separation", 10)
	for card in ["wan1", "tiao1", "tong8"]:
		var tile := TileView.new()
		tile.set_card(card, true)
		tile.set_unit(0.9)
		tiles.add_child(tile)
	content.add_child(tiles)
	content.add_child(_button("单机对局", func(): get_tree().change_scene_to_file("res://scenes/GameTable.tscn")))
	content.add_child(_button("联机房间", func(): get_tree().change_scene_to_file("res://scenes/Lobby.tscn")))
	content.add_child(_button("退出", func(): get_tree().quit()))
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var factor := minf(1.0, minf(size.x / 540.0, size.y / 520.0))
	content.scale = Vector2.ONE * factor
	content.position = (size - content.size * factor) / 2.0

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(460, 64)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#355e48") if state == "normal" else Color("#4b7b5d")
		style.border_color = Color("#8da98e")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button
