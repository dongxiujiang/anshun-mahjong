extends Control
## 克制实用的新中式水墨鎏金牌桌动作提示：碰 / 杠 / 暗杠 / 加杠 / 报听 / 冲锋鸡 / 烧鸡。
## 纯视觉表现层，mouse_filter = IGNORE，紧贴对应方位、清晰显示动作与对应牌面，绝不遮挡弃牌与手牌。

const UI := preload("res://src/app/AppTheme.gd")

const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
const MotionFX = preload("res://src/presentation/MotionFX.gd")

const STYLES := {
	"pong": {
		"title": "碰",
		"accent": Color("#e8c167"),
		"fill": Color("#102922eb"),
		"ink": Color("#fff5d8"),
		"sub": Color("#d8c89c"),
	},
	"kong": {
		"title": "明杠",
		"accent": Color("#e89a4a"),
		"fill": Color("#1a241eeb"),
		"ink": Color("#ffe8c2"),
		"sub": Color("#dfbe92"),
	},
	"concealed_kong": {
		"title": "暗杠",
		"accent": Color("#5dd09e"),
		"fill": Color("#0e2b24eb"),
		"ink": Color("#e6fff3"),
		"sub": Color("#9fd8be"),
	},
	"add_kong": {
		"title": "加杠",
		"accent": Color("#eaa852"),
		"fill": Color("#19251feb"),
		"ink": Color("#ffedd0"),
		"sub": Color("#dfc298"),
	},
	"ready": {
		"title": "报听",
		"accent": Color("#62d4cf"),
		"fill": Color("#0d2c2ceb"),
		"ink": Color("#e8fffe"),
		"sub": Color("#a2ddd9"),
	},
	"charge_chicken": {
		"title": "冲锋鸡",
		"accent": Color("#eb734c"),
		"fill": Color("#2a1715eb"),
		"ink": Color("#ffebd2"),
		"sub": Color("#f3b896"),
	},
	"burn_chicken": {
		"title": "烧鸡",
		"accent": Color("#d47c64"),
		"fill": Color("#231716eb"),
		"ink": Color("#f7ddd4"),
		"sub": Color("#cfa69a"),
	},
}

var _quality := MotionConfig.current_quality
var _fx := MotionConfig.section("fx", _quality)
var _particles := MotionFX.ParticlePool.new()
var _slot_boxes: Array[Dictionary] = []
var _banner_box: StyleBoxFlat
var _bursts: Array[Dictionary] = []
var _banner := {}

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 18
	for i in 4:
		_slot_boxes.append({
			"shadow": UI.card(Color.TRANSPARENT, 12, 0, Color.TRANSPARENT, 0),
			"card": UI.card(Color.TRANSPARENT, 12, 0, Color.TRANSPARENT, 1),
			"stripe": UI.card(Color.TRANSPARENT, 2, 0, Color.TRANSPARENT, 0),
		})
	_banner_box = UI.card(Color.TRANSPARENT, 10, 0, Color.TRANSPARENT, 1)
	_sync_process_state()

func apply_quality(value: String) -> void:
	_quality = MotionConfig.normalize_quality(value)
	_fx = MotionConfig.section("fx", _quality)
	if int(_fx.callout_particles) == 0:
		_particles.clear()
	_sync_process_state()
	queue_redraw()

func _sync_process_state() -> void:
	set_process(not _bursts.is_empty() or not _banner.is_empty() or _particles.active_count > 0)

func clear_all() -> void:
	_bursts.clear()
	_banner.clear()
	_particles.clear()
	set_process(false)
	queue_redraw()

func _text_line(value: String, font_size: int) -> TextLine:
	var line := TextLine.new()
	line.add_string(value, get_theme_default_font(), font_size)
	return line

func play_action(kind: String, rel_seat: int = 0, subtitle: String = "") -> void:
	var style: Dictionary = STYLES.get(kind, STYLES.pong)
	var seat := clampi(rel_seat, 0, 3)
	for i in _bursts.size():
		if _bursts[i].rel_seat == seat:
			_bursts.remove_at(i)
			break
	var sub := subtitle.strip_edges()
	_bursts.append({
		"rel_seat": seat,
		"title_line": _text_line(style.title, 22),
		"sub_line": null if sub.is_empty() else _text_line(sub, 15),
		"style": style,
		"elapsed": 0.0,
		"duration": float(_fx.callout_duration) * (1.15 if kind in ["charge_chicken", "burn_chicken"] else 1.0),
	})
	var count := int(_fx.callout_particles)
	if count > 0:
		_particles.emit_burst(_anchor_for_seat(seat), count, [style.accent, style.ink, Color("#ffe394")], 55.0, 145.0, 0.28, 0.52, 110.0)
	set_process(true)
	queue_redraw()

func play_chicken_banner(summary_text: String, hit_count: int) -> void:
	if summary_text.is_empty():
		return
	_banner = {
		"line": _text_line(summary_text, 15),
		"hits": hit_count,
		"elapsed": 0.0,
		"duration": float(_fx.callout_duration) * 2.0,
	}
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_particles.step(delta)
	for i in range(_bursts.size() - 1, -1, -1):
		var item := _bursts[i]
		item.elapsed += delta
		if item.elapsed >= item.duration:
			_bursts.remove_at(i)
	if not _banner.is_empty():
		_banner.elapsed += delta
		if _banner.elapsed >= _banner.duration:
			_banner.clear()
	_sync_process_state()
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
	for item in _bursts:
		_draw_callout(item, item.rel_seat)
	if not _banner.is_empty():
		_draw_banner(_banner)
	_particles.draw(self)

func _draw_callout(item: Dictionary, idx: int) -> void:
	var t := clampf(float(item.elapsed) / float(item.duration), 0.0, 1.0)
	var enter := clampf(float(item.elapsed) / float(_fx.callout_in_duration), 0.0, 1.0)
	var ease_in := 1.0 - (1.0 - enter) * (1.0 - enter)
	var alpha := ease_in * clampf((1.0 - t) * 4.5, 0.0, 1.0)
	var center := _anchor_for_seat(idx) + _slide_dir_for_seat(idx) * (1.0 - ease_in)
	var peak := float(_fx.callout_scale_overshoot)
	var pop_scale := lerpf(0.92, 1.0, ease_in)
	if peak > 1.0:
		pop_scale = lerpf(0.84, peak, 1.0 - pow(1.0 - minf(enter / 0.65, 1.0), 3.0))
		pop_scale = lerpf(pop_scale, 1.0, smoothstep(0.65, 1.0, enter))
	draw_set_transform(center, 0.0, Vector2.ONE * pop_scale)
	var title: TextLine = item.title_line
	var sub: TextLine = item.sub_line
	var width := maxf(86.0, 42.0 + title.get_size().x + (10.0 + sub.get_size().x if sub else 0.0))
	var rect := Rect2(-width * 0.5, -19.0, width, 38.0)
	var boxes := _slot_boxes[idx]
	var style: Dictionary = item.style
	var fill: Color = style.fill
	var accent: Color = style.accent
	var glow := bool(_fx.callout_glow)
	if glow:
		boxes.shadow.bg_color = Color(0, 0, 0, 0.28 * alpha)
		draw_style_box(boxes.shadow, Rect2(rect.position + Vector2(0, 3), rect.size))
	boxes.card.bg_color = Color(fill, fill.a * alpha)
	boxes.card.border_color = Color(accent, 0.78 * alpha)
	draw_style_box(boxes.card, rect)
	if glow:
		var length := width * 0.24
		var start := rect.position + Vector2(lerpf(13.0, width - 13.0 - length, t), 1.5)
		draw_line(start, start + Vector2.RIGHT * length, Color(1.0, 0.88, 0.57, sin(PI * t) * 0.65 * alpha), 1.0, true)
	var stripe := Rect2(rect.position + Vector2(9, 8), Vector2(4, 22))
	boxes.stripe.bg_color = Color(accent, 0.96 * alpha)
	draw_style_box(boxes.stripe, stripe)
	var title_pos := Vector2(stripe.end.x + 10.0, -title.get_size().y * 0.5)
	title.draw_outline(get_canvas_item(), title_pos, 3, Color(0.04, 0.08, 0.07, 0.85 * alpha))
	title.draw(get_canvas_item(), title_pos, Color(style.ink, alpha))
	if sub:
		var sep_x := title_pos.x + title.get_size().x + 5.0
		draw_line(Vector2(sep_x, -8), Vector2(sep_x, 8), Color(accent, 0.35 * alpha), 1.0, true)
		sub.draw(get_canvas_item(), Vector2(sep_x + 6.0, -sub.get_size().y * 0.5), Color(style.sub, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_banner(banner: Dictionary) -> void:
	var t := clampf(float(banner.elapsed) / float(banner.duration), 0.0, 1.0)
	var alpha := clampf(t * 7.0, 0.0, 1.0) * clampf((1.0 - t) * 4.5, 0.0, 1.0)
	var line: TextLine = banner.line
	var box_w := clampf(line.get_size().x + 36.0, 180.0, size.x * 0.72)
	var rect := Rect2((size.x - box_w) * 0.5, clampf(size.y * 0.145, 76.0, 118.0), box_w, 30.0)
	_banner_box.bg_color = Color(0.07, 0.17, 0.14, 0.90 * alpha)
	_banner_box.border_color = Color(0.84, 0.70, 0.38, 0.72 * alpha)
	draw_style_box(_banner_box, rect)
	line.draw(get_canvas_item(), rect.get_center() - line.get_size() * 0.5, Color(0.97, 0.91, 0.74, alpha))
