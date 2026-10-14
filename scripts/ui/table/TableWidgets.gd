extends RefCounted
## 统一牌桌控件创建和按钮样式，供各组件共用。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

func _make_tile(card: String, up: bool, unit: float = UI.TILE_UNIT) -> TileView:
	var tile := TileView.new()
	tile.set_card(card, up)
	tile.set_unit(unit)
	return tile

func _put_tile(parent: Control, tile: TileView, pos: Vector2) -> void:
	parent.add_child(tile)
	tile.set_table_position(pos)

func _box(parent: Control) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color = UI.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _style(color: Color, border: Color, radius: int, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_width)
	return style

func _button(text: String, callback: Callable, dimensions: Vector2, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = dimensions
	button.size = dimensions
	button.add_theme_font_size_override("font_size", UI.BUTTON_FONT_SIZE)
	button.add_theme_color_override("font_color", UI.BUTTON_PRIMARY_INK if primary else UI.INK)
	button.add_theme_color_override("font_hover_color", UI.BUTTON_PRIMARY_INK if primary else UI.INK)
	button.add_theme_stylebox_override("normal", _style(UI.GOLD if primary else UI.BUTTON_NORMAL, UI.BUTTON_BORDER, UI.BUTTON_RADIUS, 1))
	button.add_theme_stylebox_override("hover", _style(UI.BUTTON_PRIMARY_HOVER if primary else UI.BUTTON_HOVER, UI.GOLD, UI.BUTTON_RADIUS, 1))
	button.add_theme_stylebox_override("pressed", _style(UI.BUTTON_PRIMARY_PRESSED if primary else UI.BUTTON_PRESSED, UI.GOLD, UI.BUTTON_RADIUS, 1))
	button.add_theme_stylebox_override("disabled", _style(UI.BUTTON_DISABLED, UI.BUTTON_DISABLED_BORDER, UI.BUTTON_RADIUS, 1))
	button.add_theme_stylebox_override("focus", _style(UI.TRANSPARENT_FILL, UI.GOLD, UI.BUTTON_RADIUS, 2))
	preload("res://scripts/ui/UiMotion.gd").bind_button(button)
	button.pressed.connect(callback)
	return button

func _clear_box(box: Node) -> void:
	# Detach immediately: consecutive synchronous state updates share a frame.
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _cn(card: String) -> String:
	if card == "":
		return "-"
	return "%d%s" % [Tiles.rank(card), {"wan": "万", "tiao": "条", "tong": "筒"}.get(Tiles.suit(card), "")]
