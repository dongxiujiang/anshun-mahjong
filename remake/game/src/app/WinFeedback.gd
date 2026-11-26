extends Control
## 克制雅致的胡牌/自摸提示：精准高亮胡牌张 + 紧凑中式墨玉金边横幅，绝不遮挡亮牌与手牌。
const Art = preload("res://src/app/CharacterArt.gd")
const UI = preload("res://src/app/AppTheme.gd")

var last_key := ""
var progress := 0.0
var _motion: Tween
var _portrait := TextureRect.new()
var _title := Label.new()
var _names := Label.new()
var _badge_label := Label.new()
var _source := Vector2.ZERO
var _self_draw := false
var _badges: PackedStringArray = PackedStringArray()
var _shadow_box: StyleBoxFlat
var _zimo_box: StyleBoxFlat
var _hu_box: StyleBoxFlat
var _portrait_box: StyleBoxFlat

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 20
	hide()
	var rim := Color("#e8c36b")
	_shadow_box = UI.card(Color(0, 0, 0, 0.32), 14, 0, Color(0, 0, 0, 0), 0)
	_zimo_box = UI.card(Color("#2b1514f0"), 14, 0, rim, 2)
	_hu_box = UI.card(Color("#112620f0"), 14, 0, rim, 2)
	_portrait_box = UI.card(Color(0.06, 0.14, 0.11, 0.9), 8, 0, Color(rim.r, rim.g, rim.b, 0.6), 1)
	for child in [_portrait, _title, _names, _badge_label]:
		child.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(child)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color("#ffe7a0"))
	_title.add_theme_color_override("font_outline_color", Color("#2a1008"))
	_title.add_theme_constant_override("outline_size", 4)
	_names.add_theme_font_size_override("font_size", 16)
	_names.add_theme_color_override("font_color", Color("#f2ecdc"))
	_names.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_badge_label.add_theme_font_size_override("font_size", 14)
	_badge_label.add_theme_color_override("font_color", Color("#e5c470"))
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	resized.connect(_arrange)

func present(key: String, result: Dictionary, members: Array, source: Vector2, badges: PackedStringArray = PackedStringArray()) -> bool:
	if key == last_key or result.get("winners", []).is_empty():
		return false
	last_key = key
	_source = source
	_self_draw = result.get("self_draw", false)
	_badges = badges
	var winner: int = result.winners[0]
	_portrait.texture = Art.portrait(int(members[winner].get("avatar", 1)))
	_title.text = "自摸" if _self_draw else "胡"
	var names: Array[String] = []
	for seat in result.winners:
		names.append(str(members[int(seat)].get("nickname", "牌友")))
	_names.text = ("一炮多响 · " if result.winners.size() > 1 else "") + "、".join(names)
	_badge_label.text = " · ".join(_badges) if not _badges.is_empty() else ""
	_badge_label.visible = not _badges.is_empty()
	if _motion and _motion.is_valid():
		_motion.kill()
	progress = 0.0
	modulate = Color.WHITE
	show()
	_arrange()
	_motion = create_tween().set_ignore_time_scale(true)
	_motion.tween_method(_advance, 0.0, 1.0, 1.05)
	_motion.tween_callback(hide)
	return true

func cancel() -> void:
	if _motion and _motion.is_valid():
		_motion.kill()
	hide()

func _advance(value: float) -> void:
	progress = value
	modulate.a = clampf(value * 7.5, 0.0, 1.0) * clampf((1.0 - value) * 4.2, 0.0, 1.0)
	_arrange()
	queue_redraw()

func _banner_rect() -> Rect2:
	# 置于左上角留白绿呢区（结算时顶部导航已隐藏），完全不压对家亮牌与居中结算卡
	var w := clampf(size.x * 0.25, 290.0, 360.0)
	var h := 68.0
	var ease_in := 1.0 - pow(1.0 - clampf(progress * 5.0, 0.0, 1.0), 3.0)
	var slide := lerpf(-16.0, 0.0, ease_in)
	return Rect2(14.0 + slide, 10.0, w, h)

func _arrange() -> void:
	var rect := _banner_rect()
	_portrait.position = rect.position + Vector2(10.0, 8.0)
	_portrait.size = Vector2(52.0, 52.0)
	_title.position = rect.position + Vector2(74.0, 10.0)
	_names.position = rect.position + Vector2(154.0, 13.0 if _badge_label.visible else 22.0)
	_names.size = Vector2(rect.size.x - 166.0, 22.0)
	_badge_label.position = rect.position + Vector2(154.0, 37.0)
	_badge_label.size = Vector2(rect.size.x - 166.0, 20.0)
	queue_redraw()

func _draw() -> void:
	var fade := clampf((1.0 - progress) * 2.5, 0.0, 1.0)
	# 1. 胡牌张清晰金环定位（实用聚焦，一眼锁定赢在哪张牌，无夸张光柱和放射刺）
	if _source != Vector2.ZERO:
		var ring_r := 18.0 + progress * 24.0
		draw_circle(_source, 16.0, Color(0.96, 0.78, 0.32, 0.22 * fade))
		draw_arc(_source, ring_r, 0.0, TAU, 48, Color(0.98, 0.84, 0.42, 0.85 * fade), 2.5, true)
		draw_arc(_source, ring_r * 0.68, 0.0, TAU, 36, Color(1.0, 0.94, 0.72, 0.55 * fade), 1.4, true)
	# 2. 紧凑墨玉鎏金横幅（复用预缓存 StyleBox，零逐帧堆分配）
	var rect := _banner_rect()
	draw_style_box(_shadow_box, Rect2(rect.position + Vector2(0, 4), rect.size))
	draw_style_box(_zimo_box if _self_draw else _hu_box, rect)
	draw_style_box(_portrait_box, Rect2(rect.position + Vector2(8.0, 6.0), Vector2(56.0, 56.0)))
	draw_line(Vector2(rect.position.x + 144.0, rect.position.y + 14.0), Vector2(rect.position.x + 144.0, rect.end.y - 14.0), Color(0.91, 0.76, 0.42, 0.35), 1.0, true)
