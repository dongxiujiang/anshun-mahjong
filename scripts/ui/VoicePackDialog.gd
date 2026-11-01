extends Control
## 每个座位的音色包选择。C 阶段无音频时由 AudioManager 回退默认音色。

signal pack_selected(seat: int, pack_id: String)
signal preview_requested(seat: int, pack_id: String)
signal test_all_requested

const STYLE := preload("res://scripts/ui/UiStyle.gd")
const REGISTRY := preload("res://scripts/core/VoicePackRegistry.gd")
const SIZE := Vector2(980, 620)

var _panel: Panel
var _selects := {}
var _previews := {}
var _seat_labels := {}
const WINDS := ["东", "南", "西", "北"]
var _test_button: Button
var _test_status: Label
var _close: Button
var _hint: Label
var _my_seat := 0
var _is_host := false
var _packs := ["luoxiaohei", "wuyuanzhao", "wangye", "nvyou"]
var _picker: Control
var _picker_panel: Panel
var _picker_grid: GridContainer
var _picker_seat := 0

func _ready() -> void:
	name = "VoicePackDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 330
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.04, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_panel = Panel.new()
	_panel.size = SIZE
	_panel.add_theme_stylebox_override("panel", STYLE.panel())
	add_child(_panel)
	var title := Label.new()
	title.text = "座位音色"
	title.position = Vector2(34, 22)
	title.size = Vector2(690, 44)
	title.add_theme_font_override("font", TileView._font())
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", STYLE.GOLD)
	_panel.add_child(title)
	_hint = Label.new()
	_hint.position = Vector2(34, 76)
	_hint.size = Vector2(690, 38)
	_hint.add_theme_font_override("font", TileView._font())
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", STYLE.MUTED)
	_panel.add_child(_hint)
	for seat in 4:
		var label := Label.new()
		label.text = "%s位" % WINDS[seat]
		label.position = Vector2(24, 128 + seat * 82)
		label.size = Vector2(140, 56)
		label.add_theme_font_override("font", TileView._font())
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", STYLE.INK)
		_panel.add_child(label)
		_seat_labels[seat] = label
		var select := Button.new()
		select.position = Vector2(170, 122 + seat * 82)
		select.size = Vector2(390, 58)
		select.custom_minimum_size = Vector2(390, 58)
		select.add_theme_font_override("font", TileView._font())
		select.add_theme_font_size_override("font_size", 24)
		STYLE.button(select, false)
		select.pressed.connect(func(): _open_picker(seat))
		_panel.add_child(select)
		_selects[seat] = select
		var preview := Button.new()
		preview.text = "试听"
		preview.position = Vector2(580, 122 + seat * 82)
		preview.size = Vector2(150, 58)
		preview.add_theme_font_override("font", TileView._font())
		preview.add_theme_font_size_override("font_size", 24)
		STYLE.button(preview, false)
		preview.pressed.connect(func(): preview_requested.emit(seat, str(_packs[seat])))
		_panel.add_child(preview)
		_previews[seat] = preview
	_build_picker()
	_close = Button.new()
	_close.text = "关闭"
	_close.position = Vector2(700, 520)
	_close.size = Vector2(240, 70)
	_close.add_theme_font_override("font", TileView._font())
	_close.add_theme_font_size_override("font_size", 24)
	STYLE.button(_close, false)
	_close.pressed.connect(close)
	_panel.add_child(_close)
	_test_button = Button.new()
	_test_button.text = "测试全部语音"
	_test_button.position = Vector2(440, 520)
	_test_button.size = Vector2(240, 70)
	_test_button.add_theme_font_override("font", TileView._font())
	_test_button.add_theme_font_size_override("font_size", 22)
	STYLE.button(_test_button, false)
	_test_button.pressed.connect(func(): test_all_requested.emit())
	_panel.add_child(_test_button)
	_test_status = Label.new()
	_test_status.position = Vector2(34, 520)
	_test_status.size = Vector2(390, 70)
	_test_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_status.add_theme_font_override("font", TileView._font())
	_test_status.add_theme_font_size_override("font_size", 18)
	_test_status.add_theme_color_override("font_color", STYLE.MUTED)
	_panel.add_child(_test_status)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.voice_test_progress.connect(_on_test_progress)
	resized.connect(_layout)
	hide()

func open(packs: Array, my_seat: int, is_host: bool) -> void:
	_my_seat = clampi(my_seat, 0, 3)
	_is_host = is_host
	_packs = []
	var used := {}
	for seat in 4:
		var pack_id := REGISTRY.concrete_for_seat(packs[seat] if seat < packs.size() else "default", seat)
		if used.has(pack_id):
			for candidate in REGISTRY.ORDER:
				if not used.has(candidate):
					pack_id = candidate
					break
		used[pack_id] = true
		_packs.append(pack_id)
	var roles := ["自己", "下家", "对家", "上家"]
	for seat in 4:
		var relative := posmod(seat - _my_seat, 4)
		_seat_labels[seat].text = "%s·%s位" % [roles[relative], WINDS[seat]]
		var select: Button = _selects[seat]
		select.disabled = not is_host and seat != _my_seat
	_refresh_usage()
	_hint.text = "房主可独立设置每个座位，四个座位不能重复。" if is_host \
		else "只能修改自己的座位，四个座位不能重复。"
	_picker.hide()
	show()
	_layout()

func _used_by_other(seat: int, pack_id: String) -> bool:
	for index in 4:
		if index != seat and _packs[index] == pack_id:
			return true
	return false

func _refresh_usage() -> void:
	for seat in 4:
		var select: Button = _selects[seat]
		select.text = REGISTRY.label(_packs[seat])

func _build_picker() -> void:
	_picker = Control.new()
	_picker.name = "VoicePackPicker"
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.z_index = 340
	add_child(_picker)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.04, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.add_child(shade)
	_picker_panel = Panel.new()
	_picker_panel.size = Vector2(760, 760)
	_picker_panel.add_theme_stylebox_override("panel", STYLE.panel())
	_picker.add_child(_picker_panel)
	var title := Label.new()
	title.text = "选择音色"
	title.position = Vector2(28, 18)
	title.size = Vector2(500, 42)
	title.add_theme_font_override("font", TileView._font())
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", STYLE.GOLD)
	_picker_panel.add_child(title)
	_picker_grid = GridContainer.new()
	_picker_grid.columns = 2
	_picker_grid.position = Vector2(24, 78)
	_picker_grid.size = Vector2(712, 600)
	_picker_grid.add_theme_constant_override("h_separation", 16)
	_picker_grid.add_theme_constant_override("v_separation", 8)
	_picker_panel.add_child(_picker_grid)
	var close := Button.new()
	close.text = "关闭"
	close.position = Vector2(540, 664)
	close.size = Vector2(190, 66)
	close.add_theme_font_override("font", TileView._font())
	close.add_theme_font_size_override("font_size", 24)
	STYLE.button(close, false)
	close.pressed.connect(_close_picker)
	_picker_panel.add_child(close)
	_picker.hide()

func _open_picker(seat: int) -> void:
	if bool(_selects[seat].disabled):
		return
	_picker_seat = seat
	for child in _picker_grid.get_children():
		child.queue_free()
	for id in REGISTRY.ORDER:
		var button := Button.new()
		button.text = ("✓ " if id == _packs[seat] else "") + REGISTRY.label(id)
		button.custom_minimum_size = Vector2(340, 52)
		button.size = Vector2(340, 52)
		button.add_theme_font_override("font", TileView._font())
		button.add_theme_font_size_override("font_size", 24)
		button.disabled = _used_by_other(seat, id)
		STYLE.button(button, id == _packs[seat])
		button.pressed.connect(_choose_picker.bind(id))
		_picker_grid.add_child(button)
	_picker.show()
	_layout_picker()

func _choose_picker(pack_id: String) -> void:
	if _used_by_other(_picker_seat, pack_id):
		_hint.text = "这个音色已被其他座位使用，请换一个。"
		return
	_packs[_picker_seat] = pack_id
	_refresh_usage()
	_hint.text = "房主可独立设置每个座位，四个座位不能重复。" if _is_host \
		else "只能修改自己的座位，四个座位不能重复。"
	pack_selected.emit(_picker_seat, pack_id)
	_close_picker()

func _close_picker() -> void:
	if _picker != null:
		_picker.hide()

func _layout_picker() -> void:
	if _picker_panel == null or not _picker.visible:
		return
	var bounds := STYLE.usable_rect(self)
	if not bounds.has_area():
		bounds = Rect2(Vector2.ZERO, get_viewport_rect().size)
	var factor := minf(1.0, minf((bounds.size.x - 32.0) / 760.0, (bounds.size.y - 32.0) / 760.0))
	_picker_panel.scale = Vector2.ONE * maxf(0.1, factor)
	_picker_panel.position = bounds.position + (bounds.size - Vector2(760, 760) * _picker_panel.scale) * 0.5

func close() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.stop_voice_test()
	_close_picker()
	hide()

func _on_test_progress(pack_id: String, key: String, index: int, total: int) -> void:
	if _test_status == null:
		return
	if pack_id == "" or total <= 0:
		_test_status.text = ""
		return
	_test_status.text = "测试中 %d/%d\n%s · %s" % [index, total, REGISTRY.label(pack_id), key]

func _layout() -> void:
	if _panel == null: return
	var bounds := STYLE.usable_rect(self)
	if not bounds.has_area(): bounds = Rect2(Vector2.ZERO, get_viewport_rect().size)
	var factor := minf(1.0, minf((bounds.size.x - 32.0) / SIZE.x, (bounds.size.y - 32.0) / SIZE.y))
	_panel.scale = Vector2.ONE * maxf(0.1, factor)
	_panel.position = bounds.position + (bounds.size - SIZE * _panel.scale) * 0.5
	_layout_picker()
