extends SceneTree

const Badge := preload("res://src/app/PlayerBadge.gd")
const UI := preload("res://src/app/AppTheme.gd")

var _badge := Badge.new()
var _pressed := []
var _downs := 0
var _ups := 0
var _underneath_presses := 0
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var surface := Control.new()
	surface.theme = UI.build()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(surface)
	var underneath := Button.new()
	underneath.position = Vector2(60, 60)
	underneath.size = Vector2(400, 110)
	surface.add_child(underneath)
	underneath.pressed.connect(func(): _underneath_presses += 1)
	var holder := VBoxContainer.new()
	holder.position = underneath.position
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(holder)
	holder.add_child(_badge)
	_badge.button_down.connect(func(): _downs += 1)
	_badge.button_up.connect(func(): _ups += 1)
	_badge.player_pressed.connect(func(context): _pressed.append(context))
	var member := {"nickname": "甲乙丙丁戊己", "score": -1234}
	var flags := PackedStringArray(["庄", "暂离", "报听"])
	var target := {"room_instance_id": "first-room", "seat": 2, "player_id": "first-player"}
	_badge.show_player(member, flags, false, target, true)
	await process_frame
	await process_frame
	_check_layout()
	_check_colors(member, flags, target)

	var point := _badge.name_label.get_global_rect().get_center()
	_move(point)
	_mouse(point, true)
	check(_downs == 1 and _pressed.is_empty() and _badge.button_pressed, "mouse down reaches the badge and waits for release")
	_mouse(point, false)
	check(_ups == 1 and _pressed == [target] and _underneath_presses == 0, "real mouse release emits exactly the visible player context")
	point = _badge.score_label.get_global_rect().get_center()
	_move(point)
	_mouse(point, true)
	_badge.show_player(member.duplicate(), flags, false, target.duplicate(), true)
	_mouse(point, false)
	check(_downs == 2 and _ups == 2 and _pressed == [target, target], "the same room and player refresh permits a pending press")

	_mouse(point, true)
	var replacement := target.duplicate()
	replacement.player_id = "replacement-player"
	_badge.show_player(member, flags, false, replacement, true)
	_mouse(point, false)
	check(_downs == 3 and _ups == 3 and _pressed.size() == 2, "changing the occupant during a mouse hold cancels release")
	_mouse(point, true)
	var other_room := replacement.duplicate()
	other_room.room_instance_id = "second-room"
	_badge.show_player(member, flags, false, other_room, true)
	_mouse(point, false)
	check(_downs == 4 and _ups == 4 and _pressed.size() == 2, "changing the room during a mouse hold cancels release")
	_mouse(point, true)
	_badge.cancel_press()
	_mouse(point, false)
	check(_downs == 5 and _ups == 5 and _pressed.size() == 2, "explicit cancellation blocks the delayed mouse release")
	_mouse(point, true)
	_mouse(point, false)
	check(_pressed.size() == 3 and _pressed.back() == other_room, "new pointer click targets the current room after cancellations")

	_mouse(point, true)
	_badge.show_player(member, flags, false, other_room, false)
	_mouse(point, false)
	check(_badge.disabled and _badge.mouse_filter == Control.MOUSE_FILTER_IGNORE and _badge.focus_mode == Control.FOCUS_NONE, "disabled badge ignores mouse hit testing and keyboard focus")
	var before := _downs
	_mouse(point, true)
	_mouse(point, false)
	check(_downs == before and _pressed.size() == 3 and _underneath_presses == 1, "disabled badge blocks the held activation and passes a fresh click to the underlay")

	_badge.show_player(member, flags, false, other_room, true)
	_badge.grab_focus()
	check(root.gui_get_focus_owner() == _badge, "enabled badge accepts keyboard focus")
	_key(true)
	check(_downs == before + 1 and _pressed.size() == 3, "Enter key down uses real focused button input")
	_key(false)
	check(_pressed.size() == 4 and _pressed.back() == other_room, "Enter key release uses the same context as pointer input")
	_key(true)
	_badge.show_player(member, flags, false, replacement, true)
	_key(false)
	check(_pressed.size() == 4, "a late keyboard release cannot target a changed room")
	surface.queue_free()
	await process_frame
	print("Player badge: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check_layout() -> void:
	var badge_rect := _badge.get_global_rect()
	var name_rect := _badge.name_label.get_global_rect()
	var score_rect := _badge.score_label.get_global_rect()
	check(badge_rect.size.x >= 48 and badge_rect.size.y >= 48 and _badge.get_combined_minimum_size().y >= 48, "badge provides a target at least 48 by 48")
	check(_badge.name_label.text == "甲乙丙丁戊己" and _badge.name_label.get_line_count() == 1 and name_rect.size.x >= _badge.name_label.get_combined_minimum_size().x and badge_rect.encloses(name_rect), "six-character nickname fits on one full line")
	check(_badge.score_label.text == "-1234 分 · 庄 · 暂离 · 报听" and _badge.score_label.get_line_count() == 1 and score_rect.size.x >= _badge.score_label.get_combined_minimum_size().x and badge_rect.encloses(score_rect) and name_rect.end.y <= score_rect.position.y, "score and flags are complete on a separate non-overlapping line")

func _check_colors(member: Dictionary, flags: PackedStringArray, target: Dictionary) -> void:
	var score := _badge.score_label.text
	_badge.set_mic_active(true)
	check(_badge.name_label.get_theme_color("font_color") == Color.WHITE and _badge.mic_dot.modulate.a==1.0 and _badge.mic_dot.self_modulate==Badge.ACTIVE and _badge.score_label.get_theme_color("font_color") == Color.WHITE and _badge.turn_dot.modulate.a == 0.0, "actual microphone state lights a green dot beside the white name")
	_badge.show_player(member, flags, true, target, true)
	_badge.set_mic_active(true,true)
	check(_badge.mic_dot.modulate.a==1.0 and _badge.mic_dot.self_modulate==Badge.MUTED and _badge.mic_dot.get_child_count()==0, "muted listener sees a solid red dot without a slash")
	_badge.set_mic_active(true,false)
	check(_badge.mic_dot.self_modulate==Badge.ACTIVE and _badge.mic_dot.modulate.a==1.0, "restoring listening changes the dot back to green")
	_badge.set_mic_active(false)
	check(_badge.name_label.get_theme_color("font_color") == Color.WHITE and _badge.mic_dot.modulate.a==0.0 and _badge.score_label.text == score and _badge.score_label.get_theme_color("font_color") == Color.WHITE and _badge.turn_dot.modulate.a == 1.0 and _badge.turn_dot.text=="▶" and _badge.turn_dot.get_theme_color("font_color") == Color.WHITE, "white turn arrow and score remain independent when the green microphone dot turns off")
	_badge.show_player(member, flags, false, target, true)

func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func _mouse(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func _key(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = down
	root.push_input(event, true)

func check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr(description)
