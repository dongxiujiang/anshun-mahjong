extends SceneTree
## 仅用于材质验收，不注册为游戏界面或更改真实牌局。

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var canvas := Control.new()
	root.add_child(canvas)
	var felt := ColorRect.new()
	felt.color = Color("#164533")
	felt.size = Vector2(1280, 720)
	canvas.add_child(felt)
	for row in 3:
		for rank in range(1, 10):
			var tile := TileView.new()
			tile.set_unit(1.9)
			tile.set_card(Tiles.val(Tiles.SUITS[row], rank), true)
			tile.position = Vector2(44 + (rank - 1) * 104, 28 + row * 136)
			canvas.add_child(tile)
	for index in 3:
		var back := TileView.new()
		back.set_unit(1.9)
		back.set_card("", false)
		back.back_depth_top = index == 1
		back.position = Vector2(1044, 28 + index * 136)
		canvas.add_child(back)
	for row in 2:
		for value in range(1, 7):
			var die = load("res://scripts/ui/DiceView.gd").new()
			die.size = Vector2(88, 88)
			die.position = Vector2(80 + (value - 1) * 190, 460 + row * 116)
			die.value = value
			die.pip_color = Color("#a62b21") if row == 0 else Color("#243a30")
			canvas.add_child(die)
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://build/ui-copy-review/screens"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join("17_tile_materials.png"))
	print("[preview_tile_materials] passed: 27 faces, 3 backs, 12 dice")
	quit()
