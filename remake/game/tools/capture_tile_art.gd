extends SceneTree
## Evidence uses the production tile meshes, materials and table lighting.
const Table = preload("res://src/presentation/TableView.gd")
const Art = preload("res://src/presentation/TileArt.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty():
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var table := Table.new()
	viewport.add_child(table)
	table.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	table.camera.size = 13.4
	table.camera.position = Vector3(0, 13, 11)
	table.camera.look_at(Vector3.ZERO)
	for row in 3:
		for rank in range(1, 10):
			var value: String = ["wan", "tiao", "tong"][row] + str(rank)
			var tile := MeshInstance3D.new()
			tile.mesh = Art.mesh(value)
			tile.material_override = Art.material(true)
			tile.position = Vector3((rank - 5) * 1.26, 0.31, (row - 1) * 2.65)
			table.add_child(tile)
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := viewport.get_texture().get_image()
	var error := capture.save_png(output)
	print("Production tile artwork preview: ", capture.get_size(), " saved=", error == OK)
	quit(0 if error == OK else 1)
