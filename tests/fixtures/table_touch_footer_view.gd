extends "res://scripts/ui/table/v2/TableV2.gd"

var test_touch_height := 0.0
var test_screen_safe_area := Rect2()

func minimum_touch_height() -> float:
	return test_touch_height

func _screen_safe_area() -> Rect2:
	return test_screen_safe_area
