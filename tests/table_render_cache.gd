extends SceneTree
const H = preload("res://tests/test_harness.gd")
var t = H.new()
func _initialize(): call_deferred("run")
func run():
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.auto_sort_hands = false
	var r := RoundState.new()
	r.controllers = [null,null,null,null]
	r.set_rng_seed(42)
	r.pause_after_opening = true
	r.start_round(1,3,2)
	r.resume_after_opening()
	view.set_round(r,1)
	await process_frame
	view.refresh()
	var empty: Array = view._exposed_layout()
	view.refresh()
	t.expect(empty.is_empty() and is_same(empty,view._exposed_layout()),"unchanged empty layout is cached")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/meld_layout_replay.json"))
	r = RoundState.new()
	r.set_rng_seed(int(record.seed))
	r.next_dealer_seat = int(record.dealer)
	r.controllers = [null,null,null,null]
	r.pause_after_opening = true
	r.start_round(1,int(record.red),int(record.white))
	r.resume_after_opening()
	for action in record.actions:
		var ok: bool = r.submit_turn(int(action.seat),action.decision) if action.kind=="turn" else r.submit_response(int(action.seat),str(action.tile),action.decision)
		t.expect(ok,"recorded layout action remains legal")
	for viewer in 4:
		view.set_round(r,viewer)
		var specs: Array = view._exposed_layout()
		view.refresh()
		t.expect(is_same(specs,view._exposed_layout()),"unchanged dense layout reuses cache at every seat")
		t.expect(specs==view.EXPOSED.solve(view),"cached positions equal a fresh solve")
		var wall_tile = view._wall_layer.get_child(0)
		wall_tile.position += Vector2(0.1,0)
		t.expect(not is_same(specs,view._exposed_layout()),"changed visual wall geometry invalidates cache")
		t.expect(view._exposed_layout()==view.EXPOSED.solve(view),"wall invalidation retains collision solver output")
		view.refresh()
		specs=view._exposed_layout()
		r.players[viewer].ready=not r.players[viewer].ready
		view.refresh()
		t.expect(not is_same(specs,view._exposed_layout()),"ready badge changes invalidate layout")
		t.expect(view._exposed_layout()==view.EXPOSED.solve(view),"new badge space remains clear")
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self,t.finish("table_render_cache"))
