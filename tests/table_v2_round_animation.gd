extends SceneTree
## Regression coverage for the formal V2 animation path; also run with a Windows display.
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t = H.new()
var selected_case = "all"

class Host extends Control:
	var round: RoundState
	var human_seat = 1
	var _new_areas
	var _table_animation_controller
	var _seat_visual_keys = {}
	var _selecting = false
	func _refresh(): pass
	func _update_interactivity(): pass
	func _pump_visual_animation(): pass
	func _net_mode() -> String: return ""

func _initialize(): call_deferred("_run")

func _fixture():
	var host = Host.new()
	root.add_child(host)
	host.round = RoundState.new()
	host.round.build_players(1)
	host.round.phase = RoundState.Phase.PLAYING
	host.round.controllers = [null, null, null, null]
	var deck = load("res://scripts/ui/table/v2/TableV2.gd").new()
	host.add_child(deck)
	deck.round = host.round
	deck.human_seat = 1
	deck.table = host
	deck.auto_sort_hands = false
	deck._sort_started = true
	host._new_areas = deck
	var controller = load("res://scripts/ui/table/v2/TableV2AnimationController.gd").new(host)
	host._table_animation_controller = controller
	controller.build()
	controller._session = "regression"
	controller._dealt = [13,13,13,13]
	return host

func _card(deck, layer, card, seat, index, center = Vector2(300,300)):
	var node = deck._tile(layer, card, true, center, 0.7, 0.0)
	node.set_meta("concealed_index",index)
	node.set_meta("v2_seat",seat)
	return node

func _cleanup(host):
	host._new_areas._reset_round_visual_state()
	host._table_animation_controller.cancel()
	host._table_animation_controller.dispose_pool()
	host.queue_free()
	await process_frame

func _lifecycle():
	var host = _fixture()
	var deck = host._new_areas
	for i in 13: _card(deck,deck.hand_boxes[1],"wan%d" % (i%9+1),1,i)
	_card(deck,deck.draw_boxes[1],"tong9",1,13)
	var held = deck.hand_boxes[1].get_child(1)
	var state = {"insert":0,"draw":0,"discard":0}
	deck.animate_draw_insert(1,"wan1","tong9",func():state.insert+=1)
	deck.animate_draw(0,"wan9",0,func():state.draw+=1)
	await create_timer(0.14).timeout
	t.expect(state.draw==0 and state.insert==0,"draw and discard presentation both use the shared timed setting")
	deck.refresh()
	t.expect(held.get_parent()==deck.hand_boxes[1],"refresh cannot recycle an animation-owned hand tile")
	t.expect(deck.deal_animation_active and host._table_animation_controller.has_pending(),"all unfinished native actions remain pending")
	await create_timer(0.55).timeout
	t.expect(state.draw==1 and state.insert==1 and not deck.native_actions_pending(),"draw and insertion each complete once and release their holds")
	_card(deck,deck.draw_boxes[1],"wan9",1,13)
	host.round.players[1].discards=["wan9"]
	deck.animate_draw_discard(1,func():state.discard+=1)
	t.expect(state.discard==0 and host._table_animation_controller.input_locked(),"draw discard stays locked until its flight lands")
	await create_timer(0.35).timeout
	t.expect(state.discard==1 and not deck.native_actions_pending(),"draw discard completion runs exactly once after landing")
	t.expect(not host._table_animation_controller.input_locked() and not host._table_animation_controller.has_pending(),"completed Tween references do not keep native input or settlement locked")
	deck.animate_draw(0,"wan8",1,func():state.draw+=1)
	deck.recover_after_resume()
	await create_timer(0.4).timeout
	t.expect(state.draw==1 and not deck.native_actions_pending(),"cancelled Tweens cannot execute stale completion callbacks")
	await _cleanup(host)
	host=_fixture()
	deck=host._new_areas
	var config=root.get_node("GameConfig")
	config.set_tile_animation_seconds(0.54,false)
	var completed={"deals":0,"draws":0}
	deck.animate_deal_group(1,["wan1","wan2","wan3","wan4"],[0,1,2,3],0,func():completed.deals+=1)
	await create_timer(0.42).timeout
	deck.animate_draw(1,"wan9",4,func():completed.draws+=1)
	await create_timer(0.65).timeout
	t.expect(completed.deals==1 and completed.draws==1,"old deal timeout cannot recycle a later draw or repeat completion")
	host._table_animation_controller._on_visual_event({"session":"next-round","id":1,"type":"meld_reveal","seat":0,"index":0})
	t.expect(not deck._sort_started,"new event session resets opening visuals even when RoundState is reused")
	for seat in 4:host.round.players[seat].concealed=["hidden0","hidden0","hidden0","hidden0"]
	host._table_animation_controller._on_visual_event({"session":"next-round","id":2,"type":"discard","seat":0,"fast_forward":true})
	t.expect(not host._table_animation_controller.deal_sequence_active() and deck._sort_started,"merged short-hand snapshot recovers without reopening the initial deal gate")
	config.set_tile_animation_seconds(0.30,false)
	await _cleanup(host)

func _kong_draw():
	if DisplayServer.get_name()=="headless":
		t.expect(true,"native dispatch requires graphical driver; covered by Windows run")
		return
	var host = _fixture()
	var deck = host._new_areas
	var controller = host._table_animation_controller
	host.round.players[1].melds=[{"kind":"kong","tile":"wan5","concealed":true}]
	for i in 4: _card(deck,deck.hand_boxes[1],"wan5",1,i)
	controller._on_visual_event({"session":"regression","id":1,"type":"meld","seat":1,"tile":"","hand_indices":[0,1,2,3],"kind":"concealed","index":0})
	var draw_event={"session":"regression","id":2,"type":"draw","seat":1,"tile":"tong9","wall_index":107,"kind":"tail"}
	controller._on_visual_event(draw_event)
	t.expect(not controller._pending_draw_after_meld.is_empty() and not deck._draw_animating,"tail draw waits for kong flight")
	await create_timer(0.42).timeout
	t.expect(deck._draw_animating and controller._draw_cards[1]=="tong9","deferred tail draw executes after kong without duplicate rejection")
	controller._on_visual_event(draw_event)
	await create_timer(0.4).timeout
	t.expect(deck.draw_boxes[1].get_child_count()==1 and deck.draw_boxes[1].get_child(0).tile=="tong9","tail draw lands once even when event is redelivered")
	t.expect(controller._animation_last_id==2 and controller._pending_draw_after_meld.is_empty(),"receive cursor and deferred queue remain consistent")
	await _cleanup(host)

func _kong_sources():
	for kind in ["concealed","add_kong"]:
		var host=_fixture()
		var deck=host._new_areas
		host.round.players[1].melds=[{"kind":"kong" if kind=="concealed" else "add_kong","tile":"wan5","concealed":kind=="concealed"}]
		var unrelated=_card(deck,deck.hand_boxes[1],"wan1",1,3,Vector2(300,800))
		var drawn=_card(deck,deck.draw_boxes[1],"wan5",1,4,Vector2(900,800))
		var drawn_before=drawn.position
		for i in 3:
			var layer=deck.hand_boxes[1] if kind=="concealed" else deck._meld_layer
			var node=_card(deck,layer,"wan5",1,i,Vector2(400+i*50,800))
			node.set_meta("meld_index",0)
		deck.animate_meld({"seat":1,"tile":"wan5","kind":kind,"index":0,"hand_indices":[0,1,2,4] if kind=="concealed" else [4]},func():pass)
		await create_timer(0.55).timeout
		t.expect(unrelated.get_parent()==deck.hand_boxes[1] and unrelated.tile=="wan1" and str(unrelated.get_meta("new_kind",""))=="hand",kind+": unrelated hand entity stays in the hand while it recenters")
		t.expect(drawn.position.distance_to(drawn_before)>10,kind+": fourth tile originates from draw box")
		await _cleanup(host)
	var host=_fixture()
	var deck=host._new_areas
	host.round.players[0].melds=[{"kind":"kong","tile":"hidden0","concealed":true}]
	var nodes=[]
	for i in 7: nodes.append(_card(deck,deck.hand_boxes[0],"",0,i,Vector2(100+i*50,400)))
	var matching_before=nodes[3].position
	deck.animate_meld({"seat":0,"tile":"hidden0","kind":"concealed","index":0,"hand_indices":[3,4,5,6]},func():pass)
	await create_timer(0.55).timeout
	t.expect(nodes[0].get_parent()==deck.hand_boxes[0] and nodes[3].get_parent()==deck._meld_layer and nodes[3].position!=matching_before and not nodes[3].face_up and nodes[3].tile=="","hidden kong sources use authoritative indices without exposing values")
	await _cleanup(host)
	for source_seat in [2, 0, 3]:
		for value in ["wan5", "tong8"]:
			host = _fixture()
			deck = host._new_areas
			host.round.players[1].melds = [{"kind": "kong", "tile": value, "from_seat": source_seat}]
			for i in 3:
				_card(deck, deck.hand_boxes[1], value, 1, i)
			var chicken: bool = value == "tong8"
			var origin: Control = deck._red_layer if chicken else deck._discard_layer
			var destination: Control = deck._red_layer if chicken else deck._meld_layer
			var claimed: TileView = _card(deck, origin, value, source_seat, -1)
			claimed.set_meta("discard_id", 7)
			deck.animate_meld({"seat": 1, "source": source_seat, "source_discard_id": 7, "kind": "kong",
				"tile": value, "index": 0, "hand_indices": [0, 1, 2]}, func(): pass)
			await create_timer(0.55).timeout
			var expected_slot := 0 if source_seat == 2 else 3
			t.expect(claimed.get_parent() == destination and int(claimed.get_meta("meld_slot", -1)) == expected_slot
				and is_equal_approx(claimed.rotation, PI / 2.0),
				"%s exposed kong lands its real source discard sideways in slot %d" % [value, expected_slot])
			if source_seat == 3:
				var middle: TileView
				for node in destination.get_children():
					if int(node.get_meta("meld_slot", -1)) == 1:
						middle = node
				var center := claimed.position + claimed.size / 2.0
				t.expect(middle != null and is_equal_approx(center.x, (middle.position + middle.size / 2.0).x)
					and center.y < (middle.position + middle.size / 2.0).y,
					"%s opposite discard lands centered above the upright row" % value)
			await _cleanup(host)

func _discard_sources():
	for flying in [false,true]:
		var host=_fixture()
		var deck=host._new_areas
		host.round.players[1].melds=[{"kind":"pung","tile":"wan5"}]
		for i in 2: _card(deck,deck.hand_boxes[1],"wan5",1,i)
		var wrong=_card(deck,deck._discard_layer,"tong2",0,-1,Vector2(500,300))
		wrong.set_meta("discard_id",0)
		var wrong_before=wrong.position
		var correct=_card(deck,deck.draw_boxes[2] if flying else deck._discard_layer,"wan5",2,13,Vector2(800,300))
		correct.set_meta("discard_id",0)
		var correct_before=correct.position
		if flying:
			host.round.players[2].discards=["wan5"]
			host.round.players[2].discard_ids=[0]
			deck.animate_draw_discard(2,func():pass)
		deck.animate_meld({"seat":1,"tile":"wan5","kind":"pung","index":0,"source":2,"source_discard_id":0,"hand_indices":[0,1]},func():pass)
		await create_timer(0.5).timeout
		t.expect(wrong.position==wrong_before,"source with same id at another seat remains untouched")
		t.expect(correct.position!=correct_before,"meld uses exact source seat and discard id, including in-flight discard")
		t.expect(deck._discard_flights.is_empty(),"claimed flying discard cannot later create a ghost landing")
		await _cleanup(host)

func _remote_discards():
	for from_draw in [false,true]:
		var host=_fixture()
		var deck=host._new_areas
		var controller=host._table_animation_controller
		for i in 13:
			var hidden=_card(deck,deck.hand_boxes[0],"",0,i)
			hidden.set_card("",false)
		var draw=_card(deck,deck.draw_boxes[0],"hidden0",0,13)
		draw.set_card("hidden0",false)
		host.round.players[0].discards=["wan9"]
		host.round.players[0].discard_ids=[0]
		controller._draw_cards[0]="hidden0"
		var old_indices=range(13)
		old_indices.erase(5)
		old_indices.insert(4,13)
		var slots={}
		for slot in old_indices.size(): slots[old_indices[slot]]=slot
		if DisplayServer.get_name()!="headless":
			controller._on_visual_event({"session":"regression","id":1,"type":"discard","seat":0,"tile":"wan9","discard_from_draw":from_draw,"draw_tile":"hidden0","discard_index":13 if from_draw else 5,"hand_slot_map":slots})
		elif from_draw:
			deck.animate_draw_discard(0,func():pass,"wan9")
		else:
			deck.animate_draw_insert(0,"wan9","hidden0",func():pass,5,slots)
		await create_timer(0.95).timeout
		t.expect(deck.hand_boxes[0].get_child_count()==13 and deck.draw_boxes[0].get_child_count()==0,"remote discard preserves 13 concealed tiles and no draw slot")
		t.expect(deck._discard_layer.get_child_count()==1 and deck._discard_layer.get_child(0).tile=="wan9","public discard uses event value instead of hidden0")
		var hidden_count=0
		for node in deck.hand_boxes[0].get_children():
			if not node.face_up: hidden_count+=1
		t.expect(hidden_count==13,"remote remaining hand stays private")
		if not from_draw:
			t.expect(deck.hand_boxes[0].get_child(4)==draw and int(draw.get_meta("concealed_index"))==12,"hidden draw inserts by authoritative slot map with updated source index")
		await _cleanup(host)
	var host=_fixture()
	var deck=host._new_areas
	var first=_card(deck,deck.hand_boxes[1],"wan3",1,0)
	_card(deck,deck.hand_boxes[1],"wan1",1,1)
	_card(deck,deck.hand_boxes[1],"wan3",1,2)
	_card(deck,deck.draw_boxes[1],"tong9",1,3)
	deck.animate_draw_insert(1,"wan3","tong9",func():pass,2,{0:1,1:0,3:2})
	await create_timer(0.85).timeout
	t.expect(first.get_parent()==deck.hand_boxes[1],"clicking second identical tile does not discard the first copy")
	await _cleanup(host)

func _discard_during_draw():
	for from_draw in [true, false]:
		var host = _fixture()
		var view = host._new_areas
		var seat := 0
		var player: PlayerState = host.round.players[seat]
		for i in 13:
			player.concealed.append("hidden0")
			var tile = _card(view, view.hand_boxes[seat], "", seat, i,
				G.hand_slot_center(seat, i, 1, 13))
			tile.set_card("", false)
		view.animate_draw(seat, "hidden0", 29, func(): pass)
		t.expect(view.draw_boxes[seat].get_child_count() == 0, "The opponent's earlier draw is still flying")
		player.discards = ["wan9"]
		player.discard_ids = [0]
		if from_draw:
			view.animate_draw_discard(seat, func(): pass, "wan9")
		else:
			view.animate_draw_insert(seat, "wan9", "hidden0", func(): pass, 4)
		t.expect(not view._discard_flights.is_empty() or view._discard_layer.get_child_count() == 1,
			"Public discard starts immediately while the older opponent draw is still flying")
		await create_timer(0.7).timeout
		t.expect(view._discard_layer.get_child_count() == 1 and view.draw_boxes[seat].get_child_count() == 0,
			"Only the public discard remains after the interrupted draw")
		await _cleanup(host)

func _remote_discard_without_draw():
	if DisplayServer.get_name() == "headless": return
	var host = _fixture()
	var view = host._new_areas
	host.round.players[0].discards = ["wan9"]
	host.round.players[0].discard_ids = [0]
	_card(view, view.hand_boxes[0], "hidden0", 0, 0, G.hand_slot_center(0, 0, 1, 4))
	host._table_animation_controller._pending_draw_after_meld = {"seat": 0, "tile": "hidden0"}
	host._table_animation_controller._on_visual_event({
		"session": "regression", "id": 1, "type": "discard", "seat": 0, "tile": "wan9",
		"draw_tile": "hidden0", "drawn_source_index": -1, "discard_index": 0})
	t.expect(not view._discard_flights.is_empty() or view._discard_layer.get_child_count() == 1,
		"Legacy masked discard after a pung still starts with no draw slot")
	t.expect(host._table_animation_controller._pending_draw_after_meld.is_empty(),
		"An authoritative discard clears a superseded draw queued by a meld animation")
	await _cleanup(host)

func _remote_discards_without_source():
	var host = _fixture()
	var view = host._new_areas
	view.animate_draw(1, "wan2", 53, func(): pass)
	var cards := {0: "wan9", 2: "tiao1", 3: "tong8"}
	for seat: int in [0, 2, 3]:
		var player: PlayerState = host.round.players[seat]
		player.discards = [cards[seat]]
		player.discard_ids = [0]
		if seat == 0:
			view.animate_draw_discard(seat, func(): pass, cards[seat])
		elif seat == 2:
			view._pending_draws[seat] = "hidden0"
			view.animate_draw_insert(seat, cards[seat], "hidden0", func(): pass, 4)
			t.expect(view._pending_draws[seat] == "", "Missing draw source cannot leave a stale draw placeholder")
		else:
			view.animate_hand_discard(seat, cards[seat], 4, func(): pass)
		var river: Control = view._discard_layer if seat == 0 else view._red_layer
		var public_tiles := river.get_children().filter(func(node):
			return int(node.get_meta("v2_seat", -1)) == seat and int(node.get_meta("discard_id", -1)) == 0)
		t.expect(public_tiles.size() == 1 and public_tiles[0].tile == cards[seat] and public_tiles[0].face_up,
			"Opponent %d's public discard appears immediately even without a source node" % seat)
	t.expect(view._draw_flights.has(1), "Independent opponent discards do not cancel the viewer's draw")
	view.animate_draw_discard(0, func(): pass, cards[0])
	t.expect(view._discard_layer.get_child_count() == 1, "The same authoritative discard lands only once")
	await _cleanup(host)

func _refresh_during_discard_flight():
	var host = _fixture()
	var view = host._new_areas
	var tile = _card(view, view.draw_boxes[1], "wan9", 1, 13, Vector2(800, 500))
	host.round.players[1].discards = ["wan9"]
	host.round.players[1].discard_ids = [0]
	view._fly_discard(tile, 1, "wan9", Callable())
	t.expect(not view._discard_flights.is_empty(), "The discard is still in flight when the table refresh arrives")
	view.refresh()
	t.expect(tile.get_parent() == view._deal_layer and tile.is_visible_in_tree(), "Refreshing preserves the same visible discard actor in the animation layer")
	await create_timer(0.45).timeout
	t.expect(tile.get_parent() == view._discard_layer and view._discard_layer.get_child_count() == 1,
		"The same tile lands once after a concurrent refresh")
	await _cleanup(host)

func _deal_privacy():
	for seat in [0,1,2,3]:
		var host=_fixture()
		var deck=host._new_areas
		var completed={"count":0}
		deck.animate_deal_group(seat,["wan1","wan2","tong3","tiao4"],[0,1,2,3],0,func():completed.count+=1)
		var exposed=0
		for node in deck._deal_layer.get_children():
			if node.face_up: exposed+=1
		t.expect(exposed==(4 if seat==1 else 0),"deal flight only exposes viewer's own cards, seat%d" % seat)
		await create_timer(0.4).timeout
		t.expect(completed.count==1,"private deal still completes once")
		await _cleanup(host)

func _chicken_kong_privacy():
	for tile in ["tiao1","tong8"]:
		for seat in [0,1]:
			var host=_fixture()
			var deck=host._new_areas
			host.round.players[seat].melds=[{"kind":"kong","tile":tile,"concealed":true,"after_discard":0}]
			for discards in [0,1,2]:
				host.round.players[seat].discard_count=discards
				deck.snapshot=deck.MODEL.build(host.round,1)
				deck._clear(deck._red_layer)
				deck._build_melds()
				var face_count=0
				for node in deck._red_layer.get_children():
					if node.face_up: face_count+=1
				t.expect(face_count==(4 if seat==1 or discards>=2 else 0),"chicken concealed kong visibility follows owner and two-discard reveal")
			host.round.phase=RoundState.Phase.SETTLED
			deck.snapshot=deck.MODEL.build(host.round,1)
			deck._clear(deck._red_layer)
			deck._build_melds()
			t.expect(deck._red_layer.get_child_count()==4 and deck._red_layer.get_child(0).face_up,"settlement reveals chicken concealed kong")
			await _cleanup(host)

func _meld_zones():
	for kind in ["pung","kong","add_kong"]:
		for chicken in [false,true]:
			var host=_fixture()
			var deck=host._new_areas
			var tile="tiao1" if chicken else "wan5"
			host.round.players[1].melds=[{"kind":kind,"tile":tile}]
			deck.snapshot=deck.MODEL.build(host.round,1)
			deck._build_melds()
			var count=3 if kind=="pung" else 4
			t.expect(deck._red_layer.get_child_count()==(count if chicken else 0),"red zone contains only chicken melds with correct cardinality: "+kind)
			t.expect(deck._meld_layer.get_child_count()==(0 if chicken else count),"ordinary meld renders exactly once outside red zone: "+kind)
			await _cleanup(host)

func _short_hand_layout():
	for seat in 4:
		for count in ([13,10,7,4,1] if seat==1 else [4]):
			var host=_fixture()
			var deck=host._new_areas
			for i in count: _card(deck,deck.hand_boxes[seat],"wan%d" % (i%9+1),seat,i)
			_card(deck,deck.draw_boxes[seat],"tong9",seat,count)
			var slots={}
			for i in range(1,count+1):slots[i]=i-1
			deck.animate_draw_insert(seat,"wan1","tong9",func():pass,0,slots)
			await create_timer(0.85).timeout
			t.expect(deck.hand_boxes[seat].get_child_count()==count,"insert preserves short-hand tile count")
			var positioned=true
			for slot in count:
				var node=deck.hand_boxes[seat].get_child(slot)
				if not (node.position+node.size/2.0).is_equal_approx(G.hand_slot_center(seat,slot,1,count)):
					positioned=false
			t.expect(positioned,"short-hand insert lands at actual count for every seat, count%d seat%d" % [count,seat])
			await _cleanup(host)

func _settlement_faces():
	var host=_fixture()
	var deck=host._new_areas
	for seat in 4:
		host.round.players[seat].concealed=["tiao1","wan2","wan3","wan4","wan5","wan6","tiao2","tiao3","tiao4","tong1","tong2","tong3","wan9"]
	for seat in [0,2]:
		host.round.players[seat].concealed.append("wan9")
		host.round.players[seat].just_drew="wan9"
	host.round.round_meta.winners=[0,2]
	deck.snapshot=deck.MODEL.build(host.round,1)
	deck._build_hands()
	t.expect(not deck.hand_boxes[0].get_child(0).face_up,"opponent hand stays hidden during play")
	deck._clear_hand_tiles()
	host.round.phase=RoundState.Phase.SETTLED
	host._table_animation_controller._dealt=[0,0,0,0]
	t.expect(not deck._opening_mode(),"restored settlement does not hide hands behind an unprimed deal gate")
	deck.snapshot=deck.MODEL.build(host.round,1)
	deck._build_hands()
	for seat in 4:
		var all_revealed=true
		for node in deck.hand_boxes[seat].get_children():
			if not node.face_up or node.tile=="":all_revealed=false
		t.expect(all_revealed,"settlement exposes actual hand values for seat%d" % seat)
		if seat in [0,2]:
			t.expect(deck.draw_boxes[seat].get_child_count()==1 and deck.draw_boxes[seat].get_child(0).tile=="wan9","each winner retains a separate public winning tile")
	deck._settlement_plan={"called":[true,true,true,true],"burned":-1,"gold_tiles":[],"flip_tiles":[],"is_draw":false}
	deck._highlight_native_stage({"key":"chicken"})
	var highlighted=0
	for node in deck.hand_boxes[0].get_children():
		if node.tile=="tiao1" and node.score_highlight:highlighted+=1
	t.expect(highlighted==1,"opponent hand chicken participates in native settlement highlight")
	deck._clear_hand_tiles()
	host.round.round_meta.winners=[]
	host.round.round_meta.all_called_draw=true
	for seat in [0,2]:
		host.round.players[seat].concealed.pop_back()
		host.round.players[seat].just_drew=""
	deck.snapshot=deck.MODEL.build(host.round,1)
	deck._build_hands()
	for seat in 4:
		t.expect(deck.hand_boxes[seat].get_child_count()==13 and deck.hand_boxes[seat].get_children().all(
			func(node):return node.face_up and node.tile!=""),"all-called draw exposes every hand tile for seat%d" % seat)
	await _cleanup(host)

func _speed_settings():
	var config=root.get_node("GameConfig")
	var saved_seconds=config.tile_animation_seconds
	for kind in ["draw","discard","meld"]:
		var times={}
		for seconds in [0.0,0.1,0.3,1.0]:
			var host=_fixture()
			var deck=host._new_areas
			config.set_tile_animation_seconds(seconds,false)
			var state={"count":0,"elapsed":0}
			var started=Time.get_ticks_msec()
			var complete=func():state.count+=1;state.elapsed=Time.get_ticks_msec()-started
			if kind=="draw":
				deck.animate_draw(1,"wan9",0,complete)
			elif kind=="discard":
				_card(deck,deck.draw_boxes[1],"wan9",1,13)
				host.round.players[1].discards=["wan9"]
				host.round.players[1].discard_ids=[0]
				deck.animate_draw_discard(1,complete,"wan9")
			else:
				for i in 3: _card(deck,deck.hand_boxes[1],"wan5",1,i,Vector2(300+i*70,1000))
				host.round.players[1].melds=[{"kind":"pung","tile":"wan5","from_seat":0}]
				deck.animate_meld({"seat":1,"tile":"wan5","kind":"pung","index":0,"hand_indices":[0,1,2]},complete)
			if seconds==0.0:t.expect(state.count==1 and not deck.native_actions_pending(),kind+": instant lands and completes synchronously")
			else:t.expect(state.count==0 and deck.native_actions_pending(),kind+": timed motion initially pending")
			var deadline=Time.get_ticks_msec()+3000
			while state.count==0 and Time.get_ticks_msec()<deadline: await process_frame
			t.expect(state.count==1 and not deck.native_actions_pending(),kind+": every speed completes exactly once")
			times[seconds]=state.elapsed
			await _cleanup(host)
		t.expect(times[0.1]<times[0.3] and times[0.3]<times[1.0],kind+": real flight duration follows the shared slider")
	config.set_tile_animation_seconds(saved_seconds,false)

func _opening_speed_settings():
	if DisplayServer.get_name() == "headless": return
	var config = root.get_node("GameConfig")
	var saved_seconds: float = config.tile_animation_seconds
	var times: Array[int] = []
	for seconds in [0.0, 1.0]:
		config.set_tile_animation_seconds(seconds, false)
		var table = load("res://scenes/GameTable.tscn").instantiate()
		var started := Time.get_ticks_msec()
		root.add_child(table)
		table.round.controllers = [null, null, null, null]
		var controller = table._table_animation_controller
		var allowed_ms := int(config.opening_wait_seconds(config.opening_speed_key()) * 1000.0) + 3000
		var deadline := started + allowed_ms
		while Time.get_ticks_msec() < deadline:
			if controller._dealt == [13, 13, 13, 13] and not table._new_areas._sort_animating:
				break
			await process_frame
		var elapsed := Time.get_ticks_msec() - started
		times.append(elapsed)
		t.expect(controller._dealt == [13, 13, 13, 13] and elapsed < allowed_ms, "opening slider leaves all four hands correctly dealt")
		var start_turn_deadline := Time.get_ticks_msec() + 2000
		while table.round.phase == RoundState.Phase.DEALING and Time.get_ticks_msec() < start_turn_deadline:
			await process_frame
		t.expect(table.round.phase == RoundState.Phase.PLAYING and not table.round.pause_after_opening, "opening releases play after the deal at either endpoint")
		if table._ai_service != null: table._ai_service.stop()
		table.queue_free()
		await process_frame
	t.expect(times[1] - times[0] >= 1650, "one-second opening setting adds visible tile motion after the fixed dice beat")
	config.set_tile_animation_seconds(saved_seconds, false)

func _authoritative_melds():
	if DisplayServer.get_name()=="headless":
		t.expect(true,"authoritative meld visuals covered in graphical run")
		return
	for kind in ["concealed","add_kong","kong","pung"]:
		var table=load("res://scenes/GameTable.tscn").instantiate()
		root.add_child(table)
		table.round.cancel_opening()
		table._table_animation_controller.cancel()
		var r=RoundState.new()
		r.build_players(1)
		r.controllers=[null,null,null,null]
		r.phase=RoundState.Phase.PLAYING
		r.current_turn=1
		r.wall=WallRing.new(TileSetFactory.create_deck())
		r.wall.set_head(0)
		for seat in 4:r.players[seat].concealed=["wan1","wan2","wan3","tiao2","tiao3","tiao4","tong1","tong2","tong3","wan7","wan8","wan9","tong9"]
		var p=r.players[1]
		if kind=="concealed":
			p.concealed=p.concealed.slice(0,10)+["wan5","wan5","wan5","wan5"]
			p.just_drew="wan5"
		elif kind=="add_kong":
			p.melds=[{"kind":"pung","tile":"wan5","from_seat":0}]
			p.concealed=p.concealed.slice(0,10)+["wan5"]
			p.just_drew="wan5"
		else:
			var n=3 if kind=="kong" else 2
			p.concealed=p.concealed.slice(0,13-n)
			for i in n:p.concealed.append("wan5")
			r.players[0].discards=["wan5"]
			r.players[0].discard_ids=[0]
			r.last_discard={"seat":0,"tile":"wan5"}
			r._response_stage=RoundState.ResponseStage.MELD
		table.round=r
		table._connect_audio_round()
		table._table_animation_controller._session=r._presentation.session
		r.state_update.connect(table._queue_refresh)
		r.require_turn.connect(table._on_require_turn)
		table._table_animation_controller._dealt=[13,13,13,13]
		table._new_areas.auto_sort_hands=false
		table._refresh()
		await RenderingServer.frame_post_draw
		if kind=="concealed":r._do_concealed_kong(1,"wan5",p)
		elif kind=="add_kong":r._do_add_kong(1,"wan5")
		else:r._process_response(1,0,"wan5",{"action":"kong" if kind=="kong" else "pong"})
		var starts := {}
		for actor in table._new_areas._deal_layer.get_children():
			starts[actor.get_instance_id()] = actor.position
		t.expect(starts.size() == (3 if kind == "pung" else 4), kind + ": authority starts visible flying tiles instead of instant placement")
		await create_timer(0.08).timeout
		await process_frame
		var moved := false
		for actor in table._new_areas._deal_layer.get_children():
			if starts.has(actor.get_instance_id()):
				moved = moved or actor.position.distance_to(starts[actor.get_instance_id()]) > 1.0
				t.expect(actor.is_visible_in_tree(), kind + ": flying tile remains visible")
		t.expect(moved, kind + ": authoritative meld visibly moves before landing")
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/meld-motion"))
		root.get_texture().get_image().save_png("res://build/meld-motion/authority-" + kind + ".png")
		var deck=table._new_areas
		if kind == "kong":
			var deadline := Time.get_ticks_msec() + 950
			while not deck._draw_animating and Time.get_ticks_msec() < deadline:
				await process_frame
			t.expect(deck._draw_animating, "actual kong supplement is visible in flight")
			await _capture_motion("kong-tail-draw")
		await create_timer(1.1).timeout
		t.expect(p.melds.size()==1 and deck._meld_layer.get_child_count()==(3 if kind=="pung" else 4),kind+": authority and rendered meld cardinality agree")
		t.expect(not table._table_animation_controller.has_pending(),kind+": authoritative sequence finishes without stuck visuals")
		if kind!="pung":
			t.expect(deck.hand_boxes[1].get_child_count()==10 and deck.draw_boxes[1].get_child_count()==1,kind+": kong leaves 10 plus one tail draw")
			t.expect(deck.draw_boxes[1].get_child_count()==1 and deck.draw_boxes[1].get_child(0).tile==p.just_drew,kind+": rendered replacement equals authoritative tail tile")
		else:
			t.expect(deck.hand_boxes[1].get_child_count()==11 and deck.draw_boxes[1].get_child_count()==0,"pung starts discard turn without drawing")
			r._discard(1,str(p.concealed[0]),0)
			await create_timer(0.08).timeout
			t.expect(not deck._discard_flights.is_empty(), "real post-pung discard is visible in flight")
			await _capture_motion("discard-after-pong")
			await create_timer(0.7).timeout
			t.expect(deck.hand_boxes[1].get_child_count()==10 and not table._table_animation_controller.has_pending(),"real post-pung discard animates and completes")
		if table._ai_service!=null:table._ai_service.stop()
		table.queue_free()
		await process_frame

func _rejoin_live_hand():
	var host = _fixture()
	var controller = host._table_animation_controller
	var view = host._new_areas
	for player in host.round.players:
		player.concealed = ["wan1", "wan2", "wan3", "wan4"]
	host.round._presentation.session = "restored-round"
	host.round._presentation.event_id = 36
	controller.recover_after_resume()
	view.refresh()
	t.expect(view.hand_boxes[1].get_child_count() == 4, "Rejoin restores the shortened authoritative hand")
	controller._on_visual_event({"session":"restored-round", "id":37, "type":"meld_reveal", "seat":0, "index":0})
	view.refresh()
	t.expect(not controller.deal_sequence_active() and view.hand_boxes[1].get_child_count() == 4,
		"The next live event in a restored round cannot hide the hand or reopen dealing")
	await _cleanup(host)

	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round = RoundState.new()
	table.round.build_players(1)
	table.round.phase = RoundState.Phase.PLAYING
	table.human_seat = 1
	table.round.players[1].concealed = ["wan1", "wan2", "wan3", "wan4"]
	table._connect_audio_round()
	table._opening_primed = true
	table._awaiting_rejoin_snapshot = true
	table._on_client_state_updated()
	t.expect(not table._awaiting_rejoin_snapshot and not table._table_animation_controller.deal_sequence_active(),
		"An existing table restores its dealt baseline before unlocking after transport reconnect")
	t.expect(table._new_areas.hand_boxes[1].get_child_count() == 4,
		"An existing table immediately redraws the shortened hand after reconnect")
	var active_round := RoundState.new()
	active_round.controllers = [null, null, null, null]
	active_round.start_round(1, 2, 3)
	table.round = active_round
	table._connect_audio_round()
	table._opening_primed = false
	table._table_animation_controller.cancel()
	table._prime_opening_visuals()
	table._refresh()
	t.expect(not table._table_animation_controller.deal_sequence_active(),
		"Joining after the first draw never replays the initial deal over a running round")
	t.expect(table._new_areas.draw_boxes[active_round.dealer_seat].get_child_count() == 1,
		"A late join before the first discard preserves the dealer's already drawn tile")
	if table._ai_service != null: table._ai_service.stop()
	table.queue_free()
	await process_frame

func _online_opening_wall():
	var host = _fixture()
	var view = host._new_areas
	var authority := RoundState.new()
	authority.build_players(1)
	authority.controllers = [null, null, null, null]
	authority.pause_after_opening = true
	authority.start_round(1, 2, 3)
	var serializer = load("res://scripts/core/RoundSerializer.gd")
	serializer.apply_sync(host.round, serializer.serialize_for_seat(authority, 1))
	view.snapshot = load("res://scripts/ui/table/v2/TableV2Model.gd").build(host.round, 1)
	view.test_frozen = true
	for dealt in [[0, 0, 0, 0], [4, 4, 4, 4], [13, 13, 13, 13]]:
		host._table_animation_controller._dealt = dealt
		var shown: int = dealt[0] * 4
		for seat in 4:
			t.expect(view._wall_slots(seat) == authority.wall.debug_stack_slots_at(seat, shown),
				"Client wall matches the authoritative slots after %d displayed tiles, seat %d" % [shown, seat])
	var finished := {"deal": false, "draw": false}
	view.animate_deal_group(1, ["wan1", "wan2", "wan3", "wan4"], [], 0,
		func(): finished.deal = true)
	t.expect(finished.deal and not view.deal_animation_active, "A legacy deal without slots never flies from the table center")
	view.animate_draw(1, "wan1", -1, func(): finished.draw = true)
	t.expect(finished.draw and view.draw_boxes[1].get_child_count() == 1,
		"A legacy draw without a slot appears directly in the draw area")
	await _cleanup(host)

func _held_draw_envelope():
	for seat in 4:
		var host = _fixture()
		var deck = host._new_areas
		var centers: Array = []
		# 暗杠来自原有手牌，而上一次刚摸的牌仍留在原摸牌位置。
		for slot in range(4,13): centers.append(G.hand_slot_center(seat,slot,1,13))
		centers.append(G.draw_slot_center(seat,1,13))
		deck._held_hand_centers[seat] = centers
		var target: Vector2 = deck._draw_center(seat,10)
		var direction: Vector2 = [Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN][G.relative_seat(1,seat)]
		t.expect(target.dot(direction) <= G.draw_slot_center(seat,1,13).dot(direction), "second replacement draw stays within the original hand envelope")
		for center: Vector2 in centers:
			t.expect(absf((target-center).dot(direction)) >= G.hand_tile_size(seat,1).x + 19.9, "replacement draw cannot cover any retained hand tile")
		await _cleanup(host)

func _held_after_meld():
	var config = root.get_node("GameConfig")
	for seconds in [0.0, 0.2]:
		config.set_tile_animation_seconds(seconds, false)
		for seat in 4:
			for kind in ["pung", "kong", "concealed", "add_kong"]:
				var host = _fixture()
				var deck = host._new_areas
				var p = host.round.players[seat]
				var source = posmod(seat + 1, 4)
				var removed = 1 if kind == "add_kong" else (4 if kind == "concealed" else (3 if kind == "kong" else 2))
				for i in 13: p.concealed.append("wan5" if i < removed else "tong%d" % (i % 9 + 1))
				if kind == "add_kong": p.melds = [{"kind":"pung", "tile":"wan5", "from_seat":source}]
				var src = host.round.players[source]
				src.discards = ["wan5"]
				src.discard_ids = [4]
				deck.refresh()
				var positions = {}
				for tile in deck.hand_boxes[seat].get_children():
					if int(tile.get_meta("concealed_index", -1)) >= removed: positions[tile] = tile.position
				var indices = []
				for i in removed: indices.append(i)
				p.concealed = p.concealed.slice(removed)
				p.melds = [{"kind":"add_kong" if kind == "add_kong" else ("pung" if kind == "pung" else "kong"), "tile":"wan5", "from_seat":source, "concealed":kind == "concealed"}]
				var event = {"seat":seat, "tile":"wan5", "kind":kind, "index":0, "hand_indices":indices}
				if kind in ["pung", "kong"]:
					event.source = source
					event.source_discard_id = 4
				var done = {"meld":false,"discard":false,"draw":false}
				deck.animate_meld(event, func(): done.meld = true)
				await create_timer(seconds + 0.06).timeout
				deck.refresh()
				t.expect(done.meld and deck._held_hand_centers.has(seat), kind + ": hand position is held for seat %d" % seat)
				for tile in positions:
					t.expect(is_instance_valid(tile) and tile.position.is_equal_approx(positions[tile]), kind + ": surviving hand hit targets never move after claim and refresh")
				if kind != "pung":
					p.concealed.append("tiao9")
					p.just_drew = "tiao9"
					deck.animate_draw(seat, "tiao9", -1, func(): done.draw = true)
					deck.refresh()
					for tile in positions: t.expect(tile.position.is_equal_approx(positions[tile]), "replacement draw also preserves the old hit targets")
					p.concealed.pop_back()
					p.just_drew = ""
					p.discards.append("tiao9")
					p.discard_ids.append(8)
					deck.animate_draw_discard(seat, func(): done.discard = true, "tiao9")
				else:
					var value = str(p.concealed[0])
					p.concealed.remove_at(0)
					p.discards.append(value)
					p.discard_ids.append(8)
					deck.animate_hand_discard(seat, value, 0, func(): done.discard = true)
				await create_timer(seconds + 0.08).timeout
				deck.refresh()
				t.expect(done.discard and not deck._held_hand_centers.has(seat), "discard releases held hand exactly once")
				for tile in deck.hand_boxes[seat].get_children():
					var slot = int(tile.get_meta("v2_hand_slot", -1))
					t.expect((tile.position + tile.size / 2.0).is_equal_approx(G.hand_slot_center(seat, slot, 1, p.concealed.size())), "hand recenters after discard")
				if DisplayServer.get_name() != "headless" and seconds > 0:
					await RenderingServer.frame_post_draw
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/meld-motion"))
					root.get_texture().get_image().save_png("res://build/meld-motion/held-%d-%s.png" % [seat, kind])
				await _cleanup(host)
	config.set_tile_animation_seconds(0.3, false)

func _capture_motion(name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://build/equal-table/motion")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/equal-table/motion/" + name + ".png")

func _run():
	# Tests use a known baseline without persisting user preferences.
	root.get_node("GameConfig").set_tile_animation_seconds(0.30,false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): selected_case=arg.substr(7)
	if selected_case in ["all","lifecycle"]: await _lifecycle()
	if selected_case in ["all","kong_draw"]: await _kong_draw()
	if selected_case in ["all","held_draw_envelope"]: await _held_draw_envelope()
	if selected_case in ["all","held_after_meld"]: await _held_after_meld()
	if selected_case in ["all","kong_sources"]: await _kong_sources()
	if selected_case in ["all","discard_sources"]: await _discard_sources()
	if selected_case in ["all","remote_discards"]: await _remote_discards()
	if selected_case in ["all","discard_during_draw"]: await _discard_during_draw()
	if selected_case in ["all","remote_discard_without_draw"]: await _remote_discard_without_draw()
	if selected_case in ["all","remote_discards_without_source"]: await _remote_discards_without_source()
	if selected_case in ["all","refresh_during_discard_flight"]: await _refresh_during_discard_flight()
	if selected_case in ["all","deal_privacy"]: await _deal_privacy()
	if selected_case in ["all","online_opening_wall"]: await _online_opening_wall()
	if selected_case in ["all","rejoin_live_hand"]: await _rejoin_live_hand()
	if selected_case in ["all","chicken_kong_privacy"]: await _chicken_kong_privacy()
	if selected_case in ["all","meld_zones"]: await _meld_zones()
	if selected_case in ["all","short_hand_layout"]: await _short_hand_layout()
	if selected_case in ["all","settlement_faces"]: await _settlement_faces()
	if selected_case in ["all","speed_settings"]:
		await _speed_settings()
		await _opening_speed_settings()
	if selected_case in ["all","authoritative_melds"]: await _authoritative_melds()
	await H.quit_cleanly(self,t.finish("table_v2_round_animation"))
