extends RefCounted
## 新中式雅致国风主题：深翠玉石 + 紫檀胡桃 + 暖鎏金描边与柔和投影层次。

const MotionFX = preload("res://src/presentation/MotionFX.gd")

const INK := Color("#f7f0df")
const MUTED := Color("#b8c4b6")
const GOLD := Color("#efd085")
const GOLD_BRIGHT := Color("#ffe5a3")
const GOLD_BORDER := Color("#b9954c")
const BACKDROP := Color("#0d1c18")
const PANEL := Color("#132b24")
const PANEL_LIGHT := Color("#1c3a30")
const BORDER := Color("#4c7462")
const ACCENT := Color("#b63c2f")


static func build() -> Theme:
	var result := Theme.new()
	const FONT_PATH := "res://src/app/assets/NotoSansSC-Regular.otf"
	if ResourceLoader.exists(FONT_PATH):
		result.default_font = load(FONT_PATH)
	result.default_font_size = 19
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 10)
	result.set_stylebox("panel", "PanelContainer", elevated_card(PANEL, 14, 14, BORDER, 1, 6))
	result.set_stylebox("panel", "PopupMenu", elevated_card(Color("#122923f8"), 12, 10, GOLD_BORDER, 1, 10))
	result.set_color("font_color", "Label", INK)
	for kind in ["Button", "OptionButton", "CheckButton"]:
		result.set_color("font_color", kind, INK)
		result.set_color("font_hover_color", kind, GOLD_BRIGHT)
		result.set_color("font_pressed_color", kind, Color("#fff5d8"))
		result.set_color("font_hover_pressed_color", kind, GOLD_BRIGHT)
		result.set_color("font_disabled_color", kind, Color("#8d9c92"))
		result.set_stylebox("normal", kind, elevated_card(Color("#1d3b31"), 11, 12, Color("#49705e"), 1, 3))
		result.set_stylebox("hover", kind, elevated_card(Color("#294f42"), 11, 12, Color("#89b29a"), 1, 4))
		result.set_stylebox("pressed", kind, card(Color("#275645"), 11, 12, GOLD_BORDER, 1))
		result.set_stylebox("hover_pressed", kind, elevated_card(Color("#2f6451"), 11, 12, GOLD, 1, 4))
		result.set_stylebox("disabled", kind, card(Color("#182822"), 11, 12, Color("#30453d"), 1))
		result.set_stylebox("focus", kind, card(Color.TRANSPARENT, 11, 11, GOLD, 2))
	# CheckButton 专用翡翠鎏金开关态（告别刺眼的红底激活态）
	result.set_stylebox("normal", "CheckButton", card(Color("#132720"), 10, 10, Color("#3b5b4e"), 1))
	result.set_stylebox("hover", "CheckButton", card(Color("#1b362d"), 10, 10, Color("#68907d"), 1))
	result.set_stylebox("pressed", "CheckButton", card(Color("#1a4b3a"), 10, 10, GOLD_BORDER, 1))
	result.set_stylebox("hover_pressed", "CheckButton", card(Color("#215c48"), 10, 10, GOLD, 1))
	result.set_color("font_pressed_color", "CheckButton", GOLD_BRIGHT)
	result.add_type("PrimaryButton")
	result.set_type_variation("PrimaryButton", "Button")
	result.set_stylebox("normal", "PrimaryButton", elevated_card(ACCENT, 11, 14, Color("#e08762"), 1, 4))
	result.set_stylebox("hover", "PrimaryButton", elevated_card(Color("#c94a3b"), 11, 14, GOLD_BRIGHT, 1, 5))
	result.set_stylebox("pressed", "PrimaryButton", card(Color("#8e2a20"), 11, 14, GOLD, 1))
	result.set_stylebox("normal", "LineEdit", card(Color("#0c1d18"), 10, 12, Color("#45695a"), 1))
	result.set_stylebox("focus", "LineEdit", card(Color("#10241e"), 10, 12, GOLD, 2))
	result.set_color("font_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("caret_color", "LineEdit", GOLD_BRIGHT)
	# TabContainer 新中式页签样式
	result.set_stylebox("panel", "TabContainer", card(Color("#10241ee6"), 12, 12, Color("#3e6253"), 1))
	result.set_stylebox("tab_selected", "TabContainer", card(Color("#284c3f"), 9, 10, GOLD_BORDER, 1))
	result.set_stylebox("tab_unselected", "TabContainer", card(Color("#152c25"), 9, 10, Color("#355246"), 1))
	result.set_stylebox("tab_hovered", "TabContainer", card(Color("#203f35"), 9, 10, Color("#7aa38e"), 1))
	result.set_color("font_selected_color", "TabContainer", GOLD_BRIGHT)
	result.set_color("font_unselected_color", "TabContainer", MUTED)
	result.set_color("font_hovered_color", "TabContainer", INK)
	# HSlider 滑条鎏金质感
	result.set_stylebox("slider", "HSlider", card(Color("#0e1f1a"), 4, 4, Color("#3f6052"), 1))
	result.set_stylebox("grabber_area", "HSlider", card(Color("#c89f50"), 4, 4, GOLD_BRIGHT, 1))
	result.set_stylebox("grabber_area_highlight", "HSlider", card(Color("#e6bc66"), 4, 4, GOLD_BRIGHT, 1))
	return result


static func card(fill: Color, radius: int = 14, inset: int = 14, border: Color = BORDER, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	for side in [SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM, SIDE_LEFT]:
		box.set_content_margin(side, inset)
	return box


static func elevated_card(fill: Color, radius: int = 14, inset: int = 14, border: Color = BORDER, width: int = 1, shadow: int = 6) -> StyleBoxFlat:
	var box := card(fill, radius, inset, border, width)
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0, maxf(1.0, float(shadow) * 0.35))
	return box


static func label(message: String = "", font_size: int = 19, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = message
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


static func menu_theme() -> Theme:
	var result := build()
	result.set_stylebox("normal", "PrimaryButton", elevated_card(Color("#e5b459"), 13, 12, Color("#ffe195"), 1, 5))
	result.set_stylebox("hover", "PrimaryButton", elevated_card(Color("#f0c26b"), 13, 12, Color("#fff0be"), 1, 6))
	result.set_stylebox("pressed", "PrimaryButton", card(Color("#c4933f"), 13, 12, Color("#ffe195"), 1))
	for state in ["normal", "hover", "pressed", "focus"]:
		var key: String = "font_color" if state == "normal" else "font_" + str(state) + "_color"
		result.set_color(key, "PrimaryButton", Color("#1b251c"))
	return result


static func button(message: String, callback: Callable, primary: bool = false) -> Button:
	var result := Button.new()
	result.text = message
	result.custom_minimum_size.y = 48
	if primary:
		result.theme_type_variation = "PrimaryButton"
	result.pressed.connect(callback)
	MotionFX.bind_button(result)
	return result


static func focus_later(control: Control) -> void:
	(func():
		if is_instance_valid(control) and not control.is_queued_for_deletion() and control.is_inside_tree() and control.is_visible_in_tree() and control.get_focus_mode_with_override() != Control.FOCUS_NONE:
			control.grab_focus()
	).call_deferred()
