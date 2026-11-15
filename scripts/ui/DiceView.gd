extends Control
## 实体圆角骰子的离线三维渲染；运行时只读取贴图，顶面为权威点数。
const ATLAS := preload("res://res/tiles/materials3d/dice-atlas.png")
var value := 1:
	set(next):
		value = clampi(next, 1, 6)
		queue_redraw()
var face_color := Color.WHITE
var pip_color := Color("#284438")
var presentation_3d := false:
	set(next):
		if presentation_3d == next: return
		presentation_3d = next
		queue_redraw()

func _draw() -> void:
	if presentation_3d: return
	var row := 0 if pip_color.r > pip_color.g else 1
	draw_texture_rect_region(ATLAS, Rect2(Vector2.ZERO, size), Rect2((value - 1) * 256, row * 256, 256, 256), face_color)
