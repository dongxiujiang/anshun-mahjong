extends SceneTree
## All four perspectives, local state and the actual seat-masked network snapshot.
const H = preload("res://tests/test_harness.gd")
var t = H.new()

class Host extends Node:
	var round: RoundState
	var human_seat: int
	func _clear_actions(): pass
	func _update_interactivity(): pass
	func _on_settlement_animation_finished(): pass

func _initialize(): call_deferred("run")

func fixture(kind: String) -> RoundState:
	var r = RoundState.new()
	r.build_players(0)
	r.controllers = [null,null,null,null]
	r.phase = RoundState.Phase.PLAYING
	var bag = TileSetFactory.create_deck()
	var used = []
	var melds = [
		{"kind":"pung","tile":"wan7","from_seat":3},
		{"kind":"kong","tile":"wan8","concealed":true},
		{"kind":"kong","tile":"wan9","from_seat":0},
		{"kind":"add_kong","tile":"tong9","from_seat":1}]
	for seat in 4:
		var p = r.players[seat]
		p.concealed = ["wan1","wan2","wan3","tiao2","tiao3","tiao4","tong2","tong3","tong4",["tong6","tong5","tiao5","wan5"][seat]]
		if kind == "mixed_draw" and seat == 1: p.concealed[0] = "tiao7"
		if kind in ["self_draw","ron"] and seat == 0: p.concealed.append("tong6")
		p.melds = [melds[seat]]
		p.discards = ["wan6","tiao1","tong8"]
		used.append_array(p.concealed)
		used.append_array(p.discards)
		for i in (3 if seat == 0 else 4): used.append(melds[seat].tile)
	for tile in used:
		t.expect(bag.has(tile), "fixture never exceeds four copies: " + tile)
		bag.erase(tile)
	if kind.ends_with("draw") and kind != "self_draw":
		for i in bag.size(): r.players[i%4].discards.append(bag[i])
		used.append_array(bag)
		bag.clear()
	for p in r.players:
		p.discard_ids.assign(range(p.discards.size()))
		p.discard_count = p.discards.size()
	r.round_meta.charge_chickens = {"tiao1":{"owner":0,"location":"discard","discard_id":1},"tong8":{"owner":1,"location":"discard","discard_id":2}}
	r.round_meta.winner = 0 if kind in ["self_draw","ron"] else -1
	r.round_meta.winners = [0] if r.round_meta.winner == 0 else []
	r.round_meta.self_draw = kind == "self_draw"
	r.round_meta.discard_seat = 1 if kind == "ron" else -1
	r.round_meta.win_tile = "tong6" if r.round_meta.winner == 0 else ""
	r.wall = WallRing.new(used+bag)
	for i in used.size(): r.wall.draw_head()
	r._finish()
	return r

func check(view, label: String):
	t.expect(not view._discard_layer.visible, label+": ordinary river hidden")
	var counts = [0,0,0,0]
	var charges = 0
	for tile in view._red_layer.get_children()+view._meld_layer.get_children():
		if not tile is TileView: continue
		var seat = int(tile.get_meta("v2_seat",-1))
		counts[seat] += 1
		t.expect(tile.is_visible_in_tree(), label+": exposed tile visible at seat %d"%seat)
		t.expect(tile.face_up, label+": concealed kong also revealed")
		if bool(tile.get_meta("v2_charge",false)): charges+=1
	t.expect(counts == [5,6,6,6], label+": all melds and eight discarded chickens retained")
	t.expect(charges == 2, label+": both charge chickens retained")

func run():
	root.get_node("GameConfig").set_score_details_enabled(false,false)
	for kind in ["self_draw","ron","mixed_draw","all_called_draw"]:
		var local = fixture(kind)
		for viewer in 4:
			var client = RoundState.new()
			client.apply_sync(local.serialize_for_seat(viewer))
			for state in [local,client]:
				var mode = "local" if state == local else "online"
				var label = "%s/%s/%d"%[kind,mode,viewer]
				var view = load("res://scenes/table/TableV2.tscn").instantiate()
				root.add_child(view)
				view.auto_sort_hands = false
				view.set_round(state,viewer)
				var host = Host.new()
				host.round = state
				host.human_seat = viewer
				root.add_child(host)
				view.table = host
				view.start_native_settlement(false)
				check(view,label+"/start")
				view._finish_native_settlement()
				check(view,label+"/end")
				view.table = null
				view.refresh()
				check(view,label+"/refresh")
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					DirAccess.make_dir_recursive_absolute("res://build/settlement-exposed")
					root.get_texture().get_image().save_png("res://build/settlement-exposed/%s-%s-%d.png"%[kind,mode,viewer])
				view.reset_native_settlement()
				t.expect(view._discard_layer.visible,label+": reset restores ordinary river")
				view.free()
				host.free()
				await process_frame
	await H.quit_cleanly(self,t.finish("settlement_exposed_visibility"))
