extends "res://tests/settlement_animation_flow.gd"
## Real settled rounds, fixed seed, and the live tabletop controls on both renderers.

func _score_fixture(kind: String) -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	for seat in 4: r.players[seat].concealed = WAIT.duplicate()
	r.players[0].concealed = ["tong4", "tong5", "tong6", "wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "wan6", "wan7", "wan8", "wan9", "wan9"]
	r.players[0].just_drew = "wan9"
	r.players[0].ready = true
	r.round_meta.winner = 0
	r.round_meta.winners = [0]
	r.round_meta.self_draw = false
	r.round_meta.discard_seat = 2
	r.round_meta.win_tile = "wan9"
	var flip := "tong5"
	if kind in ["mixed", "mixed_double", "ordinary"]:
		r.players[0].concealed = WIN.duplicate()
		r.players[0].discards = ["tiao1", "tiao1", "tong8"]
		r.players[0].discard_ids = [0, 1, 2]
		r.players[0].discard_count = 3
		r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
		flip = "wan8" if kind == "ordinary" else "tiao1"
		if kind == "mixed_double": r.round_meta.chicken_multiplier = 2
	if kind == "melds":
		r.players[0].ready = false
		r.players[0].concealed = ["tong4", "tong5", "tong6", "wan9", "wan9"]
		r.players[0].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 1},
			{"kind": "kong", "tile": "tong8", "concealed": true, "from_seat": 0},
			{"kind": "kong", "tile": "wan2", "from_seat": 2}]
		flip = "tong8"
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.wall._ring[0] = flip
	r._finish()
	t.expect(_sum(r.last_result.scores) == 800.0, kind + ": settlement conserves 800")
	return r

func _group(area: String, seat: int = 0, index: int = -1) -> Dictionary:
	for group in table._settlement_animation_controller.score_annotations.groups:
		if group.area == area and int(group.seat) == seat and (index < 0 or int(group.meld_index) == index): return group
	return {}

func _capture_score(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://build/ui_review/settlement_scores"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	t.expect(root.get_texture().get_image().save_png(folder + "/" + name + ".png") == OK, "save " + name)

func _check_annotations() -> void:
	var c = table._settlement_animation_controller
	var a = c.score_annotations
	var occupied: Array[Rect2] = []
	for label in a.labels.values():
		t.expect(label.is_visible_in_tree() and not label.text.is_empty(), "annotation has visible text")
		t.expect(Rect2(Vector2.ZERO, UI.DESIGN_SIZE).encloses(label.get_rect()), "annotation stays within resized design canvas")
		for previous in occupied: t.expect(not label.get_rect().intersects(previous), "simultaneous group annotations do not overlap")
		occupied.append(label.get_rect())
		for identity in c.identity_labels.values(): t.expect(not label.get_rect().intersects(identity.get_rect()), "group amount leaves identity readable")

func _test_stage_labels() -> void:
	for kind in ["flip_run", "mixed", "mixed_double", "ordinary", "melds"]:
		var r := _score_fixture(kind)
		var before := _snapshot(r)
		var tween := _prepare_timed(r)
		if tween == null: return
		var c = table._settlement_animation_controller
		var a = c.score_annotations
		# Advance through the actual flip before manually isolating each stage.
		tween.custom_step(0.7 * root.get_node("GameConfig").settlement_duration(1.0))
		for key in ["flip", "chicken", "kong", "other"]:
			c._begin_stage(key)
			t.expect(a.hit_buttons.is_empty(), "inspection is disabled during playback")
			_check_annotations()
			if kind == "flip_run" and key == "flip":
				var group := _group("hand")
				t.expect(not group.is_empty() and group.stages.flip.amount == 3.0, "456 tong highlighted group reads exactly +3 from flip items")
				if not group.is_empty(): t.expect(a.labels.has(group.id) and a.labels[group.id].text.contains("3"), "flip group amount is displayed above the cards")
				await _capture_score("01_flip_group")
			if kind in ["mixed", "ordinary", "mixed_double"] and key == ("chicken" if kind == "ordinary" else "flip"):
				var group := _group("chicken")
				var expected := 24.0 if kind == "mixed_double" else (6.0 if kind == "ordinary" else 12.0)
				t.expect(not group.is_empty() and group.stages[key].amount == expected, "charge and ordinary chicken group uses ledger rates, including doubled round")
				if not group.is_empty():
					t.expect(a.labels[group.id].text == ("冲锋幺鸡16分 幺鸡8分" if kind == "mixed_double" else ("冲锋幺鸡4分 幺鸡2分" if kind == "ordinary" else "冲锋幺鸡8分 幺鸡4分")), "mixed chicken names charge and ordinary amounts separately")
				if kind == "mixed": await _capture_score("02_gold_mixed_stage")
			if kind == "melds" and key == "kong":
				var dark := _group("meld", 0, 1)
				var exposed := _group("meld", 0, 2)
				t.expect(not dark.is_empty() and dark.stages.kong.amount == 12.0, "concealed kong stage only shows three actual base payments")
				t.expect(not exposed.is_empty() and not exposed.stages.has("kong"), "winning round exposed kong stays outside base-kong stage")
				await _capture_score("03_kong_stage")
			c._end_stage()
			t.expect(a.labels.is_empty(), "stage completion clears temporary amounts")
		c.skip()
		t.expect(a.completed and a.labels.is_empty() and not a.hit_buttons.is_empty(), "skip enables inspection with no stage labels left")
		t.expect(c.current_pairs == r.last_result.pairwise and _snapshot(r) == before, "group labels never change ledger or final relative payments")

func _test_clicks() -> void:
	for kind in ["mixed", "ordinary", "melds"]:
		var r := _score_fixture(kind)
		var before := _snapshot(r)
		_bind(r)
		var c = table._settlement_animation_controller
		var a = c.score_annotations
		var group := _group("meld", 0, 2) if kind == "melds" else _group("chicken")
		if not t.expect(not group.is_empty(), "scoring group exists for click"): continue
		var tile = a._tiles_for(group)[0]
		var button: Button = a.hit_buttons[str(tile.get_instance_id())]
		button.pressed.emit()
		t.expect(a.selected_id == group.id and a.labels.has(group.id), "click displays this group detail")
		if kind == "melds":
			t.expect(a.labels[group.id].text.contains("对家") and a.labels[group.id].text.contains("4"), "exposed kong explicitly names the owner's opposite payer and four points")
			await _capture_score("05_exposed_kong_click")
		else:
			t.expect(a.labels[group.id].text.contains("8" if kind == "mixed" else "4"), "chicken click retains charge rate")
			await _capture_score("04_" + kind + "_click")
		_check_annotations()
		for dimensions in [Vector2i(960, 540), Vector2i(1080, 1920), Vector2i(1920, 1080)]:
			root.size = dimensions
			await process_frame
			await process_frame
			c.refresh_layout()
			_check_annotations()
			t.expect(a.labels.has(group.id), "resize retains selected group")
		button.pressed.emit()
		t.expect(a.selected_id == "" and a.labels.is_empty(), "second click dismisses without discarding")
		if kind == "mixed" and DisplayServer.get_name() != "headless":
			await _pointer_click(button, false)
			t.expect(a.selected_id == group.id, "real viewport mouse click opens the tile group")
			await _pointer_click(button, true)
			t.expect(a.selected_id == "", "emulated touch tap closes the same group once")
		t.expect(not a.hit_buttons.has("flip"), "flip tile no longer opens text")
		await _pointer_at(table.surface.get_global_transform_with_canvas() * Vector2(1140, 260), false)
		t.expect(a.selected_id == "" and a.labels.is_empty(), "background click clears detail")
		t.expect(_snapshot(r) == before and _sum(r.last_result.scores) == 800, "every click and resize is read-only")
		c.reset()
		t.expect(a.groups.is_empty() and a.labels.is_empty() and a.hit_buttons.is_empty(), "reset removes group overlays and touch targets")

func _pointer_click(button: Button, touch: bool) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size / 2.0)
	await _pointer_at(point, touch)

func _pointer_at(point: Vector2, touch: bool) -> void:
	for pressed in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.index = 0
			event.position = point
			event.pressed = pressed
			Input.parse_input_event(event)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			event.position = point
			event.global_position = point
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func _test_hidden_draw_kong() -> void:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	for seat in 4: r.players[seat].concealed = WAIT.duplicate()
	r.players[1].concealed = ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
	r.players[1].melds = [{"kind": "kong", "tile": "tong5", "concealed": true, "from_seat": 1, "after_discard": 0}]
	r.players[1].discard_count = 1
	r.players[3].concealed = ["wan1", "tong4", "tiao7"]
	r._penzu()
	t.expect(_sum(r.last_result.scores) == 800, "hidden-kong draw conserves scores")
	var before := _snapshot(r)
	_bind(r)
	var a = table._settlement_animation_controller.score_annotations
	var group := _group("meld", 1, 0)
	a.select_group(group.id)
	for tile in a._tiles_for(group): t.expect(not tile.face_up, "unrevealed draw kong stays face down")
	t.expect(a.labels[group.id].text.contains("未翻开") and not a.labels[group.id].text.contains("5筒"), "draw inspection cannot disclose hidden kong value")
	t.expect(a.labels[group.id].text.contains("4"), "hidden kong still exposes its recorded base payment")
	t.expect(_snapshot(r) == before, "hidden kong explanation is read-only")

func _kong_caption_fixture(is_draw: bool, called_owner: bool, multiplier: int, gold: String) -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261021)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	for seat in 4: r.players[seat].concealed = WAIT.duplicate()
	r.players[1].concealed = ["wan1", "tong4", "tiao7"]
	var owner := 2 if called_owner else 1
	r.players[owner].concealed = (["wan1", "wan2", "wan3", "tong1", "tong2", "tong3", "wan9"] if called_owner
		else ["wan1", "wan3", "wan5", "wan7", "tong1", "tong4", "tiao7"])
	for tile in ["tiao1", "tong8"]:
		r.players[owner].melds.append({"kind": "kong", "tile": tile, "from_seat": owner - 1})
	r.round_meta.chicken_multiplier = multiplier
	if is_draw:
		r._penzu()
	else:
		r.players[0].concealed = WIN.duplicate()
		r.players[0].just_drew = "wan9"
		r.round_meta.winner = 0
		r.round_meta.winners = [0]
		r.round_meta.self_draw = false
		r.round_meta.discard_seat = 3
		r.round_meta.win_tile = "wan9"
		r.wall = WallRing.new(TileSetFactory.create_deck())
		r.wall.set_head(0)
		r.wall._ring[0] = gold
		r._finish()
	return r

func _test_requested_kong_clicks() -> void:
	for is_draw in [false, true]:
		for called_owner in [false, true]:
			for gold in ["tiao1", "tong8"]:
				var r := _kong_caption_fixture(is_draw, called_owner, 1, gold)
				var before := _snapshot(r)
				var owner := 2 if called_owner else 1
				var expected: Array = []
				_bind(r)
				var a = table._settlement_animation_controller.score_annotations
				for index in 2:
					var group := _group("meld", owner, index)
					var tile := "tiao1" if index == 0 else "tong8"
					var name := "幺鸡" if index == 0 else "八筒"
					var unit := 16 if not is_draw and tile == gold else 8
					var chicken := name + str(unit if called_owner else -unit) + "分"
					var base := "杠上家" + name + ("4分" if called_owner else "-4分")
					var button: Button = a.hit_buttons[str(a._tiles_for(group)[0].get_instance_id())]
					button.pressed.emit()
					t.expect(a.labels[group.id].text.contains(chicken), "live click shows the requested signed chicken kong tile rate")
					t.expect(a.labels[group.id].text.contains(base), "live click keeps only the exposed kong's source direction")
					t.expect(not a.labels[group.id].text.contains("向") and not a.labels[group.id].text.contains("补付"), "live kong click omits payment flow wording")
					expected.append(group.detail)
					if is_draw and gold == "tiao1":
						await _capture_score("08_draw_kong_%s_%d" % ["called" if called_owner else "uncalled", index])
				var client := RoundState.new()
				client.apply_sync(r.serialize_for_seat(3))
				_bind(client, 3)
				for index in 2:
					t.expect(_group("meld", owner, index).detail == expected[index], "reconnected client keeps the same short kong captions")
				t.expect(_snapshot(r) == before and _sum(r.last_result.scores) == 800, "requested kong caption clicks preserve scores and settlement")
	var pung_round := _score_fixture("melds")
	_bind(pung_round)
	var pung := _group("meld", 0, 0)
	var annotations = table._settlement_animation_controller.score_annotations
	annotations.select_group(pung.id)
	t.expect(annotations.labels[pung.id].text == "碰幺鸡6分", "called chicken pung click shows 碰幺鸡6分")

func _test_requested_draw_package_clicks() -> void:
	var r := RoundState.new()
	r.set_rng_seed(20261021)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	for seat in 4: r.players[seat].concealed = WAIT.duplicate()
	r.players[1].concealed = ["wan1", "tong4", "tiao7"]
	r.players[1].discards = ["tiao1", "tong8"]
	r.players[1].discard_ids = [0, 1]
	r.players[1].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 0}]
	r.players[0].discards = ["tong8"]
	r.players[0].discard_ids = [0]
	r.round_meta.chicken_multiplier = 2
	r.round_meta.charge_chickens = {"tiao1": {"owner": 1, "location": "discard", "discard_id": 0},
		"tong8": {"owner": 1, "location": "discard", "discard_id": 1}}
	r._penzu()
	var before := _snapshot(r)
	_bind(r)
	var a = table._settlement_animation_controller.score_annotations
	for group in a.groups:
		if int(group.seat) != 1: continue
		a.select_group(group.id)
		var expected := "碰幺鸡-12分" if group.area == "meld" else ("冲锋幺鸡-8分" if group.tiles[0] == "tiao1" else "冲锋八筒-8分")
		if not t.expect(a.labels.has(group.id), "live draw package has a visible debt label for " + group.id): continue
		t.expect(a.labels[group.id].text == expected, "live draw package caption: expected " + expected + ", got " + a.labels[group.id].text)
		await _capture_score("09_draw_package_" + str(group.area) + "_" + str(group.tiles[0]))
	t.expect(_snapshot(r) == before and _sum(r.last_result.scores) == 800, "draw package click leaves every real payment unchanged")

func _test_reconnect_details() -> void:
	var host := _score_fixture("melds")
	for human in 4:
		var client := RoundState.new()
		client.set_rng_seed(20261018)
		client.apply_sync(host.serialize_for_seat(human))
		var before := _snapshot(client)
		_bind(client, human)
		var a = table._settlement_animation_controller.score_annotations
		t.expect(a.completed and not a.hit_buttons.is_empty(), "settled reconnect immediately enables read-only inspection")
		var group := _group("meld", 0, 2)
		a.select_group(group.id)
		t.expect(a.labels[group.id].text.contains("对家"), "exposed payer remains relative to meld owner across viewers")
		_check_annotations()
		t.expect(_snapshot(client) == before, "reconnect inspection never modifies client snapshot")
	for kind in ["draw", "all_called_draw", "rob_kong", "zero", "negative"]:
		var r := _fixture(kind)
		var before := _snapshot(r)
		_bind(r)
		var a = table._settlement_animation_controller.score_annotations
		if kind == "all_called_draw": t.expect(a.groups.is_empty() and a.hit_buttons.is_empty(), "all-called draw creates no score inspection")
		if kind == "draw":
			for group in a.groups: t.expect(group.area not in ["hand", "draw"] and not group.stages.has("flip"), "draw does not expose hand score or flip detail")
		for group in a.groups:
			a.select_group(group.id)
			_check_annotations()
			if kind == "rob_kong" and int(group.seat) == 1:
				for tile in a._tiles_for(group): t.expect(not tile.score_highlight, "burned player never receives positive highlight")
		t.expect(_snapshot(r) == before, kind + ": inspection is read-only")

func _run() -> void:
	var master := AudioServer.get_bus_index("Master")
	var muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await _test_stage_labels()
	await _test_clicks()
	await _test_requested_kong_clicks()
	await _test_requested_draw_package_clicks()
	_test_reconnect_details()
	_test_hidden_draw_kong()
	_bind(_fixture("ready_ron"))
	await _capture_score("07_ready_identity")
	table.free()
	await process_frame
	AudioServer.set_bus_mute(master, muted)
	await H.quit_cleanly(self, t.finish("settlement_score_inspection"))
