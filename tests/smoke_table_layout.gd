extends SceneTree

var table
var rendering := false
var failed := false

func _initialize() -> void:
	rendering = DisplayServer.get_name() != "headless"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 1000)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_check_layout()
	_test_ai_speed()
	await _test_input()
	_test_ready()
	_test_kong()
	_test_kong_choices()
	_test_sync()
	_test_network_reset()
	_test_charge_chickens()
	await _test_anchored_rows()
	_build_midgame()
	for dimensions in [Vector2i(1440, 1520), Vector2i(1440, 1000), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1080, 1080), Vector2i(1080, 1920)]:
		root.size = dimensions
		await process_frame
		await process_frame
		_check_layout()
		if rendering:
			await RenderingServer.frame_post_draw
			var snapshot := root.get_texture().get_image()
			var path := "res://docs/table_%dx%d.png" % [dimensions.x, dimensions.y]
			_expect(snapshot.save_png(path) == OK)
			print("[layout] screenshot ", path)
	await _test_dense_discards()
	await _test_meld_markers()
	_test_result()
	await process_frame
	await process_frame
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/table_result.png") == OK)
	await _test_draw_results()
	_test_next_round()
	if not failed:
		print("[smoke_table_layout] selection, ready, kong, sync, layout, settlement passed")
	quit(1 if failed else 0)

func _new_fixture() -> void:
	if table.round != null:
		table.round.phase = "idle"
	table._clear_actions()
	table._response_disc = ""
	table._declaring_ready = false
	table._result_shown = false
	table.result_layer.hide()
	table.round = RoundState.new()
	table.round.build_players(table.human_seat)
	table.round.controllers = [null, null, null, null]
	table.round.wall = WallRing.new(TileSetFactory.create_deck())
	table.round.wall.set_head(0)
	table.round.current_turn = table.human_seat
	table.round.phase = "playing"
	table.round.awaiting = true
	table.round.require_turn.connect(table._on_require_turn)
	table.round.require_response.connect(table._on_require_response)
	table.round.state_update.connect(table._refresh)
	table.round.round_finished.connect(table._on_round_finished)

func _test_ai_speed() -> void:
	for speed in ["fast", "medium", "slow"]:
		table._speed_buttons[speed].pressed.emit()
		_expect(root.get_node("GameConfig").ai_speed == speed, "Speed buttons must select the requested speed")
		var expected := float({"fast": 1, "medium": 2, "slow": 3}[speed]) if rendering else 0.0
		_expect(table.round.ai_delay_seconds == expected, "AI speed must use the specified one/two/three second delay")
	table._speed_buttons.fast.pressed.emit()

func _test_input() -> void:
	var drawn: TileView = table.draw_box[0].get_child(0)
	var card: String = drawn.tile
	var before: Array = table.round.players[0].concealed.duplicate()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = drawn.get_global_rect().get_center()
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	_expect(drawn.selected)
	_expect(drawn.position.y < drawn._table_position.y)
	_expect(table.round.players[0].concealed == before, "Selecting must not discard")
	var button: Button = table.action_bar.get_child(table.action_bar.get_child_count() - 1)
	_expect(not button.disabled)
	var confirm := InputEventMouseButton.new()
	confirm.button_index = MOUSE_BUTTON_LEFT
	confirm.position = button.get_global_rect().get_center()
	confirm.pressed = true
	Input.parse_input_event(confirm)
	await process_frame
	confirm.pressed = false
	Input.parse_input_event(confirm)
	await process_frame
	_expect(table.round.players[0].discard_count == 1, "Confirm must record a discard even if the tile is then claimed")

func _test_ready() -> void:
	_new_fixture()
	var player: PlayerState = table.round.players[0]
	player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan9", "tong9"]
	player.just_drew = "tong9"
	table._on_require_turn(0)
	table._refresh()
	_expect(table._ready_discards.has("tong9"))
	table._toggle_ready()
	_expect(table.draw_box[0].get_child(0).interactive)
	_expect(not table.hand_box[0].get_child(0).interactive)
	table._submit_discard("tong9")
	_expect(player.ready)
	_expect(player.discards == ["tong9"])
	player.just_drew = "tiao9"
	player.concealed.append("tiao9")
	table.round.current_turn = 0
	table._on_require_turn(0)
	table._refresh()
	_expect(table.draw_box[0].get_child(0).interactive)
	for tile in table.hand_box[0].get_children():
		_expect(not tile.interactive)

func _test_kong() -> void:
	_new_fixture()
	var player: PlayerState = table.round.players[0]
	player.concealed = ["wan1", "wan1", "wan1", "wan1", "wan4", "wan5", "tiao2", "tiao4", "tiao6", "tong2", "tong4", "tong6", "tong8", "wan9"]
	player.just_drew = "wan9"
	table._on_require_turn(0)
	table._refresh()
	table._commit_turn({"kong_declares": ["wan1"], "discard": "wan9"})
	_expect(player.melds.size() == 1)
	_expect(table.meld_box[0].get_child_count() == 4)
	_expect(player.discards.is_empty(), "Kong must wait for another discard choice after replacement draw")
	_expect(table.round.awaiting and table._selecting)

func _test_sync() -> void:
	table.round._awaiting_response = {"seat": 2, "disc_seat": 1, "tile": "tong6"}
	table.round.players[0].first_turn_done = true
	table.round.players[0].discards = ["tiao1"]
	table.round.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	table.round._refresh_charge_flags()
	var client := RoundState.new()
	client.apply_sync(table.round.serialize())
	_expect(client.players[0].just_drew == table.round.players[0].just_drew)
	_expect(client.players[0].is_dealer)
	_expect(client.players[0].first_turn_done and client.players[0].charge_chicken)
	_expect(client._awaiting_response.seat == 2)
	for seat in 4:
		var count := 0
		for stack in client.wall_stacks[seat]:
			count += stack
		_expect(count == client.wall_remain[seat])

func _test_kong_choices() -> void:
	_new_fixture()
	var player: PlayerState = table.round.players[0]
	player.concealed = ["wan1", "wan1", "wan1", "wan1", "wan4", "wan4", "wan4", "wan4", "tiao2", "tiao3", "tiao4", "tong6", "tong7", "tong8"]
	player.just_drew = "tong8"
	table._on_require_turn(0)
	table._refresh()
	var choices: PopupMenu
	for button in table.action_bar.get_children():
		if button.text == "暗杠":
			choices = button.get_node_or_null("TileChoices")
	_expect(choices != null and choices.item_count == 2, "Both concealed kongs must be selectable")
	if choices != null:
		choices.id_pressed.emit(1)
		_expect(player.melds.size() == 1 and player.melds[0].tile == "wan4", "Second kong choice must be honored")

func _test_network_reset() -> void:
	var network := root.get_node("Network")
	network.reset()
	_expect(network.net_node.get_parent() == network)
	_expect(network.net_node.get_path() == NodePath("/root/Network/Net"))
	var active_round: RoundState = table.round
	table.round = RoundState.new()
	table._refresh()
	_expect(table._exposed_layouts.is_empty(), "Waiting for a client sync must not index missing player data")
	table.round = active_round
	table._refresh()

func _build_midgame() -> void:
	_new_fixture()
	var r: RoundState = table.round
	r.wall.set_head(WallRing.compute_break(4))
	for index in 64:
		r.wall.draw_head()
	for seat in 4:
		var player: PlayerState = r.players[seat]
		player.concealed = ["wan2", "wan3", "wan4", "wan7", "wan8", "tiao1", "tiao4", "tiao5", "tiao6", "tong2", "tong3", "tong5", "tong8"]
		player.discards = ["tong1", "tiao7", "wan6", "tong9", "tiao3", "wan5", "tong4", "wan1", "tiao8", "tiao1", "tong8"]
		if seat == 0:
			player.melds = [{"kind": "pung", "tile": "wan8", "robbed": false, "from_seat": 3}]
			player.concealed = ["wan2", "wan3", "wan4", "tiao1", "tiao4", "tiao5", "tiao6", "tong2", "tong3", "tong8", "tong9"]
			player.just_drew = "tong9"
		elif seat == 1:
			player.melds = [{"kind": "kong", "tile": "tiao9", "robbed": false, "concealed": true}]
			player.concealed.resize(10)
		elif seat == 2:
			player.melds = [{"kind": "kong", "tile": "tong7", "robbed": false, "from_seat": 3}]
			player.concealed.resize(10)
		elif seat == 3:
			player.melds = [{"kind": "add_kong", "tile": "wan6", "robbed": false, "from_seat": 2}]
			player.concealed.resize(10)
	r.players[3].ready = true
	r.players[3].charge_chicken = true
	r.round_meta.charge_chickens = {"tiao1": {"owner": 3, "location": "discard", "discard_id": 9}, "tong8": {"owner": 0, "location": "discard", "discard_id": 10}}
	r._refresh_charge_flags()
	r.last_discard = {"seat": 1, "tile": "tiao8"}
	table._on_require_turn(0)
	table._refresh()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	table._on_human_tile_gui(event, table.draw_box[0].get_child(0))

func _tile_rect(tile: TileView) -> Rect2:
	var transform := tile.get_global_transform()
	var first := transform * Vector2.ZERO
	var last := transform * tile.size
	return Rect2(first.min(last), first.max(last) - first.min(last))

func _control_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	var first := transform * Vector2.ZERO
	var last := transform * control.size
	return Rect2(first.min(last), first.max(last) - first.min(last))

func _check_layout() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	_expect(table.PLAYER_TILE_UNIT > table.TILE_UNIT, "Player tiles must be larger than wall and river tiles")
	var tiles: Array = []
	for seat in 4:
		for wall_tile in table.wall_box[seat].get_children():
			_expect(wall_tile.size.is_equal_approx(Vector2(52.8, 70.4)), "Wall tiles must keep their original dimensions")
		var river: ScrollContainer = table.discard_scroll[seat]
		_expect(river.position == Vector2(-180, 180) and river.size == Vector2(360, 228), "River size and placement must stay unchanged")
		for box in [table.hand_box[seat], table.draw_box[seat], table.meld_box[seat], table.chicken_box[seat]] + table.discard_box[seat]:
			for tile in box.get_children():
				var player_tile: bool = box == table.hand_box[seat] or box == table.draw_box[seat] or box == table.meld_box[seat] or box == table.chicken_box[seat]
				var expected_unit: float = table.PLAYER_TILE_UNIT if player_tile else table.TILE_UNIT
				_expect(tile.size.is_equal_approx(Vector2(TileView.BASE_W, TileView.BASE_H) * expected_unit), "Tile size must match its table zone")
				if not player_tile:
					_expect(tile.size.is_equal_approx(Vector2(52.8, 70.4)), "Discarded tiles must keep their original dimensions")
				var transform: Transform2D = tile.get_global_transform()
				_expect(is_equal_approx(transform.x.length(), table.surface.scale.x) and is_equal_approx(transform.y.length(), table.surface.scale.y), "No player or tile category may use a smaller display scale")
				var rect := _tile_rect(tile)
				if box in table.discard_box[seat]:
					rect = rect.intersection(_control_rect(table.discard_scroll[seat]))
					if rect.size.x <= 1.0 or rect.size.y <= 1.0:
						continue
				_expect(viewport_rect.encloses(rect), "Tile must fit the viewport: %s" % rect)
				for other in tiles:
					_expect(not rect.grow(-0.5).intersects(other.grow(-0.5)), "Face/hand tiles must not overlap: seat %d tile %s rect %s / %s" % [seat, tile.tile, rect, other])
				for label in table.center_labels.values() + table.avatars.values() + [table.center_info, table.action_bar, table.status_label]:
					_expect(not rect.grow(-0.5).intersects(_control_rect(label).grow(-0.5)), "Tiles must not cover scores or controls: %s %s / %s %s" % [tile.get_path(), rect, label.get_path(), _control_rect(label)])
				for wall_seat in 4:
					for wall_tile in table.wall_box[wall_seat].get_children():
						_expect(not rect.grow(-0.5).intersects(_tile_rect(wall_tile).grow(-0.5)), "Face tiles must not overlap the wall")
				tiles.append(rect)
		_expect(is_equal_approx(table.hand_box[seat].get_parent().rotation, table.ROTATIONS[table._relative_seat(seat)]))
		var discarded := 0
		for box in table.discard_box[seat]:
			discarded += box.get_child_count()
		var player: PlayerState = table.round.players[seat]
		_expect(discarded == player.discards.filter(func(card): return not Tiles.is_chicken(card)).size(), "River zones must preserve every ordinary discard")
		_expect(table.chicken_box[seat].get_child_count() == player.discards.filter(Tiles.is_chicken).size(), "Only retained discarded chickens stay in the chicken row")
		for tile in table.chicken_box[seat].get_children():
			_expect(Tiles.is_chicken(tile.tile), "Only chicken tiles belong in the chicken zone")
	for seat in 4:
		var count := 0
		for meld in table.round.players[seat].melds:
			count += 3 if meld.kind == "pung" else 4
		_expect(table.meld_box[seat].get_child_count() == count)

func _test_anchored_rows() -> void:
	_new_fixture()
	root.size = Vector2i(1440, 1520)
	var full_left := 0.0
	var fixed_right := 0.0
	var fixed_draw := Vector2.ZERO
	var expected_size := Vector2.ZERO
	for meld_count in 5:
		for seat in 4:
			var player: PlayerState = table.round.players[seat]
			player.melds.clear()
			for index in meld_count:
				player.melds.append({"kind": "pung", "tile": "wan%d" % (index + 1), "from_seat": posmod(seat + 1, 4), "after_discard": 0})
			player.concealed.clear()
			for index in 13 - meld_count * 3:
				player.concealed.append("tong%d" % (index % 9 + 1))
			player.concealed.append("tong9")
			player.just_drew = "tong9"
		table._refresh()
		await process_frame
		await process_frame
		if meld_count == 0:
			var first: TileView = table.hand_box[0].get_child(0)
			var last: TileView = table.hand_box[0].get_child(12)
			full_left = first.position.x
			fixed_right = last.position.x + last.size.x
			fixed_draw = table.draw_box[0].get_child(0).position
			expected_size = first.size
		for seat in 4:
			var first: TileView = table.hand_box[seat].get_child(0)
			var last: TileView = table.hand_box[seat].get_child(table.hand_box[seat].get_child_count() - 1)
			_expect(is_equal_approx(first.position.x - full_left, meld_count * 3 * (expected_size.x + table.TILE_GAP)), "After a pung, the hand must shorten from the left by three tile slots")
			_expect(is_equal_approx(last.position.x + last.size.x, fixed_right), "Hand right edge must stay fixed after melds")
			_expect(table.draw_box[seat].get_child(0).position.is_equal_approx(fixed_draw), "Draw slot must stay fixed after melds")
			_expect(first.size.is_equal_approx(expected_size), "A shorter hand must retain its enlarged tile size")
			if meld_count > 0:
				var meld_tile: TileView = table.meld_box[seat].get_child(0)
				_expect(meld_tile.position.x == table.EXPOSED_LEFT_X, "Melds must start at the fixed left table edge")
		_check_layout()
		if rendering and meld_count in [0, 1, 4]:
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png("res://docs/table_melds_%d.png" % meld_count) == OK)
	# Match the reference: pung, charge chicken, kong, hand, separate draw.
	for seat in 4:
		var player: PlayerState = table.round.players[seat]
		player.melds = [{"kind": "pung", "tile": "tong1", "from_seat": posmod(seat + 1, 4), "after_discard": 0}, {"kind": "kong", "tile": "tiao9", "from_seat": posmod(seat + 1, 4), "after_discard": 1}]
		player.discards = ["tiao1"]
		player.discard_history = ["tiao1"]
		player.concealed = ["wan2", "wan3", "wan4", "tong3", "tong4", "tong5", "tong9", "tong9"]
		player.just_drew = "tong9"
	table.round.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	table.round.players[0].charge_chicken = true
	table._on_require_turn(0)
	table._refresh()
	await process_frame
	await process_frame
	for seat in 4:
		var chicken: TileView = table.chicken_box[seat].get_child(0)
		_expect(chicken.position.x > table.meld_box[seat].get_child(2).position.x and chicken.position.x < table.meld_box[seat].get_child(3).position.x, "A chicken played between melds must keep its place between them")
		_expect(table.draw_box[seat].get_child(0).position.is_equal_approx(fixed_draw), "Draw slot must stay fixed with interleaved chickens")
	_check_layout()
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/table_reference.png") == OK)
	var original_round: RoundState = table.round
	var synced_round := RoundState.new()
	synced_round.apply_sync(original_round.serialize_for_seat(0))
	table.round = synced_round
	table._refresh()
	for seat in 4:
		_expect(table.chicken_box[seat].get_child(0).position.x < table.meld_box[seat].get_child(3).position.x, "Client sync must preserve chickens between melds")
	_check_layout()
	table.round = original_round
	# Stress all four directions: no melds through four kongs plus every chicken.
	for meld_count in 5:
		for seat in 4:
			var player: PlayerState = table.round.players[seat]
			player.melds.clear()
			for index in meld_count:
				player.melds.append({"kind": "kong", "tile": "wan%d" % (index + 1), "from_seat": posmod(seat + 1, 4), "after_discard": index * 2})
			player.discards = ["tiao1", "tong8", "tiao1", "tong8", "tiao1", "tong8", "tiao1", "tong8"]
			player.discard_history = player.discards.duplicate()
			player.concealed = []
			for index in 13 - meld_count * 3:
				player.concealed.append("tong2")
			player.concealed.append("tong9")
		table._refresh()
		_check_layout()
		for seat in 4:
			_expect(table.draw_box[seat].get_child(0).position.is_equal_approx(fixed_draw), "Overflow must never move the draw slot")
			if meld_count == 0:
				_expect(table.chicken_box[seat].get_child(0).position.x == table.EXPOSED_LEFT_X, "The first chicken must start at the table edge even without melds")
	print("[layout] fixed table-edge groups, right-aligned hands, fixed draws and overflow passed")

func _test_charge_chickens() -> void:
	for card in ["tiao1", "tong8"]:
		for seat in 4:
			_new_fixture()
			var player: PlayerState = table.round.players[seat]
			var other := "tong8" if card == "tiao1" else "tiao1"
			player.concealed = ["wan2", card, other, card]
			player.melds = [{"kind": "pung", "tile": "wan7", "from_seat": posmod(seat + 1, 4)}]
			table.round._discard(seat, "wan2")
			_expect(table.chicken_box[seat].get_child_count() == 0, "An ordinary first discard must not create a chicken marker")
			table.round._discard(seat, card)
			_expect(table.round.round_meta.charge_chickens[card].owner == seat, "The first of each chicken must be recorded by live play")
			table.round._discard(seat, other)
			table.round._discard(seat, card)
			var other_seat := posmod(seat + 1, 4)
			table.round.players[other_seat].discards = [card]
			table._refresh()
			_assert_charge_row(seat, card)
			_expect(is_zero_approx(table.chicken_box[other_seat].get_child(0).rotation), "Another player's chicken must stay upright")
			for local_seat in 4:
				table.human_seat = local_seat
				table._refresh()
				_assert_charge_row(seat, card)
				_check_layout()
			table.human_seat = 0
			# Remove the later ordinary copy, then transfer the original into a pung.
			table.round._remove_from_discards(seat, card)
			table.round.players[other_seat].melds = [{"kind": "pung", "tile": card, "from_seat": seat}]
			table.round._remove_from_discards(seat, card, other_seat, "meld", 0)
			table._refresh()
			_assert_claimed_charge(seat, other_seat, card, other)
			var synced := RoundState.new()
			synced.apply_sync(table.round.serialize_for_seat(0))
			table.round = synced
			table._refresh()
			_assert_claimed_charge(seat, other_seat, card, other)
			_check_layout()
	print("[layout] both charge chickens, four seats, claims, repeats and client sync passed")

func _assert_charge_row(seat: int, card: String) -> void:
	var chickens: Control = table.chicken_box[seat]
	_expect(chickens.get_child_count() == 3, "Every chicken discard must remain represented")
	var charge: TileView = chickens.get_child(0)
	_expect(charge.tile == card and is_equal_approx(charge.rotation, -PI / 2.0), "Only the first chicken must be sideways")
	_expect(charge.get_meta("charge_chicken", false), "The sideways chicken must be marked as the charge")
	_expect(is_equal_approx(chickens.get_child(1).rotation, -PI / 2.0), "The first of the other chicken kind is also a charge")
	_expect(is_zero_approx(chickens.get_child(2).rotation), "A later copy of the same chicken remains upright")
	var last_meld: TileView = table.meld_box[seat].get_child(2)
	_expect(is_equal_approx(charge.position.x - last_meld.position.x - last_meld.size.x, table.TILE_GAP + 10.0), "Chicken tiles must be adjacent to the meld group")
	_expect(is_equal_approx(charge.position.y - charge.size.y, last_meld.position.y), "Charge and meld tiles must share a row")

func _assert_claimed_charge(source: int, receiver: int, card: String, other: String) -> void:
	_expect(table.round.players[source].discards == ["wan2", other], "Claimed copies leave the original river")
	_expect(not table.round.players[source].discard_history.has(card), "Claimed copies leave discard history")
	_expect(table.chicken_box[source].get_child_count() == 1, "The original player only displays the remaining chicken")
	_expect(table.chicken_box[source].get_child(0).get_meta("charge_chicken", false), "The other kind retains its independent charge")
	var charge: TileView = table.meld_box[receiver].get_child(0)
	_expect(charge.get_meta("charge_chicken", false) and not is_zero_approx(charge.rotation), "Claimed charge moves sideways into receiver meld")
	_expect(table.round.is_charge_meld(receiver, 0), "Ownership survives sync")

func _test_dense_discards() -> void:
	for seat in 4:
		table.round.players[seat].score = [-12345.0, 23456.0, 1234.0, -9876.0][seat]
		table.round.players[seat].discards.clear()
		for index in 30:
			table.round.players[seat].discards.append(Tiles.from_index(index % 27))
		table.round.players[seat].discards.append_array(["tiao1", "tiao1", "tiao1", "tong8", "tong8", "tong8"])
		table.round.players[seat].discard_history = table.round.players[seat].discards.duplicate()
		table.round.players[seat].melds = []
		for index in 4:
			table.round.players[seat].melds.append({"kind": "add_kong" if index == 3 else "kong", "tile": "wan%d" % (index + 1), "from_seat": posmod(seat + index % 3 + 1, 4), "robbed": false})
		# Four melds leave two concealed tiles, including the draw.
		table.round.players[seat].concealed = ["tong2", "tong9"]
		table.round.players[seat].just_drew = "tong9"
	table.round.round_meta.charge_chickens = {"tong8": {"owner": 0, "location": "discard", "discard_id": 25}}
	table.round.players[0].charge_chicken = true
	table._refresh()
	await process_frame
	await process_frame
	_check_layout()
	for seat in 4:
		var river: ScrollContainer = table.discard_scroll[seat]
		_expect(river.get_v_scroll_bar().max_value > river.size.y, "Dense rivers must scroll without shrinking tiles")
		_expect(river.scroll_vertical > 0, "New discards must scroll into view")
		var charge_count := 0
		for tile in table.chicken_box[seat].get_children():
			if not is_zero_approx(tile.rotation):
				charge_count += 1
		_expect(charge_count == (1 if seat == 0 else 0), "Dense chicken rows must retain exactly one charge marker")
		river.scroll_vertical = 0
	_check_layout()
	for seat in 4:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = _control_rect(table.discard_scroll[seat]).get_center()
		Input.parse_input_event(wheel)
		await process_frame
		_expect(table.discard_scroll[seat].scroll_vertical > 0, "Every rotated river must accept scroll input")
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/table_dense.png") == OK)
	for seat in [1, 2, 3]:
		table.human_seat = seat
		table._refresh()
		await process_frame
		await process_frame
		_expect(table._relative_seat(seat) == 0)
		_expect(table.seat_roots[seat].rotation == 0.0)
		_expect(table.hand_box[seat].get_child(0).face_up)
		_check_layout()
	table.human_seat = 0
	_build_midgame()

func _test_meld_markers() -> void:
	for kind in ["pung", "kong", "add_kong", "concealed"]:
		for source in [1, 2, 3]:
			_new_fixture()
			var player: PlayerState = table.round.players[0]
			player.melds = [{"kind": "kong" if kind == "concealed" else kind, "tile": "tong8", "from_seat": source, "concealed": kind == "concealed"}]
			table._refresh()
			var rotated := 0
			var expected_index: int = {1: 3, 2: 3, 3: 0}.get(source) if kind == "kong" else -1
			for index in table.meld_box[0].get_child_count():
				var tile: TileView = table.meld_box[0].get_child(index)
				if not is_zero_approx(tile.rotation):
					rotated += 1
					_expect(index == expected_index, "Only exposed kong source tiles may rotate")
			_expect(rotated == (1 if kind == "kong" else 0), "Only exposed kongs should have a sideways tile; self kongs stay upright")
	# 四向桌面和本地换座位均需容纳对家上横的两行明杠。
	_new_fixture()
	for owner in 4:
		table.round.players[owner].melds = []
		for offset in [1, 2, 3]:
			table.round.players[owner].melds.append({"kind": "kong", "tile": "wan%d" % offset, "from_seat": posmod(owner + offset, 4)})
		table.round.players[owner].concealed = ["tong3", "tong4", "tong5", "tong9", "tong9"]
		table.round.players[owner].just_drew = "tong9"
	for human in 4:
		table.human_seat = human
		table._refresh()
		await process_frame
		await process_frame
		_check_layout()
		for owner in 4:
			var above: TileView = table.meld_box[owner].get_child(7)
			var below: TileView = table.meld_box[owner].get_child(5)
			_expect(above.position.y < below.position.y, "Opposite source must lie above the middle upright tile")
	# 截图分别展示下家右横、上家左横、对家上横、自有暗杠/加杠四竖。
	table.human_seat = 0
	for entry in [[0, 1], [3, 3], [2, 2]]:
		var owner: int = entry[0]
		table.round.players[owner].melds = [{"kind": "kong", "tile": "tong2", "from_seat": posmod(owner + int(entry[1]), 4)}]
		table.round.players[owner].concealed = ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong7", "tong8", "tong9", "wan9", "wan9"]
		table.round.players[owner].just_drew = "wan9"
	table.round.players[1].melds = [{"kind": "kong", "tile": "tiao9", "concealed": true}, {"kind": "add_kong", "tile": "wan7", "from_seat": 2}]
	table.round.players[1].concealed = ["wan1", "wan2", "wan3", "tong1", "tong2", "tong3", "wan9", "wan9"]
	table.round.players[1].just_drew = "wan9"
	table.round.phase = "settled"
	table._result_shown = true
	table._refresh()
	table.result_layer.hide()
	root.size = Vector2i(1440, 1520)
	await process_frame
	await process_frame
	_check_layout()
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/table_kong_arrangements.png") == OK)
	_build_midgame()

func _test_result() -> void:
	table._result_shown = true
	table.round.phase = "settled"
	table.round.round_meta.winner = 0
	table.round.round_meta.self_draw = true
	table.round.round_meta.flip_tile = "tong8"
	table.round.last_result = {"deltas": [24.0, -8.0, -8.0, -8.0], "lines": ["自摸 +4", "清一色 +24", "翻牌鸡：八筒"]}
	table._refresh()
	table._show_result()
	_expect(table.result_layer.visible)
	var flip_tile: TileView = table._result_panel.get_node("FlippedChickenTile")
	_expect(flip_tile.size.is_equal_approx(Vector2(TileView.BASE_W, TileView.BASE_H) * table.RESULT_TILE_UNIT), "Settlement chicken tile must match result card tiles")

func _test_draw_results() -> void:
	_new_fixture()
	root.size = Vector2i(1440, 1520)
	var wait := ["wan1", "wan2", "wan3", "tiao4", "tiao5", "tiao6", "tong1", "tong2", "tong3", "wan9"]
	table.round.players[0].concealed = wait.duplicate()
	table.round.players[0].melds = [{"kind": "add_kong", "tile": "tiao1", "from_seat": 2}]
	table.round.players[1].concealed = wait.duplicate()
	table.round.players[1].melds = [{"kind": "kong", "tile": "wan5", "from_seat": 3}]
	table.round.players[1].discards = ["tong8"]
	table.round.players[2].concealed = ["wan1", "wan3", "wan5", "wan7", "wan9", "tiao3", "tiao4", "tiao7", "tiao9", "tong2", "tong4", "tong6", "tong8"]
	table.round.players[3].concealed = table.round.players[2].concealed.duplicate()
	table.round.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "meld", "meld_index": 0}, "tong8": {"owner": 1, "location": "discard", "discard_id": 0}}
	table.round._refresh_charge_flags()
	for index in 108:
		table.round.wall.draw_head()
	table.round._penzu()
	await process_frame
	await process_frame
	_expect(table.round.last_result.deltas == [24.0, 12.0, -16.0, -20.0], "Visible draw result must match chicken and kong payer rules")
	_expect(table.result_layer.visible and not table.status_label.visible and table.status_label.text == "", "Mixed draw keeps table status text hidden")
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/rules_draw_result.png") == OK)
	table.result_layer.hide()
	_check_layout()
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/rules_charge_transfer.png") == OK)
	_new_fixture()
	for player in table.round.players:
		player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
	for index in 108:
		table.round.wall.draw_head()
	table.round._penzu()
	await process_frame
	await process_frame
	_expect(table.round.next_chicken_multiplier == 2 and not table.status_label.visible and table.status_label.text == "", "All-called draw keeps table status text hidden")
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/rules_all_called.png") == OK)

func _test_next_round() -> void:
	table.round.players[0].score = 224.0
	table.round.next_chicken_multiplier = 2
	table.new_game()
	_expect(table.round.players[0].score == 224.0)
	_expect(table.round.round_meta.chicken_multiplier == 2, "Next game carries the chicken multiplier")
	_expect(not table.round_label.text.contains("鸡分 ×2"), "The active multiplier stays inside settlement details")
	_expect(not table.result_layer.visible)
	_expect(table.round.phase == "playing")

func _expect(condition: bool, message: String = "Table assertion failed") -> void:
	if not condition:
		failed = true
		push_error(message)
