extends VBoxContainer
## Two real miniature tables per page with crisp 2D character avatars. Joining always names the selected seat.
signal seat_selected(room: Dictionary, seat: int)
signal inspection_requested(room: Dictionary)
const UI = preload("res://src/app/AppTheme.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Art = preload("res://src/app/CharacterArt.gd")
const MotionConfig := preload("res://src/presentation/MotionConfig.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
const WINDS := ["东", "南", "西", "北"]
var rooms: Array = []
var page := 0
var _page_motion: Tween
var _pending: Array = []
var _has_pending := false
var _pressed := false
var _swiping := false
var _press := Vector2.ZERO
var _stage := Control.new()
var _container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _world := Node3D.new()
var _camera := Camera3D.new()
var _labels: Array = []
var _counter := Label.new()
var _pager: HBoxContainer
var quality := "smooth"
var empty_hint := "创建房间邀请好友开桌"

func apply_quality(value: String) -> void:
	quality = "detail" if value == "detail" else "smooth"
	_viewport.msaa_3d = Viewport.MSAA_2X if quality == "detail" else Viewport.MSAA_DISABLED
	for child in _world.get_children():
		if child is Table:
			child.apply_quality(quality)
	if not rooms.is_empty():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _ready() -> void:
	_stage.custom_minimum_size.y = 180
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_stage)
	_stage.add_child(_container)
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(_viewport)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.visible = false
	_viewport.add_child(_world)
	_world.add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 5.8
	_camera.position = Vector3(0, 8.5, 9.5)
	_camera.look_at(Vector3(0, 0.7, 0))
	_camera.current = true
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 12)
	_pager = controls
	add_child(controls)
	var prev_btn := UI.button("上一页", _turn.bind(-1))
	prev_btn.custom_minimum_size = Vector2(96, 40)
	controls.add_child(prev_btn)
	controls.add_child(_counter)
	var next_btn := UI.button("下一页", _turn.bind(1))
	next_btn.custom_minimum_size = Vector2(96, 40)
	controls.add_child(next_btn)
	_stage.resized.connect(func():
		if not rooms.is_empty():
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_position_labels())
	_viewport.size_changed.connect(_position_labels)
	_rebuild()

func set_rooms(rows: Array) -> void:
	if _pressed:
		_pending = rows.duplicate(true)
		_has_pending = true
		return
	if _page_motion:
		_page_motion.kill()
		_stage.modulate.a = 1.0
		UI.MotionFX.stop(_stage)
		_stage.offset_transform_position = Vector2.ZERO
	rooms = rows.duplicate(true)
	rooms.sort_custom(func(a, b):
		if (int(a.players) < 4) != (int(b.players) < 4):
			return int(a.players) < 4
		return str(a.number) < str(b.number))
	page = mini(page, maxi(0, (rooms.size() - 1) / 2))
	if is_node_ready():
		_rebuild()

func _rebuild() -> void:
	for item in _labels:
		_stage.remove_child(item.control)
		item.control.queue_free()
	_labels.clear()
	for child in _world.get_children():
		if child != _camera:
			_world.remove_child(child)
			child.queue_free()
	_counter.text = "%d / %d" % [page + 1, maxi(1, ceili(rooms.size() / 2.0))]
	if is_instance_valid(_pager):
		_pager.visible = rooms.size() > 2
	if rooms.is_empty():
		var empty_card := PanelContainer.new()
		empty_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_card.add_theme_stylebox_override("panel", UI.card(Color("#102920aa"), 14, 14, Color("#57705b78")))
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		empty_card.add_child(col)
		var headline := UI.label("暂无开放牌桌", 22, UI.GOLD_BRIGHT)
		headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(headline)
		var hint := UI.label(empty_hint, 16, UI.MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(hint)
		_stage.add_child(empty_card)
		_labels.append({"control": empty_card, "point": Vector3.ZERO, "size": Vector2(460, 128), "centered": true})
		_container.visible = false
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_container.visible = true
		for index in range(page * 2, mini(page * 2 + 2, rooms.size())):
			_build_room(rooms[index], Vector3(-3.65 if index % 2 == 0 else 3.65, 0, 0))
		_camera.make_current()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_position_labels.call_deferred()

func _build_room(room: Dictionary, center: Vector3) -> void:
	var table := Table.new()
	table.frame_camera_enabled = false
	table.set_meta("room_number", str(room.number))
	_world.add_child(table)
	table.camera.current = false
	table.apply_quality(quality)
	_camera.environment = table.camera.environment
	table.scale = Vector3.ONE * (1.45 / table.table_edge())
	table.position = center + Vector3(0, 0.5, 0)
	if center.x > 0:
		table._key_light.hide()
	for x in [-1.2, 1.2]:
		for z in [-1.2, 1.2]:
			_box(center + Vector3(x, 0.24, z), Vector3(0.13, 0.48, 0.13), Color("594638"))
	var heading := UI.label("%s · %s" % [room.number, room.name], 19, Color("#f2dc9b"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_child(heading)
	_labels.append({"control": heading, "point": center, "size": Vector2(300, 34), "heading": true})
	var known: bool = room.get("seats") is Array and room.seats.size() == 4 and room.seats.all(func(member):
		return member is Dictionary and member.get("player_id") is String and member.get("nickname") is String and (member.get("score") is float or member.get("score") is int))
	for seat in 4:
		var member: Dictionary = room.seats[seat] if known else {}
		var occupied := not str(member.get("player_id", "")).is_empty()
		var away := occupied and bool(member.get("away", not member.get("connected", true)))
		var facing := Layout.facing(seat)
		var seat_color := Color("7a6d56") if away else (Color("c89d4e") if occupied else Color("345a4c"))
		_box(center + facing * Vector3(0, 0.29, 1.95), Vector3(0.54, 0.10, 0.48), seat_color)
		var text := "%s家 · 空座" % WINDS[seat]
		if not known:
			text = "查看座位"
		elif occupied:
			text = "%s\n%d分" % [member.nickname, int(member.score)]
			if member.player_id == room.get("owner_player_id", ""):
				text += " · 房主"
			if away:
				text += " · 暂离"
		var button := UI.button(text, _select.bind(room.duplicate(true), seat, known))
		button.disabled = occupied or int(room.players) >= 4
		button.add_theme_color_override("font_disabled_color", UI.INK)
		button.set_meta("page_label", "%s房间%s家座位" % [room.number, WINDS[seat]])
		if occupied:
			var portrait := Art.portrait(int(member.get("avatar", 1)))
			if portrait != null:
				button.icon = portrait
				button.expand_icon = true
				button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			if away:
				button.modulate = Color(0.75, 0.78, 0.76, 0.92)
		_stage.add_child(button)
		button.add_theme_font_size_override("font_size", 15)
		_labels.append({"control": button, "point": center + facing * Vector3(0, 1.45, 2.25), "size": Vector2(146, 52)})

func _position_labels() -> void:
	if not _camera.is_inside_tree() or _stage.size.x < 1:
		return
	for item in _labels:
		var point: Vector2 = _stage.size * 0.5 if item.get("centered", false) else _camera.unproject_position(item.point)
		if item.get("heading", false):
			point.y = _stage.size.y - 24
		item.control.size = item.size.max(item.control.get_combined_minimum_size())
		item.control.position = point - item.control.size / 2
		item.control.position = item.control.position.clamp(Vector2(4, 4), (_stage.size - item.control.size - Vector2(4, 4)).max(Vector2(4, 4)))

func transition_origin(number: String) -> Dictionary:
	for table in _world.get_children():
		if not table is Table or table.get_meta("room_number", "") != number:
			continue
		var rect := _container.get_global_rect()
		if rect.size.x < 1 or rect.size.y < 1:
			return {}
		var center := _camera.unproject_position(table.global_position)
		var corners := []
		for x in [-table.table_edge(), table.table_edge()]:
			for z in [-table.table_edge(), table.table_edge()]:
				corners.append(rect.position + _camera.unproject_position(table.global_transform * Vector3(x, 0, z)) * rect.size / Vector2(_viewport.size))
		return {
			"basis": _camera.global_basis.orthonormalized(),
			"height": _camera.size / table.scale.x,
			"rect": rect,
			"center": rect.position + center * rect.size / Vector2(_viewport.size),
			"corners": corners,
		}
	return {}

func _box(position_3d: Vector3, size_3d: Vector3, color: Color) -> void:
	var shape := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size_3d
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	box.material = material
	shape.mesh = box
	shape.position = position_3d
	_world.add_child(shape)

func _select(room: Dictionary, seat: int, known: bool) -> void:
	if _swiping:
		return
	if known:
		seat_selected.emit(room, seat)
	else:
		inspection_requested.emit(room)

func _turn(delta: int) -> void:
	var next := clampi(page + delta, 0, maxi(0, ceili(rooms.size() / 2.0) - 1))
	if next == page:
		return
	page = next
	if _page_motion:
		_page_motion.kill()
	var overlay := MotionConfig.section("overlay")
	var curve: int = MotionConfig.value("panel", "ease_trans")
	if MotionConfig.is_detail():
		_rebuild()
		_stage.offset_transform_enabled = true
		_stage.offset_transform_visual_only = true
		_stage.offset_transform_position = Vector2.RIGHT * delta * float(overlay.popup_offset_y)
		_stage.modulate.a = 0.0
		_page_motion = create_tween().set_parallel(true).set_trans(curve).set_ease(Tween.EASE_OUT)
		_page_motion.tween_property(_stage, "offset_transform_position", Vector2.ZERO, overlay.toast_in)
		_page_motion.tween_property(_stage, "modulate:a", 1.0, overlay.toast_in)
	else:
		var half: float = overlay.badge_in * 0.5
		_page_motion = create_tween().set_trans(curve).set_ease(Tween.EASE_IN_OUT)
		_page_motion.tween_property(_stage, "modulate:a", 0.0, half)
		_page_motion.tween_callback(_rebuild)
		_page_motion.tween_property(_stage, "modulate:a", 1.0, half)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or get_mouse_filter_with_override() == MOUSE_FILTER_IGNORE:
		return
	var down: bool = event is InputEventScreenTouch and event.pressed or event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	var up: bool = event is InputEventScreenTouch and not event.pressed or event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	if down:
		var point: Vector2 = get_global_mouse_position() if event is InputEventMouseButton else event.position
		if not _stage.get_global_rect().has_point(point):
			return
		_pressed = true
		_swiping = false
		_press = point
	elif up and _pressed:
		var point: Vector2 = get_global_mouse_position() if event is InputEventMouseButton else event.position
		if absf(point.x - _press.x) > 80:
			_swiping = true
			_turn.call_deferred(-1 if point.x > _press.x else 1)
		_pressed = false
		_flush_pending.call_deferred()

func _flush_pending() -> void:
	if _has_pending:
		_has_pending = false
		set_rooms(_pending)
