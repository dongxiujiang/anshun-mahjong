extends SceneTree
const Table=preload("res://src/presentation/TableView.gd")
const Profile=preload("res://src/presentation/TableLayoutProfile.gd")
const Round=preload("res://src/domain/Round.gd")
const Catalog=preload("res://src/domain/TileCatalog.gd")
const ButtonArt=preload("res://src/app/TableActionButton.gd")
const Feedback=preload("res://src/app/WinFeedback.gd")
const UI=preload("res://src/app/AppTheme.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL player reference: "+message)
func _initialize()->void:_run.call_deferred()
func _capture(name:String)->void:
	var folder:=OS.get_environment("DONGXIU_REFERENCE_SCREENS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(folder)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func _run()->void:
	root.size=Vector2i(1280,720)
	var table=Table.new();root.add_child(table);await process_frame
	check(table.custom_profile!=null,"actual game loads the user's applied layout")
	if table.custom_profile==null:table.free();quit(1);return
	var source:=OS.get_environment("DONGXIU_LAYOUT_INPUT")
	if source.is_empty():source="res://assets/layouts/table-layout.json"
	var expected:=Profile.new();check(expected.load_file(source),"read user source layout")
	check(JSON.stringify(table.custom_profile.data)==JSON.stringify(expected.data),"game uses the exact same layout as the user's file")
	var game:=Round.new();check(game.start(1,5,2,Catalog.values(812)) and game.begin_dealer_turn(),"real legal opening reaches a turn")
	for seat in 4: game.snapshot_for(seat)
	var unchanged:=JSON.stringify(game.export_authority())
	var wall:int=game.wall.peek_head()
	var wall_pose:Transform3D
	for viewer in 4:
		table.set_viewer(viewer);table.apply_view(game.snapshot_for(viewer));table._render(false)
		check(table.tiles.size()==108,"viewer change conserves all physical tiles")
		if viewer==0:wall_pose=table.tiles[wall].transform
		else:check(table.tiles[wall].transform==wall_pose,"viewpoint keeps the shared wall in the same world position")
		var faces:=0
		for id in table.tiles:
			var tile:MeshInstance3D=table.tiles[id]
			if tile.get_meta("zone")=="hand" and tile.get_meta("value")!="":faces+=1
		check(faces==game.players[viewer].hand.size(),"each real viewpoint exposes only its own private hand")
		await _capture("view-"+str(viewer)+"-1280x720")
	check(JSON.stringify(game.export_authority())==unchanged,"view style never changes round facts")
	table.set_viewer(1);table.apply_view(game.snapshot_for(1));table._render(false)
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2670,1200)]:
		root.size=resolution;await process_frame;await process_frame
		table.set_safe_insets(Vector4(36,64,28,24))
		var screen:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
		for id in table.tiles:
			if table.tiles[id].get_meta("zone")=="hand" and table.tiles[id].get_meta("seat")==1:
				var node:MeshInstance3D=table.tiles[id]
				for corner in 8:check(screen.has_point(table.camera.unproject_position(node.transform*Table.TILE_BOUNDS.get_endpoint(corner))),"magnified own hand stays fully within the landscape viewport")
		await _capture("landscape-%dx%d"%[resolution.x,resolution.y])
	var chosen: int=-1
	for id in game.choices(1).discard_ids:
		if game.wall.value(id) not in ["tiao1","tong8"]:chosen=id;break
	check(chosen>=0 and game.submit(1,game.prompt_id,"discard",chosen),"real ordinary discard is accepted")
	table.apply_view(game.snapshot_for(1));table._render(false)
	check(table._discard_marker.visible,"orange indicator identifies the current physical discard")
	var destination:Transform3D=table.tiles[chosen].transform
	var old:Vector3=table._discard_marker.position
	table._process(0.2)
	check(table._discard_marker.position!=old and table.tiles[chosen].transform==destination,"only the pointer bobs; the real discard stays fixed")
	var material:StandardMaterial3D=table._discard_marker.mesh.material
	check(material.albedo_color.g>0.5 and material.albedo_color.b<0.2,"discard pointer follows the orange reference")
	await _capture("current-discard")
	# The same production action widget is also used by Main's legal action list.
	root.size=Vector2i(1280,720);await process_frame
	var surface:=Control.new();surface.theme=UI.build();root.add_child(surface);surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row:=HBoxContainer.new();surface.add_child(row);row.position=Vector2(850,430)
	var clicks:=[]
	for pair in [["win","胡"],["pong","碰"],["pass","过"]]:
		var button:=ButtonArt.new();button.configure(pair[0],pair[1],func():clicks.append(true));row.add_child(button)
	await process_frame;await process_frame
	for button in row.get_children():
		check(button._has_point(button.size*0.5) and not button._has_point(Vector2.ZERO),"round controls have circular touch targets")
		check(button.custom_minimum_size.x>=64 and button.accessibility_name==button.text,"touch size and accessible action labels remain available")
		button.pressed.emit()
	check(clicks.size()==3,"vector-drawn controls preserve button callbacks")
	await _capture("action-style-components")
	row.hide()
	var feedback:=Feedback.new();surface.add_child(feedback);feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await process_frame
	var members:=[{"nickname":"牌友甲","avatar":1},{"nickname":"牌友乙","avatar":2},{"nickname":"牌友丙","avatar":3},{"nickname":"牌友丁","avatar":4}]
	var result:={"winners":[1,3],"self_draw":false}
	var copy:=result.duplicate(true)
	check(feedback.present("one",result,members,Vector2(450,300)),"win effect starts for a new real-result identity")
	feedback._motion.pause();feedback._advance(0.35)
	check(feedback._names.text.contains("牌友乙") and feedback._names.text.contains("牌友丁"),"multiple winners remain visible in the presentation")
	check(not feedback.present("one",result,members,Vector2.ZERO),"duplicate snapshots never replay the win effect")
	check(feedback.mouse_filter==Control.MOUSE_FILTER_IGNORE and result==copy,"win feedback never blocks controls or changes the result")
	await _capture("win-feedback")
	check(feedback.present("two",{"winners":[1],"self_draw":true},members,Vector2(450,300)),"self-draw has a distinct presentation")
	feedback._motion.pause();feedback._advance(0.35)
	check(feedback._title.text=="自摸","self-draw uses the correct title")
	await _capture("self-draw-feedback")
	feedback._motion.custom_step(2)
	check(not feedback.visible,"feedback always retires without delaying settlement")
	check(not feedback.present("draw",{"winners":[]},members,Vector2.ZERO),"drawn round never plays a win effect")
	surface.free();table.free();await process_frame
	print("%d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
