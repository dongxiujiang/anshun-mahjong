extends Control
## Procedural ivory die; no texture assets needed.
var value := 1:
	set(next):
		value = clampi(next, 1, 6)
		queue_redraw()
var face_color := Color("#faf3dd")
var border_color := Color("#d7c599")
var pip_color := Color("#284438")

func _draw() -> void:
	var face := preload("res://scripts/ui/UiStyle.gd").panel(face_color, border_color, 18)
	draw_style_box(face, Rect2(Vector2.ZERO, size))
	var patterns: Array = [[[1,1]], [[0,0],[2,2]], [[0,0],[1,1],[2,2]], [[0,0],[2,0],[0,2],[2,2]], [[0,0],[2,0],[1,1],[0,2],[2,2]], [[0,0],[2,0],[0,1],[2,1],[0,2],[2,2]]]
	for point in patterns[value - 1]:
		draw_circle(Vector2(size.x * (0.25 + point[0] * 0.25), size.y * (0.25 + point[1] * 0.25)), size.x * 0.065, pip_color)
