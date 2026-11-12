extends SceneTree
const H=preload("res://tests/test_harness.gd")
var t=H.new()
class Reference extends TileView:
	var river:=false
	func _draw(): _draw_procedural_back(river)
func _initialize():call_deferred("run")
func run():
	if DisplayServer.get_name()=="headless":
		push_error("tile_back_render requires a display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://build/back-render")
	for unit in [1.0,1.1475,1.35,2.4,3.2]:
		var cell:=Vector2i(ceili(54*unit),ceili(72*unit))
		var viewport:=SubViewport.new()
		viewport.size=cell*Vector2i(2,4)
		viewport.transparent_bg=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		root.add_child(viewport)
		for row in 4:
			for side in 2:
				var tile=TileView.new() if side==0 else Reference.new()
				tile.set_unit(unit)
				tile.set_card("",false)
				tile.back_depth_top=row%2==1
				if side==1:tile.river=row>=2
				elif row>=2:
					tile.set_meta("discard_id",0)
					tile.set_meta("new_kind","ordinary")
				viewport.add_child(tile)
				tile.position=Vector2(cell.x*side+2*unit,cell.y*row+2*unit)
		await process_frame
		await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image()
		image.save_png("res://build/back-render/unit-%.4f.png"%unit)
		var error:=0.0
		for y in image.get_height():
			for x in cell.x:
				var a:=image.get_pixel(x,y)
				var b:=image.get_pixel(x+cell.x,y)
				error+=absf(a.r*a.a-b.r*b.a)+absf(a.g*a.a-b.g*b.a)+absf(a.b*a.a-b.b*b.a)+absf(a.a-b.a)
		error/=float(cell.x*image.get_height()*4)
		print("[tile_back_render] unit=",unit," mean_channel_error=",error)
		t.expect(error<0.015,"atlas preserves colors, outlines and shadows at unit %.4f"%unit)
		viewport.queue_free()
		await process_frame
	await H.quit_cleanly(self,t.finish("tile_back_render"))
