extends SceneTree
## 真实 OpenGL 窗口检查 V2 牌桌在三种目标分辨率下的缩放和可见区域。

const H := preload("res://tests/test_harness.gd")
const SIZES := [Vector2i(2400, 1080), Vector2i(1280, 720), Vector2i(960, 540)]
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.get_node("UpdateManager").auto_check = false
	var output := "res://build/device_validation/desktop"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	for dimensions in SIZES:
		root.size = dimensions
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var screen := Rect2(Vector2.ZERO, Vector2(dimensions))
		var surface_rect: Rect2 = table.surface.get_global_rect()
		t.expect(screen.grow(1).encloses(surface_rect),
			"%dx%d: V2 牌桌完整位于窗口内" % [dimensions.x, dimensions.y])
		t.expect(table._new_areas != null and table._new_areas.is_visible_in_tree(),
			"%dx%d: V2 是可见正式牌桌" % [dimensions.x, dimensions.y])
		t.expect(screen.grow(1).encloses(table._sound_button.get_global_rect()),
			"%dx%d: 设置按钮位于安全可见区域" % [dimensions.x, dimensions.y])
		var title := _find_label(table.surface, "安顺麻将")
		var fps_label: Control = root.get_node("FpsOverlay")._label
		t.expect(title != null and not fps_label.get_global_rect().intersects(title.get_global_rect()),
			"%dx%d: FPS 指示不遮挡标题" % [dimensions.x, dimensions.y])
		t.expect(not fps_label.get_global_rect().intersects(table._sound_button.get_global_rect()),
			"%dx%d: FPS 指示不遮挡设置按钮" % [dimensions.x, dimensions.y])
		for seat in 4:
			t.expect(not table.seat_roots[seat].visible,
				"%dx%d: 旧牌桌座位节点保持隐藏" % [dimensions.x, dimensions.y])
		var image := root.get_texture().get_image()
		t.expect(image.get_size() == dimensions,
			"%dx%d: 截图像素尺寸正确" % [dimensions.x, dimensions.y])
		image.save_png(output.path_join("table_%dx%d.png" % [dimensions.x, dimensions.y]))
	table.round.controllers = [null, null, null, null]
	table.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("capture_v2_resolutions"))

func _find_label(parent: Node, text: String) -> Label:
	for child in parent.get_children():
		if child is Label and child.text == text:
			return child
		var nested := _find_label(child, text)
		if nested != null:
			return nested
	return null
