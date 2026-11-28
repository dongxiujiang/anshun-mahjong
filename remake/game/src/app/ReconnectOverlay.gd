extends ColorRect
## Blocks the old table until the authenticated room state is usable again.

const UI := preload("res://src/app/AppTheme.gd")
signal retry_requested
signal return_requested

var message: Label
var retry: Button
var go_back: Button
var waiting_for_room := false
var spinner := Control.new()

func _ready() -> void:
	color = Color.BLACK
	modulate.a = 0.0
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	column.add_child(spinner)
	spinner.custom_minimum_size.y = 38
	spinner.draw.connect(func():
		var angle := Time.get_ticks_msec() * 0.005
		if UI.MotionFX.MotionConfig.is_detail():
			for i in 12:
				var start := angle + 4.7 * i / 12
				spinner.draw_arc(spinner.size / 2, 14, start, start + 4.7 / 12, 4,
					UI.GOLD.lerp(UI.GOLD_BRIGHT, i / 11.0), 3, true)
		else:
			spinner.draw_arc(spinner.size / 2.0, 14, angle, angle + 4.7, 28, Color.WHITE, 3, true))
	message = UI.label("", 24)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(actions)
	retry = UI.button("重试", retry_requested.emit)
	go_back = UI.button("返回大厅", return_requested.emit)
	actions.add_child(retry)
	actions.add_child(go_back)
	hide()
	set_process(false)

func display(waiting: bool, recovering: bool, closed: bool, immediate := false) -> void:
	message.text = "房间已关闭" if closed else ("重连中" if recovering else "正在同步牌局…")
	spinner.visible = not closed
	retry.visible = recovering and not closed
	go_back.visible = recovering
	set_process(waiting and not closed)
	if immediate and not waiting:
		waiting_for_room = false
		UI.MotionFX.stop(self)
		hide()
		return
	if waiting == waiting_for_room:
		return
	waiting_for_room = waiting
	mouse_behavior_recursive = MOUSE_BEHAVIOR_INHERITED if waiting else MOUSE_BEHAVIOR_DISABLED
	focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED if waiting else FOCUS_BEHAVIOR_DISABLED
	var spec := UI.MotionFX.MotionConfig.section("panel")
	color.a = spec.backdrop_alpha
	UI.MotionFX._slide(self, waiting, Vector2.ZERO,
		spec.backdrop_in_duration if waiting else spec.modal_out_duration, spec.ease_trans)

func _process(_delta: float) -> void:
	spinner.queue_redraw()
