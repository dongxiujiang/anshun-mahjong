extends Control
const STYLE := preload("res://scripts/ui/UiStyle.gd")
const MOTION := preload("res://scripts/ui/UiMotion.gd")
## First-run rules/tutorial panel. It is deliberately self-contained so it can
## be hot-updated without changing scenes or autoload registration.

const DESIGN := Vector2(1500, 900)
const PAGES := [
	{"title": "牌局顺序", "body": "全副108张牌，庄家14张、闲家13张。座位编号递增为顺时针；起手按庄、下家、对家、上家的顺时针方向依次拿牌，之后仍按顺时针轮转摸牌、出牌和检查响应，杠后从牌尾补牌。只能碰和杠，不能吃。"},
	{"title": "碰、杠与过牌", "body": "胡牌优先于碰，碰优先于摸牌；同一张弃牌可多人同胡。过胡后直到自己下一次摸牌前只能自摸；过碰后同张牌不能再碰。碰牌后不能立即打出刚碰的牌。"},
	{"title": "鸡牌", "body": "幺鸡和八筒各自最先打出的一张为冲锋鸡4分，其余鸡牌2分。翻牌取本牌及上下相邻牌，九和一首尾相连；命中幺鸡或八筒时，该鸡分翻倍。鸡分倍率最高为2倍。"},
	{"title": "胡牌牌型", "body": "小七对24，龙七对44，大队子14，大队子单吊24，清一色24，清大对34，清大队单吊44，清七对44，清单吊54，清龙对64。牌型按最高一项计；清单吊与清大队单吊同时成立时按54分。"},
	{"title": "胡牌与额外分", "body": "普通自摸4；干扣14，四家结算鸡分都为0时改为大干扣24，不叠加。报听胡牌24，杀报24；杠开+5，最后四张自摸+5。大牌和报听不加干扣。诈胡处罚暂未实现。"},
	{"title": "付款与流局", "body": "普通弃牌被胡按非自摸胡结算，由弃牌者单独付17（已叫牌）或21（未叫牌），牌型分另计，胡牌者不加自摸4分。只有暗杠或加杠补牌后的第一张弃牌被胡，才算杠后放炮并触发烧鸡；明杠后弃牌不触发。多家同胡时弃牌者逐个付款，鸡分与杠分另算。抢杠胡由被抢杠者付12分基础费及牌型分，同样不加自摸4分。荒牌未叫者向每位叫牌者补双方出牌鸡和应付杠分；四家叫牌不计分，下局鸡分×2且当前庄家连庄。"},
	{"title": "联机与暂未实现", "body": "联机状态由房主权威结算，断线重连会同步当前牌局。诈胡处罚规则已列入规则设计，当前版本尚未实现。"},
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
	panel.theme = Theme.new()
	panel.theme.default_font = TileView._font()
	add_child(panel)
	title_label = _label("", Vector2(64, 54), Vector2(992, 64), 42, Color("#f2deb0"))
	body_label = _label("", Vector2(64, 150), Vector2(992, 210), 30, Color("#e0ece1"))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_label = _label("", Vector2(64, 500), Vector2(260, 42), 24, Color("#adc6b5"))
	previous_button = _button("上一步", _previous, Vector2(530, 548), Vector2(180, 68))
	next_button = _button("下一步", _next, Vector2(730, 548), Vector2(180, 68))
	_button("关闭", close, Vector2(930, 548), Vector2(130, 68))
	var example := HBoxContainer.new()
	example.name = "Examples"
	example.position = Vector2(64, 370)
	example.size = Vector2(992, 118)
	example.alignment = BoxContainer.ALIGNMENT_CENTER
	example.add_theme_constant_override("separation", 18)
	panel.add_child(example)
	resized.connect(_layout)
	_layout()

func open() -> void:
	page = 0
	_layout()
	MOTION.appear(self)
	MOTION.slide_in(panel)
	_refresh()

func close() -> void:
	MOTION.stop(self)
	MOTION.stop(panel)
	visible = false

func _next() -> void:
	page = mini(PAGES.size() - 1, page + 1)
	_refresh()

func _previous() -> void:
	page = maxi(0, page - 1)
	_refresh()

func _refresh() -> void:
	var example := panel.get_node("Examples")
	for child in example.get_children():
		example.remove_child(child)
		child.queue_free()
	var samples: Array = [["wan1", "wan2", "wan3", "tong8", "tiao1"], ["tong4", "tong4", "tong4", "wan9", "wan9", "wan9", "wan9"], ["tiao1", "tong7", "tong8", "tong9"], ["wan1", "wan1", "wan2", "wan2", "wan3", "wan3"], ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2"], ["tong1", "tong2", "tong3", "tong8", "tiao1"], []][page]
	for card in samples:
		var tile := TileView.new()
		tile.set_card(card, true)
		tile.set_unit(1.5)
		example.add_child(tile)
	var item: Dictionary = PAGES[page]
	title_label.text = item.title
	body_label.text = item.body
	page_label.text = "%d / %d" % [page + 1, PAGES.size()]
	previous_button.disabled = page == 0
	next_button.disabled = page == PAGES.size() - 1

func _layout() -> void:
	if panel == null: return
	MOTION.stop(panel)
	var available := STYLE.usable_rect(self)
	var factor := minf(1.0, minf((available.size.x - 48) / 1120.0, (available.size.y - 48) / 650.0))
	panel.scale = Vector2.ONE * maxf(0.1, factor)
	panel.position = available.position + (available.size - panel.size * panel.scale) / 2.0

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
	STYLE.button(button, value == "下一步")
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
