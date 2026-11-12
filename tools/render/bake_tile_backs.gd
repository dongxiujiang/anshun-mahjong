extends SceneTree
## Reproduce the current tile-back artwork; no gameplay or layout changes.
class Back extends TileView:
	var river := false
	func _draw(): _draw_procedural_back(river)
func _initialize(): call_deferred("run")
func run():
	if DisplayServer.get_name()=="headless":
		push_error("Texture baking requires a rendering display")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1168,677)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(viewport)
	for base_unit in [1.0,1.35]:
		var cell:=Vector2i(ceili(54*base_unit*4),ceili(72*base_unit*4))
		for variant in 4:
			var tile := Back.new()
			tile.set_unit(base_unit)
			tile.scale=Vector2.ONE*4
			tile.back_depth_top = bool(variant%2)
			tile.river = variant>=2
			viewport.add_child(tile)
			tile.position = Vector2(variant*cell.x+8*base_unit,(288 if base_unit>1 else 0)+8*base_unit)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://res/tiles")
	var error := viewport.get_texture().get_image().save_png("res://res/tiles/backs-atlas.png")
	print("tile-back atlas: ",error_string(error))
	quit(error)
