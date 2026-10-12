extends Control
## First-run rules/tutorial panel. It is deliberately self-contained so it can
## be hot-updated without changing scenes or autoload registration.

const DESIGN := Vector2(1500, 900)
const PAGES := [
	{"title": "先认识牌桌", "body": "四位玩家围成一桌。你的手牌在下方，摸到的牌单独放在最右侧。轮到你时，选择一张牌打出；牌桌上的分数是累计分。"},
	{"title": "碰、杠和报听", "body": "只能碰和杠，不能吃。杠后从牌尾补牌。暗杠先扣在桌面，下一轮自己出牌后翻开。第一次摸牌后的出牌机会，打出后能听牌可以报听。"},
	{"title": "鸡牌怎么计分", "body": "一条和八筒是鸡牌。两种鸡牌各自全场第一张打出的是冲锋鸡。胡牌时翻牌头的下一张，取本牌和首尾循环的上下牌；命中一条或八筒时对应鸡牌翻倍。"},
	{"title": "常见胡牌", "body": "小七对 24 分，龙七对 44 分，大队子 14 分，清一色 24 分。自摸 +4，杠开 +9，最后四张自摸 +9，无鸡 +14。不同付款关系会在结算卡片逐项列出。"},
	{"title": "联机和断线", "body": "联机房间由房主/服务器权威处理，客户端接收可靠状态快照。掉线后会保留座位并由人机暂代；在保留时间内重新输入同一昵称即可恢复原座位和手牌。"},
]
var panel: Panel
var title_label: Label
var body_label: Label
var page_label: Label
var previous_button: Button
var next_button: Button
var page := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.07, 0.05, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = Panel.new()
	panel.size = Vector2(1120, 650)
	panel.add_theme_stylebox_override("panel", _style(Color("#173d31"), Color("#c7af73")))
	add_child(panel)
	title_label = _label("", Vector2(64, 54), Vector2(992, 64), 42, Color("#f2deb0"))
	body_label = _label("", Vector2(64, 150), Vector2(992, 300), 30, Color("#e0ece1"))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_label = _label("", Vector2(64, 500), Vector2(260, 42), 24, Color("#adc6b5"))
	previous_button = _button("上一步", _previous, Vector2(530, 548), Vector2(180, 68))
	next_button = _button("下一步", _next, Vector2(730, 548), Vector2(180, 68))
	_button("关闭", close, Vector2(930, 548), Vector2(130, 68))
	resized.connect(_layout)
	_layout()

func open() -> void:
	page = 0
	visible = true
	_refresh()

func close() -> void:
	visible = false

func _next() -> void:
	page = mini(PAGES.size() - 1, page + 1)
	_refresh()

func _previous() -> void:
	page = maxi(0, page - 1)
	_refresh()

func _refresh() -> void:
	var item: Dictionary = PAGES[page]
	title_label.text = item.title
	body_label.text = item.body
	page_label.text = "%d / %d" % [page + 1, PAGES.size()]
	previous_button.disabled = page == 0
	next_button.disabled = page == PAGES.size() - 1

func _layout() -> void:
	if panel == null: return
	panel.position = (size - panel.size) / 2.0

func _label(value: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	return label

func _button(value: String, callback: Callable, pos: Vector2, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.text = value
	button.position = pos
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 25)
	button.add_theme_stylebox_override("normal", _style(Color("#35694d"), Color("#52775d")))
	button.add_theme_stylebox_override("hover", _style(Color("#49775a"), Color("#c7af73")))
	button.pressed.connect(callback)
	panel.add_child(button)
	return button

func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	return style
