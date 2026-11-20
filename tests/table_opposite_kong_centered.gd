extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size=G.DESIGN_SIZE
	for pixels in [Vector2i(1600,1000),Vector2i(1920,1080),Vector2i(2400,1080)]:
		root.size=pixels
		view.scale=Vector2(pixels)/G.DESIGN_SIZE
		for owner in 4:
			var r := RoundState.new()
			r.build_players(owner)
			r.phase=RoundState.Phase.PLAYING
			r._presentation.session="opposite-%d-%d" % [pixels.x,owner]
			var p=r.players[owner]
			p.concealed=["wan1","wan2","wan3","wan4","wan5","wan6","tong1","tong2","tong3","tong9"]
			for source in [1,2,3]:
				p.melds=[{"kind":"kong","tile":"tiao8","from_seat":(owner+source)%4,"formed_at":1,"after_discard":1}]
				for viewer in 4:
					view.set_round(r,viewer)
					await process_frame
					_check(view,owner,0,"isolated %dx%d owner%d view%d source%d" % [pixels.x,pixels.y,owner,viewer,source])
	var record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/meld_layout_replay.json"))
	var replay := RoundState.new()
	replay.controllers=[null,null,null,null]
	replay.set_rng_seed(int(record.seed))
	replay.pause_after_opening=true
	replay.start_round(1,int(record.red),int(record.white),false)
	replay.resume_after_opening()
	for step in mini(64,record.actions.size()):
		var action: Dictionary=record.actions[step]
		var accepted: bool=replay.submit_turn(int(action.seat),action.decision) if action.kind=="turn" else replay.submit_response(int(action.seat),str(action.tile),action.decision)
		t.expect(accepted,"recorded action %d remains legal" % step)
	var pictured: Dictionary=replay.players[0].melds.back()
	t.expect(pictured.kind=="kong" and pictured.tile=="tiao6" and int(pictured.from_seat)==3,"step63 pictured kong is six bamboo claimed from seat3, not an opposite-source kong")
	print("REAL step63 owner0 pictured_meld=",pictured)

	for pixels in [Vector2i(1600,1000),Vector2i(1920,1080),Vector2i(2400,1080)]:
		root.size=pixels
		view.scale=Vector2(pixels)/G.DESIGN_SIZE
		for viewer in 4:
			view.set_round(replay,viewer)
			await process_frame
			for owner in 4:
				for index in replay.players[owner].melds.size():
					var meld: Dictionary=replay.players[owner].melds[index]
					if meld.kind!="kong" or meld.get("concealed",false) or int(meld.get("from_seat",-1)) not in range(4) or meld.from_seat==owner: continue
					_check(view,owner,index,"step63 %dx%d owner%d view%d tile%s" % [pixels.x,pixels.y,owner,viewer,meld.tile])
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self,t.finish("table_opposite_kong_centered"))

func _check(view,owner:int,index:int,label:String) -> void:
	var renderer=view._table_3d
	renderer.sync_tiles()
	var sources: Array=(view._meld_layer.get_children()+view._red_layer.get_children()).filter(func(tile): return int(tile.get_meta("v2_seat",-1))==owner and int(tile.get_meta("meld_index",-1))==index)
	sources.sort_custom(func(a,b): return int(a.get_meta("meld_slot"))<int(b.get_meta("meld_slot")))
	if not t.expect(sources.size()==4,label+" contains all four meshes"): return
	var source := posmod(int(view.round.players[owner].melds[index].from_seat)-owner,4)
	var slot := 0 if source==1 else 3
	t.expect(int(sources[slot].get_meta("meld_sideways",-1))==slot,label+" preserves recorded source sideways slot")
	var crosswise: MeshInstance3D=renderer.tile_nodes[sources[slot].get_instance_id()]
	sources.remove_at(slot)
	var first: MeshInstance3D=renderer.tile_nodes[sources[0].get_instance_id()]
	var middle: MeshInstance3D=renderer.tile_nodes[sources[1].get_instance_id()]
	var last: MeshInstance3D=renderer.tile_nodes[sources[2].get_instance_id()]
	var axis:=middle.basis.x.normalized()
	var width:=middle.basis.x.length()
	var inward := -middle.basis.z.normalized()
	var along: float = [0.0,-1.17,1.0,3.17][source]
	t.expect((middle.position-first.position).is_equal_approx(axis*width) and (last.position-middle.position).is_equal_approx(axis*width),label+" three upright tiles form one row")
	t.expect(crosswise.basis.z.normalized().dot(axis) < -0.999,label+" sideways tile faces across the owner's main row")
	var expected := first.position + (axis*along + inward*(1.17 if source==2 else -0.17))*width
	var error := crosswise.position.distance_to(expected)
	t.expect(error<0.001,label+" sideways tile sits at the end of the same row for side sources, or inward and centered for the opposite source; error_widths=%.4f" % (error/width))
	var projected: Vector2=renderer.camera.unproject_position(crosswise.position)
	var projected_expected: Vector2=renderer.camera.unproject_position(expected)
	t.expect(projected.distance_to(projected_expected)<0.1,label+" projected tile agrees with its source position")
