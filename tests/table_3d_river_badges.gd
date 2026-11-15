extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()
const OUT := "res://build/realtime-3d/row-spacing-review"
var layouts := 0
var badge_combinations := 0

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for viewer in 4:
		for seat in 4:
			var rel := G.relative_seat(viewer, seat)
			var columns := 8 if rel in [1, 3] else 10
			var capacity := 32 if rel in [1, 3] else 30
			t.expect(G.river_capacity(rel) == capacity, "river capacity matches the requested row limit")
			for count in range(1, capacity + 1):
				for row in ceili(float(count) / columns):
					var used := mini(columns, count - row * columns)
					var a := G.ordinary_slot_center(seat, row * columns, viewer, count)
					var b := G.ordinary_slot_center(seat, row * columns + used - 1, viewer, count)
					t.expect(is_equal_approx(absf(b.y - a.y) if rel in [1, 3] else absf(b.x - a.x), (used - 1) * 68.8), "each row fills before wrapping, including every partial row")
	root.get_node("UpdateManager").auto_check = false
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	for pixels in [Vector2(1600, 1000), Vector2(1920, 1080), Vector2(2400, 1080)]:
		view.scale = pixels / G.DESIGN_SIZE
		for viewer in 4:
			for settled in [false, true]:
				for meld_count in 5:
					for chickens in [0, 2, 8]:
						var round := fixture(viewer, meld_count, chickens)
						round.phase = RoundState.Phase.SETTLED if settled else RoundState.Phase.PLAYING
						view.set_round(round, viewer)
						view._table_3d._own_hand_pitch = 0.0 if settled else deg_to_rad(63)
						view._table_3d.sync_tiles()
						await process_frame
						view._table_3d.sync_tiles()
						check_rivers(view)
						check_badges(view)
			print("completed pixels=%s viewer=%d layouts=%d combinations=%d" % [pixels, viewer, layouts, badge_combinations])
			for count in range(33):
				for head in ([0, 28, 54, 82] if count <= 14 else [0]):
					var round := fixture(viewer, 0, 0)
					for player in round.players:
						var used := mini(count, G.river_capacity(G.relative_seat(viewer, player.seat)))
						player.discards.resize(used)
						player.discard_ids.resize(used)
						player.discard_count = used
					round.wall = WallRing.new(TileSetFactory.create_deck())
					round.wall.set_head(head)
					for i in mini(108, 52 + 4 * count): round.wall.draw_head()
					view.set_round(round, viewer)
					view._table_3d.sync_tiles()
					check_rivers(view)
			var moving := fixture(viewer, 4, 8)
			view.set_round(moving, viewer)
			for degrees in range(0, 64, 9):
				view._table_3d._own_hand_pitch = deg_to_rad(degrees)
				view._table_3d.sync_tiles()
				check_badges(view)
		var pending := fixture(0, 3, 2)
		view.set_round(pending, 0)
		var exposed: TileView = view._red_layer.get_children().filter(func(tile): return int(tile.get_meta("v2_seat")) == 0)[0]
		exposed.position = Vector2(1050, 900)
		view._table_3d.sync_tiles()
		var live_position: Vector3 = view._table_3d.tile_nodes[exposed.get_instance_id()].position
		pending.phase = RoundState.Phase.SETTLED
		view._table_3d.sync_tiles()
		t.expect(view._table_3d.tile_nodes[exposed.get_instance_id()].position.is_equal_approx(live_position), "exposed tiles stay clear of the river while settlement is pending")
		view._settlement_started = true
		view._discard_layer.hide()
		view._table_3d.sync_tiles()
		t.expect(not view._table_3d.tile_nodes[exposed.get_instance_id()].position.is_equal_approx(live_position), "exposed tiles move when settlement actually hides the river, even with unchanged round phase")
		view._settlement_started = false
		view._discard_layer.show()
	DirAccess.make_dir_recursive_absolute(OUT)
	var result := FileAccess.open(OUT.path_join("matrix-result.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify({"checks": t.checks, "failures": t.failures, "layouts": layouts, "badge_combinations": badge_combinations,
		"viewers": 4, "aspect_ratios": 3, "dealer_positions": 4, "ready_masks": 16, "meld_counts": [0, 1, 2, 3, 4], "chicken_counts": [0, 2, 8],
		"ordinary_counts": "0..32, capped at 30/32", "remaining_wall_starts": [0, 28, 54, 82], "hand_pitch_degrees": "0..63, step 9"}, "  "))
	result.close()
	view.queue_free()
	await process_frame
	print("rendered layouts=%d badge combinations=%d" % [layouts, badge_combinations])
	await H.quit_cleanly(self, t.finish("table_3d_river_badges"))

func fixture(viewer: int, meld_count: int, chickens: int) -> RoundState:
	var round := RoundState.new()
	round.build_players(viewer)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	round.wall = WallRing.new(TileSetFactory.create_deck())
	# Maximum rivers stress every screen slot; the wall is exhausted at this stage.
	for i in 108: round.wall.draw_head()
	for player in round.players:
		var hand := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong1", "tong2", "tong3", "tiao2"]
		player.concealed = hand.slice(0, 13 - meld_count * 3)
		player.concealed.append("tong9")
		player.just_drew = "tong9"
		for i in meld_count:
			player.melds.append({"kind": "pung" if i == 0 else "kong", "tile": ["wan6", "tiao1", "tong8", "wan4"][i],
				"from_seat": player.seat if i == 2 else posmod(player.seat + i + 1, 4),
				"formed_at": i + 1, "concealed": i == 2, "revealed": true, "added": i == 3})
		var cap := G.river_capacity(G.relative_seat(viewer, player.seat))
		for i in cap + chickens:
			player.discards.append("wan2" if i < cap else ("tiao1" if i % 2 == 0 else "tong8"))
			player.discard_ids.append(i)
		player.discard_count = player.discards.size()
	return round

func sources(view) -> Array:
	var out := []
	for layer in view._render_layers():
		for tile in layer.get_children():
			if tile is TileView and tile.is_visible_in_tree(): out.append(tile)
	return out

func check_rivers(view) -> void:
	var renderer = view._table_3d
	var counts := [0, 0, 0, 0]
	var rivers := [[], [], [], []]
	var failures := []
	for tile in view._discard_layer.get_children():
		var seat := int(tile.get_meta("v2_seat"))
		counts[seat] += 1
		rivers[seat].append(tile)
		t.expect(Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(renderer.project_tile(tile)), "every river tile stays on screen")
		var mesh: MeshInstance3D = renderer.tile_nodes[tile.get_instance_id()]
		for offset in [Vector2.ZERO, Vector2(-0.29, -0.40), Vector2(0.29, -0.40), Vector2(-0.29, 0.40), Vector2(0.29, 0.40)]:
			var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(offset.x, 0.31, offset.y)) / Vector2(renderer.viewport.size) * renderer.size
			var hit: TileView = renderer.pick_tile(point, false)
			if hit != tile:
				failures.append("seat%d tile%d count%d wall-left%d blocked by %s seat%s wall-index%s" % [seat, tile.get_meta("discard_id"), view._ordinary_count(seat), view.round.wall.remaining,
					hit.get_meta("new_kind") if hit else "nothing", hit.get_meta("v2_seat", -1) if hit else -1, hit.get_meta("wall_ring_index", -1) if hit else -1])
				break
	for seat in 4:
		var expected := mini(G.river_capacity(G.relative_seat(view.human_seat, seat)), view._ordinary_count(seat))
		t.expect(counts[seat] == expected, "every ordinary discard up to the row limit is displayed")
		if G.relative_seat(view.human_seat, seat) in [0, 2]:
			rivers[seat].sort_custom(func(a, b): return int(a.get_meta("discard_id")) < int(b.get_meta("discard_id")))
			for i in range(10, rivers[seat].size()):
				var a: Rect2 = renderer.project_tile(rivers[seat][i - 10])
				var b: Rect2 = renderer.project_tile(rivers[seat][i])
				var gap := b.position.y - a.end.y if seat == view.human_seat else a.position.y - b.end.y
				t.expect(gap <= 0.01, "north/south rows meet in the rendered view without a strip of table between them")
				var first: MeshInstance3D = renderer.tile_nodes[rivers[seat][i - 10].get_instance_id()]
				var next: MeshInstance3D = renderer.tile_nodes[rivers[seat][i].get_instance_id()]
				t.expect(is_equal_approx(absf(first.position.z - next.position.z), first.basis.get_scale().x * 1.34), "north/south row edges touch in world space")
				if (i / 10 + 1) * 10 <= counts[seat]:
					var overlap := a.intersection(b)
					var nearer: TileView = rivers[seat][i] if b.get_center().y > a.get_center().y else rivers[seat][i - 10]
					t.expect(overlap.has_area() and renderer.pick_tile(overlap.get_center(), false) == nearer, "the screen-lower row occludes the screen-upper row's base")
	t.expect(failures.is_empty(), "all full-river printed faces stay visible (pixels%s viewer%d phase%d melds%d chickens%d): %s" % [renderer.viewport.size, view.human_seat, view.round.phase, view.round.players[view.human_seat].melds.size(), view.round.players[view.human_seat].discards.filter(func(card): return Tiles.is_chicken(card)).size(), failures])
	layouts += 1

func check_badges(view) -> void:
	var obstacles := []
	for tile in sources(view): obstacles.append(view._table_3d.project_tile(tile))
	obstacles.append(view.action_bar_rect(Vector2(750, 112)))
	for button in [view._sort_button, view._restore_button, view._previous_sort_button]:
		if button.visible: obstacles.append(button.get_rect())
	for dealer in 4:
		view.round.dealer_seat = dealer
		for mask in 16:
			for seat in 4: view.round.players[seat].ready = bool(mask & (1 << seat))
			view._layout_meld_badges()
			var badges := []
			var clear := true
			var why := ""
			for seat in 4:
				t.expect(view._dealer_meld_badges[seat].visible == (seat == dealer), "only the dealer has a dealer badge")
				t.expect(view._ready_meld_badges[seat].visible == bool(mask & (1 << seat)), "every declared-ready player has a ready badge")
				for badge in [view._dealer_meld_badges[seat], view._ready_meld_badges[seat]]:
					if not badge.visible: continue
					t.expect(badge.size == Vector2.ONE * (40.0 if seat == view.human_seat else 56.0), "badge width and height both follow the seat after deferred font layout")
					var rect: Rect2 = badge.get_rect()
					clear = clear and Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(rect)
					for other in badges + obstacles:
						if rect.intersects(other):
							clear = false
							why = "%s %s overlaps %s" % [badge.name, rect, other]
					for other_seat in 4:
						if rect.intersects(view._seat_hud_rect(other_seat)):
							clear = false
							why = "%s %s overlaps seat%d information %s" % [badge.name, rect, other_seat, view._seat_hud_rect(other_seat)]
					badges.append(rect)
				t.expect(clear, "dealer%d ready-mask%d: badges avoid every tile, player information, screen edge and each other: %s" % [dealer, mask, why])
			badge_combinations += 1
