extends SceneTree
const H = preload("res://tests/test_harness.gd")
var t = H.new()
var events: Array = []
func _initialize(): call_deferred("run")
func run():
	root.get_node("GameConfig").set_tile_animation_seconds(0.0,false)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.auto_sort_hands = false
	view.formal_mode = false
	view.test_reveal_all_hands = true
	var count := 1008
	var first := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="): count = int(arg.substr(9))
		if arg.begins_with("--start="): first = int(arg.substr(8))
	var states := 0
	var max_river := 0
	var max_meld := 0
	for id in range(first, first + count):
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://build/layout-proposals/github-b2d0dde/live-layout-validation/replays/round-%d.json" % id))
		var meta: Dictionary = record.initial.round_meta
		var r := RoundState.new()
		r.controllers = [null,null,null,null]
		r.set_rng_seed(2026111200+id)
		r.next_dealer_seat = int(record.initial.dealer_seat)
		r.pause_after_opening = true
		r.start_round(1,int(meta.die),int(meta.die_white))
		r.resume_after_opening()
		r.visual_event.connect(func(event): events.append(event))
		view.set_round(r,id%4)
		view._sort_started = true
		view.refresh()
		for action in record.actions:
			events.clear()
			var accepted: bool = r.submit_turn(int(action.seat),action.decision) if action.kind=="turn" else r.submit_response(int(action.seat),str(action.tile),action.decision)
			if not t.expect(accepted,"round %d action accepted" % id): break
			for event in events:
				if event.type=="discard": view._held_hand_centers.erase(int(event.seat))
				if event.type=="meld": view.animate_meld(event,func():pass)
			view.refresh()
			var expected := 0
			for player in r.players:
				max_river = maxi(max_river,player.discards.filter(func(tile):return not Tiles.is_chicken(tile)).size())
				max_meld = maxi(max_meld,player.melds.size())
				expected += player.discards.filter(func(tile):return Tiles.is_chicken(tile)).size()
				for meld in player.melds: expected += 3 if meld.kind=="pung" else 4
			if not t.expect(view._exposed_layout().size()==expected,"round %d all exposed tiles placed" % id): break
			states += 1
		if t.failures>0: break
		if (id-first)%24==23: print("LAYOUT first=",first," rounds=",id-first+1," states=",states," max_river=",max_river," max_meld=",max_meld)
		await process_frame
	view.queue_free()
	await H.quit_cleanly(self,t.finish("feedback_layout_soak"))
