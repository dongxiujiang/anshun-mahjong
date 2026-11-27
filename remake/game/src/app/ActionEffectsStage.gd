extends Control
## 克制实用的新中式水墨鎏金牌桌动作提示：碰 / 杠 / 暗杠 / 加杠 / 报听 / 冲锋鸡 / 烧鸡。
## 纯视觉表现层，mouse_filter = IGNORE，紧贴对应方位、清晰显示动作与对应牌面，绝不遮挡弃牌与手牌。

const UI := preload("res://src/app/AppTheme.gd")

const STYLES := {
	"pong": {
		"title": "碰",
		"accent": Color("#e8c167"),
		"fill": Color("#102922eb"),
		"ink": Color("#fff5d8"),
		"sub": Color("#d8c89c"),
		"duration": 0.85,
	},
	"kong": {
		"title": "明杠",
		"accent": Color("#e89a4a"),
		"fill": Color("#1a241eeb"),
		"ink": Color("#ffe8c2"),
		"sub": Color("#dfbe92"),
		"duration": 0.92,
	},
	"concealed_kong": {
		"title": "暗杠",
		"accent": Color("#5dd09e"),
		"fill": Color("#0e2b24eb"),
		"ink": Color("#e6fff3"),
		"sub": Color("#9fd8be"),
		"duration": 0.92,
	},
	"add_kong": {
		"title": "加杠",
		"accent": Color("#eaa852"),
		"fill": Color("#19251feb"),
		"ink": Color("#ffedd0"),
		"sub": Color("#dfc298"),
		"duration": 0.90,
	},
	"ready": {
		"title": "报听",
		"accent": Color("#62d4cf"),
		"fill": Color("#0d2c2ceb"),
		"ink": Color("#e8fffe"),
		"sub": Color("#a2ddd9"),
		"duration": 0.95,
	},
	"charge_chicken": {
		"title": "冲锋鸡",
		"accent": Color("#eb734c"),
		"fill": Color("#2a1715eb"),
		"ink": Color("#ffebd2"),
		"sub": Color("#f3b896"),
		"duration": 1.10,
	},
	"burn_chicken": {
		"title": "烧鸡",
		"accent": Color("#d47c64"),
		"fill": Color("#231716eb"),
		"ink": Color("#f7ddd4"),
		"sub": Color("#cfa69a"),
		"duration": 1.0,
	},
}

var _bursts: Array = []
var _banner := {}

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 18
	set_process(false)

func clear_all() -> void:
	_bursts.clear()
	_banner.clear()
	set_process(false)
	queue_redraw()

func play_action(kind: String, rel_seat: int = 0, subtitle: String = "") -> void:
	var style: Dictionary = STYLES.get(kind, STYLES.pong)
	var seat := clampi(rel_seat, 0, 3)
	# 同座位连续动作直接替换，保持牌桌干净不重叠
	_bursts = _bursts.filter(func(b): return int(b.rel_seat) != seat)
	var item := {
		"kind": kind,
		"rel_seat": seat,
		"title": str(style.title),
		"sub": subtitle.strip_edges(),
		"style": style,
		"elapsed": 0.0,
		"duration": float(style.duration),
	}
	_bursts.append(item)
	if _bursts.size() > 4:
		_bursts.pop_front()
	set_process(true)
	queue_redraw()

func play_chicken_banner(summary_text: String, hit_count: int) -> void:
	if summary_text.is_empty():
		return
	_banner = {
		"text": summary_text,
		"hits": hit_count,
		"elapsed": 0.0,
		"duration": 1.85,
	}
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	var alive := []
	for item in _bursts:
		item.elapsed += delta
		if item.elapsed < item.duration:
			alive.append(item)
	_bursts = alive
	if not _banner.is_empty():
		_banner.elapsed += delta
		if _banner.elapsed >= _banner.duration:
			_banner.clear()
	if _bursts.is_empty() and _banner.is_empty():
		set_process(false)
	queue_redraw()

func _anchor_for_seat(rel_seat: int) -> Vector2:
	# 收进对应弃牌河附近的绿呢空带，避开外围牌墙与手牌。
	match rel_seat:
		0: return Vector2(size.x * 0.50, size.y * 0.60)
		1: return Vector2(size.x * 0.60, size.y * 0.46)
		2: return Vector2(size.x * 0.50, size.y * 0.27)
		_: return Vector2(size.x * 0.40, size.y * 0.46)

func _slide_dir_for_seat(rel_seat: int) -> Vector2:
	match rel_seat:
		0: return Vector2(0.0, 12.0)
		1: return Vector2(14.0, 0.0)
		2: return Vector2(0.0, -12.0)
		_: return Vector2(-14.0, 0.0)

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	for item in _bursts:
		_draw_callout(font, item)
	if not _banner.is_empty():
		_draw_banner(font, _banner)

func _draw_callout(font: Font, item: Dictionary) -> void:
	var t := clampf(float(item.elapsed) / maxf(0.01, float(item.duration)), 0.0, 1.0)
	var style: Dictionary = item.style
	var ease_in := 1.0 - pow(1.0 - clampf(t * 7.5, 0.0, 1.0), 3.0)
	var alpha := clampf(t * 10.0, 0.0, 1.0) * clampf((1.0 - t) * 4.5, 0.0, 1.0)
	var rel_seat := int(item.rel_seat)
	var center := _anchor_for_seat(rel_seat) + _slide_dir_for_seat(rel_seat) * (1.0 - ease_in)
	var pop_t := clampf(t / 0.14, 0.0, 1.0)
	var pop_scale := lerpf(1.03, 1.0, smoothstep(0.65, 1.0, pop_t))
	if pop_t < 0.65:
		pop_scale = lerpf(0.86, 1.03, 1.0 - pow(1.0 - pop_t / 0.65, 3.0))
	draw_set_transform(center, 0.0, Vector2.ONE * pop_scale)
	var title: String = str(item.title)
	var sub: String = str(item.sub)
	var title_size := 22
	var sub_size := 15
	var title_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	var sub_w := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x if not sub.is_empty() else 0.0
	var pad_x := 14.0
	var gap := 10.0 if not sub.is_empty() else 0.0
	var bar_w := 4.0
	var total_w := maxf(86.0, pad_x * 2.0 + bar_w + 10.0 + title_w + gap + sub_w)
	var total_h := 38.0
	var rect := Rect2(-Vector2(total_w * 0.5, total_h * 0.5), Vector2(total_w, total_h))
	var fill: Color = style.fill
	var accent: Color = style.accent
	var ink: Color = style.ink
	var sub_col: Color = style.sub
	# 柔和投影 + 雅致墨玉牌匾（无刺眼放射线与粗糙圆章）
	draw_style_box(UI.card(Color(0, 0, 0, 0.28 * alpha), 12, 0, Color(0, 0, 0, 0), 0), Rect2(rect.position + Vector2(0, 3), rect.size))
	draw_style_box(UI.card(Color(fill.r, fill.g, fill.b, fill.a * alpha), 12, 0, Color(accent.r, accent.g, accent.b, 0.78 * alpha), 1), rect)
	draw_line(rect.position + Vector2(13.0, 1.5), Vector2(rect.end.x - 13.0, rect.position.y + 1.5), Color(1.0, 0.88, 0.57, 0.30 * alpha), 1.0, true)
	# 左侧竖向色标条（一眼区分碰/杠/暗杠/报听/冲锋鸡）
	var stripe := Rect2(rect.position + Vector2(9.0, 8.0), Vector2(bar_w, total_h - 16.0))
	draw_style_box(UI.card(Color(accent.r, accent.g, accent.b, 0.96 * alpha), 2, 0, Color(0, 0, 0, 0), 0), stripe)
	var text_x := stripe.end.x + 10.0
	var title_y := rect.position.y + (total_h - font.get_height(title_size)) * 0.5 + font.get_ascent(title_size)
	draw_string_outline(font, Vector2(text_x, title_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, 3, Color(0.04, 0.08, 0.07, 0.85 * alpha))
	draw_string(font, Vector2(text_x, title_y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color(ink.r, ink.g, ink.b, alpha))
	if not sub.is_empty():
		var sep_x := text_x + title_w + 5.0
		draw_line(Vector2(sep_x, rect.position.y + 11.0), Vector2(sep_x, rect.end.y - 11.0), Color(accent.r, accent.g, accent.b, 0.35 * alpha), 1.0, true)
		var sub_y := rect.position.y + (total_h - font.get_height(sub_size)) * 0.5 + font.get_ascent(sub_size)
		draw_string(font, Vector2(sep_x + 6.0, sub_y), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, Color(sub_col.r, sub_col.g, sub_col.b, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_banner(font: Font, banner: Dictionary) -> void:
	var t := clampf(float(banner.elapsed) / maxf(0.01, float(banner.duration)), 0.0, 1.0)
	var alpha := clampf(t * 7.0, 0.0, 1.0) * clampf((1.0 - t) * 4.5, 0.0, 1.0)
	var text: String = str(banner.text)
	var fsize := 15
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var box_w := clampf(tw + 36.0, 180.0, size.x * 0.72)
	var rect := Rect2((size.x - box_w) * 0.5, clampf(size.y * 0.145, 76.0, 118.0), box_w, 30.0)
	draw_style_box(UI.card(Color(0.07, 0.17, 0.14, 0.90 * alpha), 10, 0, Color(0.84, 0.70, 0.38, 0.72 * alpha), 1), rect)
	var tx := rect.position.x + (rect.size.x - tw) * 0.5
	var ty := rect.position.y + 20.0
	draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.97, 0.91, 0.74, alpha))
