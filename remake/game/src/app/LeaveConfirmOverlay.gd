extends Control

signal stay_requested
signal leave_requested

const UI := preload("res://src/app/AppTheme.gd")

static func build(app) -> void:
	var overlay = new()
	overlay.stay_requested.connect(app._dismiss_leave)
	overlay.leave_requested.connect(app._back_home)
	app._leave_overlay = overlay
	app.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	panel.add_child(content)
	var title := UI.label("要离开本局吗？", 27)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var stay := UI.button("继续打牌", overlay.stay_requested.emit)
	var leave := UI.button("离开", overlay.leave_requested.emit, true)
	for button in [stay, leave]:
		button.custom_minimum_size = Vector2(164, 54)
		actions.add_child(button)
		button.focus_neighbor_top = button.get_path()
		button.focus_neighbor_bottom = button.get_path()
	for pair in [[stay, leave], [leave, stay]]:
		pair[0].focus_next = pair[1].get_path()
		pair[0].focus_previous = pair[1].get_path()
		pair[0].focus_neighbor_left = pair[1].get_path()
		pair[0].focus_neighbor_right = pair[1].get_path()
	UI.focus_later(stay)
	app._register_modal(overlay,"leave")


