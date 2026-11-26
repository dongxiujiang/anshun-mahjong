extends PanelContainer
## 局内 / 房间 / 结算右上角轻量遥测条：实时显示 FPS，局域网与在线服务器额外显示连接状态与往返延迟（ms）。
## 仅在可见时以 2 Hz 刷新，且仅在数值或状态变化时更新文本/配色，零逐帧分配、零点击阻挡。

const UI := preload("res://src/app/AppTheme.gd")

const COLOR_GOOD := Color("#7ee8ad")
const COLOR_WARN := Color("#f4cb66")
const COLOR_BAD := Color("#ff7d70")
const COLOR_RECONNECT := Color("#ffae5c")
const COLOR_DISCONNECTED := Color("#ff6b6b")

const REFRESH_INTERVAL := 0.5
const COMPACT_WIDTH_THRESHOLD := 1360.0

var _stack: BoxContainer
var _fps_label: Label
var _sep_label: Label
var _net_row: HBoxContainer
var _net_dot: Control
var _net_label: Label

var _metrics_provider: Callable = Callable()
var _elapsed := 0.0
var _frames := 0
var _measured_fps := -1
var _compact_layout := false
var _last_signature := ""
var _net_dot_color := COLOR_GOOD


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 15
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	offset_right = -10
	offset_top = 8
	var style := UI.card(Color("#0c241ee3"), 9, 5, Color("#b9954c7a"), 1)
	style.set_content_margin(SIDE_LEFT, 9)
	style.set_content_margin(SIDE_RIGHT, 9)
	style.set_content_margin(SIDE_TOP, 4)
	style.set_content_margin(SIDE_BOTTOM, 4)
	add_theme_stylebox_override("panel", style)
	_build_children(false)
	if get_parent() is Control:
		(get_parent() as Control).resized.connect(refresh_now)
	hide()
	set_process(false)


func _build_children(vertical: bool) -> void:
	if is_instance_valid(_stack):
		remove_child(_stack)
		_stack.queue_free()
	_compact_layout = vertical
	_stack = VBoxContainer.new() if vertical else HBoxContainer.new()
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_stack.add_theme_constant_override("separation", 2 if vertical else 7)
	add_child(_stack)

	var font_size := 11 if vertical else 12
	_fps_label = UI.label("60 FPS", font_size, COLOR_GOOD)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if vertical else HORIZONTAL_ALIGNMENT_LEFT
	_stack.add_child(_fps_label)

	_sep_label = UI.label("│", 11, Color("#7ba08e88"))
	_sep_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sep_label.visible = false
	_stack.add_child(_sep_label)

	_net_row = HBoxContainer.new()
	_net_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_row.alignment = BoxContainer.ALIGNMENT_END if vertical else BoxContainer.ALIGNMENT_CENTER
	_net_row.add_theme_constant_override("separation", 5)
	_net_row.visible = false
	_stack.add_child(_net_row)

	_net_dot = Control.new()
	_net_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_dot.custom_minimum_size = Vector2(8, 8)
	_net_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_net_dot.draw.connect(_draw_net_dot)
	_net_row.add_child(_net_dot)

	_net_label = UI.label("", font_size, COLOR_GOOD)
	_net_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_row.add_child(_net_label)
	_last_signature = ""


func _draw_net_dot() -> void:
	if is_instance_valid(_net_dot):
		_net_dot.draw_circle(_net_dot.size * 0.5, 3.6, _net_dot_color, true, -1, true)


func configure(active: bool, provider: Callable = Callable()) -> void:
	_metrics_provider = provider
	visible = active
	set_process(active)
	if active:
		_elapsed = 0.0
		_frames = 0
		refresh_now()


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	if _elapsed >= REFRESH_INTERVAL:
		_measured_fps = int(round(float(_frames) / maxf(0.001, _elapsed)))
		_elapsed = 0.0
		_frames = 0
		refresh_now()


func refresh_now() -> void:
	if not visible or not is_instance_valid(_fps_label):
		return
	var metrics: Dictionary = _metrics_provider.call() if _metrics_provider.is_valid() else {}
	var net_active: bool = bool(metrics.get("active", false))
	var parent_width := get_parent_area_size().x
	var want_vertical: bool = net_active and parent_width > 0.0 and parent_width < COMPACT_WIDTH_THRESHOLD
	if want_vertical != _compact_layout:
		_build_children(want_vertical)

	var engine_fps := int(round(Engine.get_frames_per_second()))
	var fps := _measured_fps if _measured_fps >= 0 else engine_fps
	var fps_text := "%d FPS" % maxi(0, fps) if fps > 0 else "-- FPS"
	var fps_color := _fps_color(fps) if (_measured_fps >= 0 or engine_fps >= 15) else COLOR_GOOD

	var net_text := ""
	var net_color := COLOR_GOOD
	if net_active:
		var formatted := format_network(metrics)
		net_text = str(formatted.text)
		net_color = formatted.color

	var sig := "%s|%s|%s|%s|%s" % [fps_text, fps_color.to_html(false), str(net_active), net_text, net_color.to_html(false)]
	if sig == _last_signature:
		return
	_last_signature = sig

	_fps_label.text = fps_text
	_fps_label.add_theme_color_override("font_color", fps_color)
	_net_row.visible = net_active
	_sep_label.visible = net_active and not _compact_layout
	if net_active:
		_net_label.text = net_text
		_net_label.add_theme_color_override("font_color", net_color)
		if _net_dot_color != net_color:
			_net_dot_color = net_color
			_net_dot.queue_redraw()
	_reposition_top_right()


func _reposition_top_right() -> void:
	var min_sz := get_combined_minimum_size()
	offset_right = -10.0
	offset_left = -10.0 - min_sz.x
	offset_top = 8.0
	offset_bottom = 8.0 + min_sz.y


static func _fps_color(fps: int) -> Color:
	if fps >= 50 or fps == 0:
		return COLOR_GOOD
	if fps >= 30:
		return COLOR_WARN
	return COLOR_BAD


static func format_network(metrics: Dictionary) -> Dictionary:
	var mode := str(metrics.get("mode", ""))
	var prefix := "局域网" if mode == "lan" else "服务器"
	var state := str(metrics.get("state", "disconnected"))
	var rtt := int(metrics.get("rtt_ms", -1))
	match state:
		"connected":
			var label := "%s %dms" % [prefix, rtt] if rtt >= 0 else "%s 已连接" % prefix
			var col := COLOR_GOOD if (rtt < 0 or rtt < 60) else (COLOR_WARN if rtt < 150 else COLOR_BAD)
			return {"text": label, "color": col}
		"connecting":
			return {"text": "%s 连接中" % prefix, "color": COLOR_WARN}
		"reconnecting":
			return {"text": "%s 重连中" % prefix, "color": COLOR_RECONNECT}
		_:
			return {"text": "%s 已断开" % prefix, "color": COLOR_DISCONNECTED}
