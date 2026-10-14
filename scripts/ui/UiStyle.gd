extends RefCounted
## Shared visual language; no new autoload, compatible with resource patches.
const INK := Color("#f1f3e9")
const MUTED := Color("#a9c3b5")
const GOLD := Color("#edcc80")
const MOTION := preload("res://scripts/ui/UiMotion.gd")

static func usable_rect(control: Control) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, control.size)
	if OS.has_feature("android"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			var transform := control.get_viewport().get_screen_transform() * control.get_global_transform()
			bounds = bounds.intersection(transform.affine_inverse() * safe)
		if bounds.has_area(): bounds = bounds.grow(-28.0)
	return bounds

static func panel(background: Color = Color("#183c32"), border: Color = Color("#526c58"), radius: int = 24) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0, 0, 0, 0.22)
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 5)
	return box

static func button(button: Button, primary: bool = false) -> void:
	button.add_theme_color_override("font_color", Color("#283a2e") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("#283a2e") if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color("#283a2e") if primary else INK)
	button.add_theme_color_override("font_disabled_color", Color("#8aa398"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill := GOLD if primary else Color("#2d5945")
		if state == "hover": fill = fill.lightened(0.08)
		if state == "pressed": fill = fill.darkened(0.12)
		if state == "disabled": fill = Color("#233e33")
		var box := panel(fill, Color("#b99b61") if primary else Color("#60816b"), 18)
		box.shadow_size = 3
		button.add_theme_stylebox_override(state, box)
	var focus := panel(Color.TRANSPARENT, GOLD, 18)
	focus.shadow_size = 0
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	MOTION.bind_button(button)

static func field(field: Control) -> void:
	field.add_theme_stylebox_override("normal", panel(Color("#102e27"), Color("#486a56"), 12))
	field.add_theme_stylebox_override("focus", panel(Color("#13382c"), GOLD, 12))
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", MUTED)
