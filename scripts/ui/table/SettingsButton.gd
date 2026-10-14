extends Button
## 视觉保留紧凑页头尺寸，触控向左/下扩展；不伸出画布顶部/右侧。
func touch_rect() -> Rect2:
	return Rect2(Vector2(-24, 0), size + Vector2(24, 40))

func _has_point(point: Vector2) -> bool:
	return touch_rect().has_point(point)
