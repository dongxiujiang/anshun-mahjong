extends Control
## 新中式茶馆氛围背景：深翠玉石径向漫光 + 极简暗金回纹边角装饰。零外部贴图、零卡顿。

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	# 1. 深墨翠基底
	draw_rect(Rect2(Vector2.ZERO, size), Color("#081512"), true)
	# 2. 柔和顶灯径向翡翠漫射晕
	var center := Vector2(size.x * 0.50, size.y * 0.36)
	var max_r := maxf(size.x, size.y) * 0.78
	var layers := [
		[1.00, Color(0.06, 0.18, 0.14, 0.34)],
		[0.76, Color(0.08, 0.24, 0.19, 0.30)],
		[0.54, Color(0.10, 0.30, 0.24, 0.24)],
		[0.34, Color(0.14, 0.34, 0.26, 0.16)],
		[0.20, Color(0.84, 0.68, 0.32, 0.045)],
	]
	for layer in layers:
		draw_circle(center, max_r * float(layer[0]), layer[1])
	# 3. 底部轻微收暗压重，突出前景卡片层次
	draw_rect(Rect2(0, size.y * 0.78, size.x, size.y * 0.22), Color(0.02, 0.06, 0.05, 0.28), true)
	# 4. 极淡中式丝绸竖格暗纹（仅左右留白边缘）
	var silk := Color(0.75, 0.88, 0.80, 0.028)
	for side_x in [36.0, 56.0, size.x - 56.0, size.x - 36.0]:
		draw_line(Vector2(side_x, 22.0), Vector2(side_x, size.y - 22.0), silk, 1.0, true)
	# 5. 极细鎏金双边框
	var outer := Rect2(Vector2(10.0, 10.0), size - Vector2(20.0, 20.0))
	var inner := Rect2(Vector2(15.0, 15.0), size - Vector2(30.0, 30.0))
	draw_rect(outer, Color(0.78, 0.64, 0.35, 0.18), false, 1.2)
	draw_rect(inner, Color(0.78, 0.64, 0.35, 0.08), false, 1.0)
	# 6. 四角精致中式回纹折角
	var gold := Color(0.88, 0.73, 0.42, 0.32)
	var arm := 26.0
	var inset := 10.0
	var corners := [
		[Vector2(inset, inset), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(size.x - inset, inset), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(inset, size.y - inset), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(size.x - inset, size.y - inset), Vector2(-1, 0), Vector2(0, -1)],
	]
	for c in corners:
		var p: Vector2 = c[0]
		var dx: Vector2 = c[1]
		var dy: Vector2 = c[2]
		draw_line(p, p + dx * arm, gold, 2.0, true)
		draw_line(p, p + dy * arm, gold, 2.0, true)
		var q := p + dx * 6.0 + dy * 6.0
		draw_line(q, q + dx * 12.0, Color(gold.r, gold.g, gold.b, 0.55), 1.2, true)
		draw_line(q, q + dy * 12.0, Color(gold.r, gold.g, gold.b, 0.55), 1.2, true)
