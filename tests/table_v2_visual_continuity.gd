extends SceneTree
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t = H.new()

class Host extends Control:
	var round: RoundState
	var human_seat = 1
	var _new_areas
	var _table_animation_controller
	func _refresh(): _new_areas.refresh()
	func _update_interactivity(): pass
	func _pump_visual_animation(): pass
	func _net_mode(): return ""

func _initialize(): call_deferred("_run")

func fixture():
	var host = Host.new()
	root.add_child(host)
	host.round = RoundState.new()
	host.round.build_players(1)
	host.round.phase = RoundState.Phase.PLAYING
	host.round.controllers = [null, null, null, null]
	host.round.wall = WallRing.new(TileSetFactory.create_deck())
	host.round.wall.set_head(0)
	for player in host.round.players:
		player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tiao2", "tiao3", "tong2", "tong3"]
		player.discards = ["tiao1", "wan2"]
		player.discard_ids = [0,1]
		player.discard_count = 2
		player.melds = [{"kind":"pung", "tile":"tong4", "formed_at":1}]
	var view = load("res://scripts/ui/table/v2/TableV2.gd").new()
	host.add_child(view)
	host._new_areas = view
	view.round = host.round
	view.table = host
	view.human_seat = 1
	view._sort_started = true
	var controller = load("res://scripts/ui/table/v2/TableV2AnimationController.gd").new(host)
	host._table_animation_controller = controller
	controller.build()
	controller._session = host.round._presentation.session
	controller._dealt = [13,13,13,13]
	view.refresh()
	return host

func cleanup(host):
	host._table_animation_controller.cancel()
	host._table_animation_controller.dispose_pool()
	host.queue_free()
	await process_frame

func rect(node):
	var transform: Transform2D = node.get_transform()
	var points = [transform * Vector2.ZERO, transform * Vector2(node.size.x,0), transform * node.size, transform * Vector2(0,node.size.y)]
	return Rect2(points[0],Vector2.ZERO).expand(points[1]).expand(points[2]).expand(points[3])

func _check_opposite_kongs(view) -> void:
	var obstacles: Array[Rect2] = []
	for seat in 4:
		obstacles.append(G.hand13_rect(seat, 1))
		obstacles.append(G.seat_hud_rect(G.relative_seat(1, seat)))
		var size: Vector2 = G.TILE_BASE if seat in [1, 3] else Vector2(G.TILE_BASE.y, G.TILE_BASE.x)
		for slot in (14 if seat in [1, 3] else 13):
			for row in 2:
				obstacles.append(Rect2(G.wall_block_center(seat, slot, row) - size / 2.0, size))
	for owner in 4:
		var rel := G.relative_seat(1, owner)
		var along: Vector2 = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN][rel]
		var inward: Vector2 = [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT][rel]
		for count in range(1, 5):
			var timeline: Array = []
			for index in count:
				timeline.append({"kind": "kong", "tile": "tong8" if index % 2 == 0 else "wan5",
					"from_seat": posmod(owner + 2, 4), "meld_index": index})
			for index in 24 - count * 4:
				timeline.append({"kind": "charge", "tile": "tiao1", "order": index})
			var layout: Array = view.red_layout(timeline, owner, rel, true)
			var clear := layout.size() == 24
			var occupied: Array[Rect2] = []
			for spec in layout:
				var wide: bool = bool(spec.sideways) != (rel in [1, 3])
				var size := Vector2(G.RED_HEIGHT, G.RED_WIDTH) if wide else Vector2(G.RED_WIDTH, G.RED_HEIGHT)
				var tile := Rect2(Vector2(spec.center) - size / 2.0, size)
				for other in occupied + obstacles:
					if tile.intersects(other.grow(-0.05)):
						clear = false
				occupied.append(tile)
			t.expect(clear, "seat %d: %d opposite kongs in a full belt clear the hand, wall and adjacent tiles" % [owner, count])
			var correct := true
			for index in count:
				var group: Array = layout.filter(func(spec): return spec.meld_index == index)
				var source: Vector2 = group[3].center
				var middle: Vector2 = group[1].center
				correct = correct and group[3].sideways and absf((source - middle).dot(along)) < 0.05 \
					and (source - middle).dot(inward) > G.RED_WIDTH
			t.expect(correct, "seat %d: opposite tile is centered on the inward side of each kong" % owner)

func _meld_clear_in_frame(view, owner: int, layer: Control) -> bool:
	var count := 0
	for tile in layer.get_children():
		if not tile.is_visible_in_tree() or tile.get_meta("v2_seat", -1) != owner or tile.get_meta("meld_index", -1) != 0:
			continue
		count += 1
		var footprint: Rect2 = rect(tile)
		for other_layer in view._render_layers() + [view._deal_layer, view._label_layer, view._action_layer]:
			for other in other_layer.get_children():
				if other != tile and other is Control and other.is_visible_in_tree() and footprint.intersects(rect(other).grow(-0.05)):
					return false
	return count == 4

func _watch_meld_motion(view, owner: int, layer: Control, expect_flight := false, capture := "") -> bool:
	var starts := {}
	for tile in view._deal_layer.get_children():
		starts[tile.get_instance_id()] = tile.position
	var moved := false
	var visible := not expect_flight or starts.size() == 4
	var frames := 0
	var deadline := Time.get_ticks_msec() + 3000
	while view.native_actions_pending() and Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
		for tile in view._deal_layer.get_children():
			if starts.has(tile.get_instance_id()):
				visible = visible and tile.is_visible_in_tree()
				moved = moved or tile.position.distance_to(starts[tile.get_instance_id()]) > 1.0
		if frames == 6 and capture != "" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/meld-motion"))
			root.get_texture().get_image().save_png("res://build/meld-motion/" + capture + ".png")
	return not view.native_actions_pending() and _meld_clear_in_frame(view, owner, layer) \
		and (not expect_flight or (visible and moved))

func _test_exposed_kongs_on_every_seat() -> void:
	for owner in 4:
		for offset in [1, 2, 3]:
			for card in ["wan5", "tong8"]:
				var host = fixture()
				var view = host._new_areas
				var r: RoundState = host.round
				var source := posmod(owner + offset, 4)
				var chicken: bool = card == "tong8"
				var origin: Control = view._red_layer if chicken else view._discard_layer
				var destination: Control = view._red_layer if chicken else view._meld_layer
				for player in r.players:
					player.melds.clear()
					player.discards.clear()
					player.discard_ids.clear()
				r.players[owner].concealed.assign([card, card, card, "wan1", "wan2", "wan3", "wan4",
					"tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4"])
				r.players[source].discards.assign([card])
				r.players[source].discard_ids.assign([7])
				r.wall.set_head(20)
				for i in 54:
					r.wall.draw_head()
				view.refresh()
				var claimed: TileView = origin.get_child(0)
				r.players[source].discards.clear()
				r.players[source].discard_ids.clear()
				r.players[owner].concealed = r.players[owner].concealed.slice(3)
				r.players[owner].melds.append({"kind": "kong", "tile": card, "from_seat": source})
				view.animate_meld({"seat": owner, "source": source, "source_discard_id": 7,
					"kind": "kong", "tile": card, "index": 0, "hand_indices": [0, 1, 2]}, func(): pass)
				var name := "seat %d source %d %s" % [owner, offset, card]
				t.expect(await _watch_meld_motion(view, owner, destination, true, "seat%d-source%d-%s" % [owner, offset, card]), name + ": visible flight moves before an unobstructed landing")
				t.expect(claimed.get_parent() == destination and claimed.get_meta("meld_slot", -1) == (0 if offset == 1 else 3),
					name + ": preserves the source discard in its correct slot")
				var tail := r.wall._tail_index()
				var drawn := r.wall.draw_tail()
				r.players[owner].concealed.append(drawn)
				r.players[owner].just_drew = drawn
				view.animate_draw(owner, drawn, tail, func(): pass)
				t.expect(await _watch_meld_motion(view, owner, destination), name + ": replacement draw does not cover the kong")
				r.phase = RoundState.Phase.SETTLED
				view.refresh()
				t.expect(_meld_clear_in_frame(view, owner, destination), name + ": clear after settlement refresh")
				await cleanup(host)

func _run():
	var host = fixture()
	var view = host._new_areas
	var before = {}
	for layer in view._render_layers():
		for tile in layer.get_children(): before[view._render_key(tile)] = tile.get_instance_id()
	for iteration in 20:
		view.refresh()
	var retained = true
	for layer in view._render_layers():
		for tile in layer.get_children():
			if before.get(view._render_key(tile), -1) != tile.get_instance_id(): retained = false
	t.expect(retained, "unchanged refresh preserves every existing tile identity")
	var opaque = true
	for tile in view._meld_layer.get_children():
		if tile.modulate.a != 1.0 or not tile.scale.is_equal_approx(Vector2(44.0/48,56.0/64)): opaque = false
	t.expect(opaque,"existing melds never restart fade or scale entrance on refresh")
	var red = view._red_layer.get_child(0)
	t.expect(int(red.get_meta("discard_id",-1))==0,"static chicken retains the authoritative discard identity")
	host.round.players[1].ready = true
	view.refresh()
	var ready_badge = false
	for label in view._label_layer.get_children():
		if label is Label and label.text=="听": ready_badge = true
	t.expect(ready_badge,"ready state has an independent visible badge instead of clipped nickname text")
	# Capacity geometry fixture, deliberately independent of physical tile values.
	for seat in 4:
		var player = host.round.players[seat]
		player.melds = [{"kind":"kong","tile":"wan1","formed_at":1},{"kind":"kong","tile":"tong8","formed_at":2},
			{"kind":"kong","tile":"wan6","formed_at":3},{"kind":"kong","tile":"tiao1","formed_at":4}]
		player.discards=["tiao1","tong8","tiao1","tong8","tiao1","tong8","tiao1","tong8"]
		player.discard_ids=range(8)
		player.discard_count=8
	view.refresh()
	for seat in 4:
		var exposed=[]
		for layer in [view._red_layer,view._meld_layer]:
			for tile in layer.get_children():
				if int(tile.get_meta("v2_seat",-1))==seat: exposed.append(tile)
		t.expect(exposed.size()==24,"seat%d: mixed exposed belt keeps all 24 capacity slots" % seat)
		var separate=true
		var hand_clear=true
		var bounds=true
		for i in exposed.size():
			var a=rect(exposed[i])
			if a.intersects(G.hand13_rect(seat,1).grow(-0.1)):hand_clear=false
			if not G.TABLE_BOUNDS.encloses(a):bounds=false
			for j in range(i+1,exposed.size()):
				if a.intersects(rect(exposed[j]).grow(-0.1)):separate=false
		t.expect(separate,"seat%d: chicken and ordinary meld tiles never overlap" % seat)
		t.expect(hand_clear,"seat%d: exposed belt clears fixed full hand area" % seat)
		t.expect(bounds,"seat%d: all exposed tiles remain within table bounds" % seat)
		var rel=G.relative_seat(1,seat)
		var wall_clear=true
		for exposed_tile in exposed:
			for wall_seat in 4:
				for slot in (14 if wall_seat in [1,3] else 13):
					for row in 2:
						var size=G.TILE_BASE if wall_seat in [1,3] else Vector2(G.TILE_BASE.y,G.TILE_BASE.x)
						var wall=Rect2(G.wall_block_center(wall_seat,slot,row)-size/2,size)
						if rect(exposed_tile).intersects(wall.grow(-0.1)): wall_clear=false
		t.expect(wall_clear,"seat%d: exposed belt clears both layers of all four walls" % seat)
	for count in [13,10,7,4,1]:
		var ui := preload("res://scripts/ui/table/TableUiConfig.gd")
		var row_size := Vector2(4 * ui.DISCARD_BUTTON_SIZE.x + 3 * ui.ACTION_SEPARATION, ui.ACTION_BUTTON_SIZE.y)
		var saved_hand: Array = host.round.players[1].concealed.duplicate()
		host.round.players[1].concealed = saved_hand.slice(0, count)
		var action_rect: Rect2 = view.action_bar_rect(row_size)
		var hand_size := G.hand_tile_size(1, 1)
		var right := G.hand_slot_center(1, count - 1, 1, count).x + hand_size.x / 2.0
		t.expect(is_equal_approx(action_rect.end.x, right), "short-hand action row remains right aligned")
		t.expect(action_rect.end.y < G.hand13_rect(1, 1).position.y, "actions remain above the hand")
		host.round.players[1].concealed = saved_hand

		var unobscured=true
		for layer in view._render_layers():
			for tile in layer.get_children():
				if action_rect.intersects(rect(tile).grow(-0.1)):unobscured=false
		t.expect(unobscured,"hand%d: action buttons avoid every public tile, wall and hand" % count)
		t.expect(action_rect.position.y >= G.CENTER.y, "hand%d: action buttons stay on the local side of the table" % count)
	host.round.players[1].melds[0]["from_seat"]=0
	view.refresh()
	var exposed_source=false
	for tile in view._meld_layer.get_children():
		if int(tile.get_meta("v2_seat",-1))==1 and int(tile.get_meta("meld_index",-1))==0 and int(tile.get_meta("meld_slot",-1))==3:
			exposed_source=is_equal_approx(tile.rotation,PI/2)
	t.expect(exposed_source,"exposed kong marks its actual source tile sideways without compressing its group")
	for owner in 4:
		var rel := G.relative_seat(1, owner)
		var right: Vector2 = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN][rel]
		for offset in [1, 3]:
			var source_seat := posmod(owner + offset, 4)
			for value in ["wan5", "tong8"]:
				var layout: Array = view.red_layout([{"kind": "kong", "tile": value, "from_seat": source_seat}], owner, rel, true)
				var source_tiles := layout.filter(func(spec): return spec.sideways)
				var left: Vector2 = layout.front().center
				var end: Vector2 = layout.back().center
				var expected := left if offset == 1 else end
				t.expect(source_tiles.size() == 1 and source_tiles[0].center == expected and (end - left).dot(right) > 0,
					"seat %d: %s source %d is sideways at the correct owner-relative end" % [owner, value, offset])
	host.round.players[1].melds[0]["kind"]="add_kong"
	view.refresh()
	var added_upright=false
	for tile in view._meld_layer.get_children():
		if int(tile.get_meta("v2_seat",-1))==1 and int(tile.get_meta("meld_index",-1))==0 and int(tile.get_meta("meld_slot",-1))==3:
			added_upright=is_zero_approx(tile.rotation)
	t.expect(added_upright,"added kong keeps all four tiles upright as specified")
	_check_opposite_kongs(view)
	await cleanup(host)
	host=fixture()
	view=host._new_areas
	for player in host.round.players: player.discards=[];player.discard_ids=[];player.melds=[]
	host.round.phase = RoundState.Phase.DEALING
	view._sort_started = false
	host._table_animation_controller._dealt=[13,4,13,13]
	host._table_animation_controller._dealt_cards[1]=["wan2","wan4","wan1","wan3"]
	view.refresh()
	var dealt=[]
	for tile in view.hand_boxes[1].get_children():dealt.append(tile.tile)
	t.expect(dealt==["wan2","wan4","wan1","wan3"],"four-tile landing preserves the exact lower/upper wall flight order")
	var source_indices=[]
	for tile in view.hand_boxes[1].get_children():source_indices.append(tile.get_meta("concealed_index"))
	t.expect(source_indices==[1,3,0,2],"deal display order preserves real authority indices")
	host._table_animation_controller._dealt_cards[1] = ["tong9", "tong9", "tong9", "tong9"]
	view.refresh()
	await process_frame
	view.refresh()
	t.expect(view.hand_boxes[1].get_child_count() == 4, "unmatched transient deal tiles keep distinct visual nodes")
	t.expect(view.hand_boxes[1].get_children().all(func(tile): return not tile.interactive), "unmatched transient tiles cannot be played")
	host._table_animation_controller.cancel()
	t.expect(host._table_animation_controller.dealt_cards(1).is_empty(),"next round cannot reuse the previous round's dealt-card order")
	await cleanup(host)
	await _test_exposed_kongs_on_every_seat()
	await H.quit_cleanly(self,t.finish("table_v2_visual_continuity"))
