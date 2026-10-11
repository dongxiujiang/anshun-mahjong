extends Control

var content: VBoxContainer
var status: Label
var join_button: Button
var address: LineEdit

func _ready() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font = TileView._font()
	theme_resource.default_font_size = 22
	theme = theme_resource
	var background := ColorRect.new()
	background.color = Color("#174f3c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	content = VBoxContainer.new()
	content.size = Vector2(500, 430)
	content.add_theme_constant_override("separation", 18)
	add_child(content)
	var title := Label.new()
	title.text = "联机房间"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)
	content.add_child(_button("创建房间", _on_host))
	address = LineEdit.new()
	address.placeholder_text = "主机 IP 地址"
	address.text = "127.0.0.1"
	address.custom_minimum_size = Vector2(500, 60)
	content.add_child(address)
	join_button = _button("加入房间", _on_join)
	content.add_child(join_button)
	status = Label.new()
	status.custom_minimum_size = Vector2(500, 60)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 18)
	content.add_child(status)
	content.add_child(_button("返回", func():
		Network.reset()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")))
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var factor := minf(1.0, minf(size.x / 580.0, size.y / 540.0))
	content.scale = Vector2.ONE * factor
	content.position = (size - content.size * factor) / 2.0

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(500, 60)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#355e48") if state == "normal" else Color("#4b7b5d")
		style.border_color = Color("#8da98e")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	return button

func _on_host() -> void:
	Network.reset()
	if Network.start_host(false, true, 7500):
		get_tree().change_scene_to_file("res://scenes/GameTable.tscn")
	else:
		status.text = "创建失败，端口已被占用"

func _on_join() -> void:
	Network.reset()
	var ip := address.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	join_button.disabled = true
	status.text = "连接中…"
	if not Network.start_client(ip, 7500):
		status.text = "连接失败，请检查主机地址"
		join_button.disabled = false
		return
	Network.net_node.room_ready.connect(func(_seat):
		get_tree().change_scene_to_file("res://scenes/GameTable.tscn"))
	Network.net_node.connection_error.connect(func(message):
		status.text = message
		join_button.disabled = false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Network.reset()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
