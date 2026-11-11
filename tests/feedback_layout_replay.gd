extends SceneTree
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const E = preload("res://scripts/ui/table/v2/ExposedLayout.gd")
var t = H.new()
func _initialize(): call_deferred("run")
func run():
	var frames: Array = JSON.parse_string(FileAccess.get_file_as_string("res://build/layout-proposals/hand-follow-hud/frames.json"))
	DirAccess.make_dir_recursive_absolute("res://build/change-20261112/screenshots")
	for frame in frames:
		var state: Dictionary = frame.state
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://build/release-candidate-1621/scenes/layout_review/round-%d.json" % int(state.id)))
		var r := RoundState.new()
		r.controllers = [null,null,null,null]
		r.set_rng_seed(2026111200+int(state.id))
		r.next_dealer_seat = int(state.dealer)
		r.pause_after_opening = true
		r.start_round(1,int(state.red),int(state.white))
		if int(state.step)>0: r.resume_after_opening()
		for i in maxi(0,int(state.step)-1):
			var action: Dictionary = record.actions[i]
			var accepted: bool = r.submit_turn(int(action.seat),action.decision) if action.kind=="turn" else r.submit_response(int(action.seat),str(action.tile),action.decision)
			t.expect(accepted,"real replay action accepted")
		for viewer in 4:
			var view = load("res://scenes/table/TableV2.tscn").instantiate()
			root.add_child(view)
			view.auto_sort_hands = false
			view.formal_mode = false
			view.test_reveal_all_hands = true
			view.round = r
			view.human_seat = viewer
			view._sort_started = true
			for key in frame.held:
				var seat := int(key)
				var old_rel := G.relative_seat(1,seat)
				var rel := G.relative_seat(viewer,seat)
				var base := G.hand_slot_center(seat,0,1,1)
				var next := G.hand_slot_center(seat,0,viewer,1)
				var ratio := (G.hand_tile_size(seat,viewer).x+4)/(G.hand_tile_size(seat,1).x+4)
				var held := []
				for raw in frame.held[key]:
					var offset: float = (Vector2(raw[0],raw[1])-base).dot(E.AXES[old_rel])
					held.append(next+E.AXES[rel]*offset*ratio)
				view._held_hand_centers[seat] = held
			view.refresh()
			var expected := 0
			for player in r.players:
				expected += player.discards.filter(func(tile):return Tiles.is_chicken(tile)).size()
				for meld in player.melds: expected += 3 if meld.kind=="pung" else 4
			t.expect(view._exposed_layout().size()==expected,"all exposed tiles placed in replay %d/%d viewer %d" % [state.id,state.step,viewer])
			var obstacles := []
			for layer in view.hand_boxes+view.draw_boxes+[view._discard_layer,view._wall_layer]:
				for node in layer.get_children():
					obstacles.append(E.rect_for(node.position+node.size/2,node.size*node.scale,node.rotation))
			for seat in 4: obstacles.append(view._seat_hud_rect(seat))
			t.expect(E.clear(view._exposed_layout(),obstacles),"exposed tiles avoid live hands/walls/rivers/names")
			if DisplayServer.get_name()!="headless":
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://build/change-20261112/screenshots/replay-%d-%d-view%d.png" % [state.id,state.step,viewer])
			view.queue_free()
			await process_frame
	await H.quit_cleanly(self,t.finish("feedback_layout_replay"))
