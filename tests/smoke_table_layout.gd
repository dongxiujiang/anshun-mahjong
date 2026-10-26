extends SceneTree
const H := preload("res://tests/test_harness.gd")

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
	if rendering:
		while table.round.phase == RoundState.Phase.DEALING or table._table_animation_controller.input_locked():
			await process_frame
	_check_layout()
	#_test_ai_speed()
	await _test_input()
	_test_ready()
	_test_ready_frame()
	_test_test_pattern_hidden()
	_test_win_with_kong_actions()
	_test_kong()
	_test_kong_choices()
	await _test_response_actions()
	_test_sync()
	_test_network_reset()
	_test_charge_chickens()
	_test_claimed_charge_kong_marker()
	await _test_anchored_rows()
	await _test_current_scores()
	_build_midgame()
	for dimensions in [Vector2i(1440, 1520), Vector2i(1440, 1000), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1920, 1080), Vector2i(2400, 1080), Vector2i(1280, 800), Vector2i(1080, 1080), Vector2i(1080, 1920)]:
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
	await _test_concealed_kong_reveal()
	_test_result()
	await process_frame
	await process_frame
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/table_result.png") == OK)
	await _test_draw_results()
	await _test_landscape_stretch()
	await _test_next_round()
	_test_independent_settlement_counts()
	if not failed:
		print("[smoke_table_layout] selection, ready, kong, sync, layout, settlement passed")
	table.queue_free()
	await process_frame
	await H.quit_cleanly(self, 1 if failed else 0)

func _new_fixture() -> void:
	if table.round != null:
		table.round.phase = RoundState.Phase.IDLE
	table._clear_actions()
	table._response_disc = ""
	table._declaring_ready = false
	table._table_animation_controller.reset()
	table._settlement_animation_controller.reset()
	table._settlement_card.hide_post_settlement_controls()
	table.round = RoundState.new()
	table.round.build_players(table.human_seat)
	table.round.controllers = [null, null, null, null]
	table.round.wall = WallRing.new(TileSetFactory.create_deck())
	table.round.wall.set_head(0)
	table.round.current_turn = table.human_seat
	table.round.phase = RoundState.Phase.PLAYING
	table.round.awaiting = true
	table.round.require_turn.connect(table._on_require_turn)
	table.round.require_response.connect(table._on_require_response)
	table.round.state_update.connect(table._refresh)
	table.round.round_finished.connect(table._on_round_finished)

func _settle_fixture() -> void:
	# Use the real ledger and score application so phase, result and totals agree.
	table.round._finish()
	table._table_animation_controller.reset()
	table._settlement_animation_controller.reset()
	table._refresh()
	table._settlement_animation_controller.skip()

func _test_ai_speed() -> void:
	for speed in ["instant", "fast", "standard"]:
		table._speed_buttons[speed].pressed.emit()
		_expect(root.get_node("GameConfig").ai_speed == speed, "Speed buttons must select the requested speed")
		var expected := float({"instant": 1, "fast": 2, "standard": 3}[speed]) if rendering else 0.0
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
	await process_frame
	_expect(table.round.players[0].discard_count == 1, "One completed tap records exactly one discard, even when claimed")
	for button in table.action_bar.get_children():
		_expect(button.text != "出牌", "Discard never requires a separate button")

func _test_ready() -> void:
	_new_fixture()
	var player: PlayerState = table.round.players[0]
	player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan9", "tong9"]
	player.just_drew = "tong9"
	table._on_require_turn(0)
	table._refresh()
	table._table_actions._selecting = false
	table._update_interactivity()
	for tile in table.hand_box[0].get_children() + table.draw_box[0].get_children():
		_expect(not tile.interactive and tile.modulate == Color.WHITE, "Waiting for a response keeps tiles bright but non-interactive")
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

func _test_ready_frame() -> void:
	var frame: Panel = table.ready_frames[0]
	_expect(frame != null and frame.visible, "Ready player gets a gold hand-area frame")
	_expect(frame.size.x > 0.0 and frame.size.y > 0.0, "Ready frame encloses the hand")
	var drawn: TileView = table.draw_box[0].get_child(0)
	_expect(frame.position.x + frame.size.x <= drawn.position.x, "Ready frame excludes the separate drawn tile")
	for seat in range(1, 4):
		_expect(not table.ready_frames[seat].visible, "Non-ready seats do not show the ready frame")
	var host: RoundState = table.round
	host.players[1].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
	host.players[1].ready = true
	table._refresh()
	_expect(table.ready_frames[1].visible, "Ready opponents show the gold frame on the table")
	var client := RoundState.new()
	client.apply_sync(host.serialize_for_seat(0))
	table.round = client
	table._refresh()
	_expect(table.ready_frames[1].visible, "Online snapshots preserve the opponent ready frame")

func _test_test_pattern_hidden() -> void:
	var config = root.get_node_or_null("GameConfig")
	var was_debug := false
	if config != null:
		was_debug = bool(config.debug_enabled)
		config.set_debug_enabled(false, false)
	_new_fixture()
	_expect(table._test_pattern_button != null and not table._test_pattern_button.visible,
		"正式模式不显示测试牌型按钮")
	if config != null:
		config.set_debug_enabled(was_debug, false)

func _test_win_with_kong_actions() -> void:
	_new_fixture()
	var player: PlayerState = table.round.players[0]
	player.concealed = ["wan1","wan1","wan1","wan1","wan2","wan2","wan3","wan3",
		"wan4","wan4","wan5","wan5","wan6","wan6"]
	player.just_drew = "wan1"
	table.round.current_turn = 0
	table.round.awaiting = true
	table._table_actions._build_turn_options(player)
	var labels: Array = []
	for button in table._table_actions.action_bar.get_children():
		if button is Button: labels.append(button.text)
	_expect("自摸" in labels and "暗杠" in labels,
		"winning draw still shows concealed kong: " + str(labels))
	player.ready = true
	table._table_actions._build_turn_options(player)
	labels.clear()
	for button in table._table_actions.action_bar.get_children():
		if button is Button: labels.append(button.text)
	_expect("自摸" in labels and "暗杠" not in labels and "加杠" not in labels,
		"ready player can only self-win, no kong buttons: " + str(labels))
	_new_fixture()
	player = table.round.players[0]
	player.concealed = ["wan1","wan2","wan3","wan4","wan4","wan4","wan5","wan5","wan5","wan6","wan6"]
	player.melds = [{"kind": "pung", "tile": "wan1"}]
	player.just_drew = "wan1"
	table.round.current_turn = 0
	table.round.awaiting = true
	table._table_actions._build_turn_options(player)
	labels.clear()
	for button in table._table_actions.action_bar.get_children():
		if button is Button: labels.append(button.text)
	_expect("自摸" in labels and "加杠" in labels,
		"winning draw still shows added kong: " + str(labels))
	table._clear_actions()
	table._on_require_response(0, 1, "wan5", {"can_win": true, "can_pong": true, "can_kong": true})
	labels.clear()
	for button in table._table_actions.action_bar.get_children():
		if button is Button: labels.append(button.text)
	_expect("胡" in labels and "碰" in labels and "杠" in labels and "过" in labels,
		"win+pong+kong response shows all choices: " + str(labels))

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

func _test_response_actions() -> void:
	_build_midgame()
	table._on_require_response(0, 1, "tong9", {"can_win": true, "can_pong": true, "can_kong": true})
	table._refresh()
	await process_frame
	await process_frame
	_expect(table.action_bar.get_child_count() == 4, "Win, pong, kong and pass must fit together")
	_check_layout()

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

func _check_hand_anchor(seat: int) -> void:
	var first: TileView = table.hand_box[seat].get_child(0)
	var drawn: TileView = table.draw_box[seat].get_child(0)
	var right := drawn.position.x + drawn.size.x
	_expect(is_equal_approx(-first.position.x, right), "Hands and draw must stay centered as melds shorten the hand")

func _check_layout() -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	var felt_rect: Rect2 = table.surface.get_global_transform() * table._table_bounds()
	_expect(table._landscape, "Every window ratio must keep the landscape table")
	_expect(table.PLAYER_TILE_UNIT > table.TILE_UNIT, "Player tiles must be larger than wall and river tiles")
	_expect(table.OWN_PLAYER_TILE_UNIT > table.PLAYER_TILE_UNIT, "Only the local player's non-discard tiles are enlarged")
	if table.action_bar.visible:
		var row: Dictionary = table._hand_layout(table.human_seat)
		var draw_right: float = table._table_center().x + row.draw_x + TileView.BASE_W * table.OWN_HAND_TILE_UNIT
		var draw_top: float = table._table_center().y + table._seat_metrics(table.human_seat).hand_y
		_expect(table.action_bar.position.x + table.action_bar.size.x >= draw_right - 0.01, "Actions stay above the draw or shift right to keep the local river clear")
		_expect(table.action_bar.position.y + table.action_bar.size.y < draw_top, "Actions must sit above the draw slot")
		for button in table.action_bar.get_children():
			_expect(button.custom_minimum_size == table.DISCARD_BUTTON_SIZE, "Every turn and response action must keep the enlarged touch target")
	var tiles: Array = []
	for seat in 4:
		var river: ScrollContainer = table.discard_scroll[seat]
		var river_metrics: Dictionary = table._seat_metrics(seat)
		var seat_fallback: bool = table._player_tile_areas._exposed_layouts.get(seat, []).any(func(group): return bool(group.get("fallback", false)))
		_expect(river.position == river_metrics.river_position and river.size == river_metrics.river_size, "River size and placement must match the current orientation")
		_expect(river.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER and not river.get_v_scroll_bar().visible, "Discard scrollbars must remain hidden even when the river is full")
		for box in [table.hand_box[seat], table.draw_box[seat], table.meld_box[seat], table.chicken_box[seat]] + table.discard_box[seat]:
			for tile in box.get_children():
				var player_tile: bool = box == table.hand_box[seat] or box == table.draw_box[seat] or box == table.meld_box[seat] or box == table.chicken_box[seat]
				var expected_unit: float = table.TILE_UNIT
				if box == table.hand_box[seat] or box == table.draw_box[seat]:
					expected_unit = table.OWN_HAND_TILE_UNIT if seat == table.human_seat else table.PLAYER_TILE_UNIT
				elif player_tile:
					expected_unit = table.OWN_PLAYER_TILE_UNIT if seat == table.human_seat else table.PLAYER_TILE_UNIT
				else:
					expected_unit = table.RIVER_TILE_UNIT
				_expect(tile.size.is_equal_approx(Vector2(TileView.BASE_W, TileView.BASE_H) * expected_unit), "Tile size must match its table zone")
				if not player_tile:
					_expect(tile.size.is_equal_approx(Vector2(TileView.BASE_W, TileView.BASE_H) * table.RIVER_TILE_UNIT), "Discarded tiles must use the readable river dimensions")
				var transform: Transform2D = tile.get_global_transform()
				_expect(is_equal_approx(transform.x.length(), table.surface.scale.x) and is_equal_approx(transform.y.length(), table.surface.scale.y), "No player or tile category may use a smaller display scale")
				var rect := _tile_rect(tile)
				var settings_hot: Rect2 = table._settings_button.get_global_transform() * table._settings_button.touch_rect()
				_expect(not rect.grow(-0.5).intersects(settings_hot), "Settings touch target must not steal taps from any tile")
				if box in table.discard_box[seat]:
					rect = rect.intersection(_control_rect(table.discard_scroll[seat]))
					if rect.size.x <= 1.0 or rect.size.y <= 1.0:
						continue
				_expect(felt_rect.encloses(rect), "Tile must fit the real table felt even on fallback: %s / %s" % [rect, felt_rect])
				if not seat_fallback:
					for other in tiles:
						_expect(not rect.grow(-0.5).intersects(other.grow(-0.5)), "Face/hand tiles must not overlap: seat %d tile %s rect %s / %s" % [seat, tile.tile, rect, other])
				if not seat_fallback:
					for label in table.center_labels.values() + table.avatars.values() + [table.center_info, table.action_bar, table.status_label]:
						if not label.visible or label.size.x < 1.0 or label.size.y < 1.0:
							continue
						if label == table.action_bar and box in table.discard_box[seat] and table._relative_seat(seat) == 1:
							continue
						_expect(not rect.grow(-0.5).intersects(_control_rect(label).grow(-0.5)), "Tiles must not cover scores or controls: %s %s / %s %s" % [tile.get_path(), rect, label.get_path(), _control_rect(label)])
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
	var expected_sizes := {}
	var anchors := {}
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
		for seat in 4:
			var first: TileView = table.hand_box[seat].get_child(0)
			var last: TileView = table.hand_box[seat].get_child(table.hand_box[seat].get_child_count() - 1)
			var drawn: TileView = table.draw_box[seat].get_child(0)
			if meld_count == 0:
				expected_sizes[seat] = first.size
			_check_hand_anchor(seat)
			_expect(is_equal_approx(drawn.position.x - (last.position.x + last.size.x), table.DRAW_GAP), "The reserved draw slot stays separated by the original gap")
			_expect(first.size.is_equal_approx(expected_sizes[seat]), "A shorter hand must retain its tile size")
			var anchor_x: float = table._player_tile_areas.exposed_anchor_x(seat)
			if anchors.has(seat):
				_expect(is_equal_approx(anchor_x, anchors[seat]), "Exposed anchor must not move with hand length")
			else:
				anchors[seat] = anchor_x
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
		var groups: Array = table._exposed_layouts[seat]
		var melds := groups.filter(func(group): return group.has("meld")).size()
		var chickens := groups.filter(func(group): return group.has("chicken")).size()
		_expect(melds == 2 and chickens >= 1, "Stacked layout keeps two melds and every chicken")
		_check_hand_anchor(seat)
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
		_expect(table._exposed_layouts[seat].any(func(group): return group.has("chicken")), "Client sync must preserve chickens in the stacked block")
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
			_check_hand_anchor(seat)
			if meld_count == 0:
				var group: Dictionary = table._exposed_layouts[seat][0]
				_expect(not group.is_empty(), "Exposed group uses the fixed seat anchor")
	print("[layout] table-edge groups, centered hands, separate draws and overflow passed")

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

func _test_claimed_charge_kong_marker() -> void:
	_new_fixture()
	table.round.players[1].melds = [{"kind": "kong", "tile": "tong8", "from_seat": 0}]
	table.round.round_meta.charge_chickens = {"tong8": {"owner": 1, "location": "meld", "meld_index": 0}}
	table.round._refresh_charge_flags()
	table._refresh()
	_expect(table.round.is_charge_meld(1, 0), "Claimed charge ownership remains intact in game state")
	for tile in table.meld_box[1].get_children():
		_expect(not tile.get_meta("charge_chicken", false), "A claimed kong does not display a charge badge")

func _assert_charge_row(seat: int, card: String) -> void:
	var chickens: Control = table.chicken_box[seat]
	_expect(chickens.get_child_count() == 3, "Every chicken discard must remain represented")
	var charge: TileView = chickens.get_child(0)
	_expect(charge.tile == card and is_equal_approx(charge.rotation, -PI / 2.0), "Only the first chicken must be sideways")
	_expect(charge.get_meta("charge_chicken", false), "The sideways chicken must be marked as the charge")
	_expect(is_equal_approx(chickens.get_child(1).rotation, -PI / 2.0), "The first of the other chicken kind is also a charge")
	_expect(is_zero_approx(chickens.get_child(2).rotation), "A later copy of the same chicken remains upright")
	var last_meld: TileView = table.meld_box[seat].get_child(2)
	_expect(charge.position.y > last_meld.position.y, "Charge chicken row sits below the meld rows")
	_expect(absf(charge.position.x - last_meld.position.x) < 220.0, "Charge chicken row stays close to the meld block")

func _assert_claimed_charge(source: int, receiver: int, card: String, other: String) -> void:
	_expect(table.round.players[source].discards == ["wan2", other], "Claimed copies leave the original river")
	_expect(not table.round.players[source].discard_history.has(card), "Claimed copies leave discard history")
	_expect(table.chicken_box[source].get_child_count() == 1, "The original player only displays the remaining chicken")
	_expect(table.chicken_box[source].get_child(0).get_meta("charge_chicken", false), "The other kind retains its independent charge")
	var charge: TileView = table.meld_box[receiver].get_child(0)
	_expect(is_zero_approx(charge.rotation) and not charge.get_meta("charge_chicken", false), "Claimed chicken pung has three upright tiles")
	for tile in table.meld_box[receiver].get_children():
		_expect(is_zero_approx(tile.rotation), "Every chicken pung tile stays upright")
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
	_settle_fixture()
	root.size = Vector2i(1440, 1520)
	await process_frame
	await process_frame
	_check_layout()
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/table_kong_arrangements.png") == OK)
	_build_midgame()

func _test_concealed_kong_reveal() -> void:
	table.human_seat = 0
	_new_fixture()
	var host: RoundState = table.round
	var kong_tiles := ["wan7", "tong6", "tiao8", "tiao9"]
	for owner in 4:
		host.players[owner].melds = [{"kind": "kong", "tile": kong_tiles[owner], "concealed": true, "after_discard": 3}]
		host.players[owner].concealed = ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
	root.size = Vector2i(1440, 1520)
	for discard_count in [3, 4, 5]:
		for player in host.players:
			player.discard_count = discard_count
		var revealed: bool = discard_count == 5
		for viewer in 4:
			table.human_seat = viewer
			for synced in [false, true]:
				if synced:
					var client := RoundState.new()
					client.apply_sync(host.serialize_for_seat(viewer))
					table.round = client
				else:
					table.round = host
				table._refresh()
				for owner in 4:
					_expect(table.meld_box[owner].get_child_count() == 4, "Every concealed kong displays all four tiles")
					var owner_can_read: bool = revealed or owner == viewer
					for tile in table.meld_box[owner].get_children():
						_expect(tile.face_up == owner_can_read, "Owner reads the concealed kong; opponents wait for the public reveal")
						_expect(tile.tile == (kong_tiles[owner] if owner_can_read else ""), "Face-down kong views contain no face or tooltip value")
						_expect(is_zero_approx(tile.rotation), "Hidden and revealed concealed kongs both keep four upright tiles")
						if not owner_can_read:
							_expect(tile.tooltip_text == "", "Hidden kong cannot leak its value through a tooltip")
			table.round = host
			table._refresh()
			await process_frame
			await process_frame
			_check_layout()
			if rendering and viewer == 0 and discard_count in [4, 5]:
				await RenderingServer.frame_post_draw
				var suffix := "revealed" if revealed else "hidden"
				_expect(root.get_texture().get_image().save_png("res://docs/table_concealed_kong_%s.png" % suffix) == OK)
	for player in host.players:
		player.discard_count = 4
	host.players[0].concealed.append("wan9")
	host.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true}, true)
	table.round = host
	_settle_fixture()
	for owner in 4:
		for tile in table.meld_box[owner].get_children():
			_expect(tile.face_up and tile.tile == kong_tiles[owner], "Early settlement shows the complete concealed kong on the table")
	table.human_seat = 0
	_build_midgame()

func _test_result() -> void:
	table.round.players[0].concealed = ["wan2", "wan3", "wan4", "tiao4", "tiao5", "tiao6", "tong2", "tong3", "tong4", "tong9", "tong9"]
	table.round.players[0].just_drew = "tong9"
	table.round.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true}, true)
	table.round.wall._ring[table.round.wall._head] = "tong8"
	_settle_fixture()
	var settlement = table._settlement_animation_controller
	_expect(settlement.is_completed() and settlement.boards.size() == 4, "Settlement displays four final tabletop payment boards")
	_expect(settlement.current_pairs == table.round.last_result.pairwise, "Tabletop payment boards display the authoritative ledger")
	_expect(settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE and not table._settlement_card._post_controls is Panel, "Settlement keeps an unshaded, non-blocking table and plain bottom controls")
	var flip_tile: TileView = settlement._flip_view
	_expect(is_instance_valid(flip_tile) and flip_tile.visible and flip_tile.face_up and flip_tile.tile == "tong8", "Settlement exposes the actual flipped chicken on the table")
	if is_instance_valid(flip_tile):
		_expect(_control_rect(table.surface).encloses(_control_rect(flip_tile)), "The flipped chicken stays inside the tabletop")

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
	_expect(table.round.last_result.deltas == [32.0, 20.0, -24.0, -28.0], "Visible draw result must match chicken, base4 and kong payer rules")
	_expect(table._settlement_animation_controller.has_started(), "Mixed draw starts tabletop settlement automatically")
	table._settlement_animation_controller.skip()
	_expect(table._settlement_animation_controller.is_completed() and table._settlement_card._post_controls.visible, "Settlement controls appear only after the preview finishes")
	_expect(not table.status_label.visible and table.status_label.text == "", "Mixed draw keeps table status text hidden")
	_expect(table._settlement_animation_controller.boards.size() == 4 and table._settlement_animation_controller.current_pairs == table.round.last_result.pairwise, "Mixed draw shows the real chicken and kong payments on the table")
	_expect(not is_instance_valid(table._settlement_animation_controller._flip_view), "A draw never creates a flipped chicken")
	await process_frame
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/rules_draw_result.png") == OK)
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
	var all_called_round: RoundState = table.round
	var scores: Array = table.round.players.map(func(player): return player.score)
	await process_frame
	await process_frame
	_expect(table.round.next_chicken_multiplier == 2 and not table.status_label.visible and table.status_label.text == "", "All-called draw keeps table status text hidden")
	await create_timer(2.0).timeout
	_expect(table.round == all_called_round and table.round.phase == RoundState.Phase.SETTLED, "All-called draw waits for the next-round button instead of advancing automatically")
	_expect(table._settlement_animation_controller.is_completed() and table._settlement_animation_controller.boards.is_empty(), "All-called draw completes without payment boards")
	_expect(not is_instance_valid(table._settlement_animation_controller._flip_view) and table._settlement_card._post_controls.visible and not table._next_round_button.disabled, "All-called draw retains only the next-round control without a chicken flip")
	_expect(all_called_round.last_result.deltas == [0.0, 0.0, 0.0, 0.0] and all_called_round.players.map(func(player): return player.score) == scores, "All-called draw never changes cumulative scores")
	if rendering:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png("res://docs/rules_all_called.png") == OK)

func _test_next_round() -> void:
	table.round.players[0].score = 224.0
	table.round.players[3].score = -24.0
	table.round.next_chicken_multiplier = 2
	table.round.next_dealer_seat = 3
	table.human_seat = 3
	table._next_round_button.pressed.emit()
	if rendering:
		while table.round.phase == RoundState.Phase.DEALING or table._table_animation_controller.input_locked():
			await process_frame
	_expect(table.round.players[0].score == 224.0)
	_expect(table.round.players[3].score == -24.0, "Next game carries negative cumulative score before play")
	_expect(table.round.dealer_seat == 3 and table.round.current_turn == 3, "New game starts from the newly selected dealer")
	_expect(table.round.players[3].is_dealer and table.round.players[3].concealed.size() == 14, "New dealer receives14 and shows dealer badge")
	_expect(table.center_labels[3].text.contains("-24分"), "Table immediately displays preserved negative score")
	_expect(table.round.round_meta.chicken_multiplier == 2, "Next game carries the chicken multiplier")
	_expect(not table.round_label.text.contains("鸡分 ×2"), "The active multiplier stays inside settlement details")
	_expect(not table._settlement_animation_controller.has_started() and table._settlement_animation_controller.boards.is_empty() and not table._settlement_card._post_controls.visible, "New game removes all settlement boards and bottom controls")
	_expect(table.round.phase == RoundState.Phase.PLAYING)
	for seat in 4:
		_expect(not table.ready_frames[seat].visible, "A new round clears the previous ready gold frame")

func _test_independent_settlement_counts() -> void:
	var network = root.get_node_or_null("Network")
	if network == null or network.net_node == null:
		_expect(false, "Network autoload is available for settlement count test")
		return
	_new_fixture()
	table.human_seat = 0
	table.round.phase = RoundState.Phase.SETTLED
	var old_mode: String = network.mode
	var old_lobby: Dictionary = network.net_node.lobby.duplicate(true)
	var old_round: int = network.net_node.round_number
	var seats := [
		{"seat": 0, "ai": false, "ready": true},
		{"seat": 1, "ai": false, "ready": false},
		{"seat": 2, "ai": true, "ready": true},
		{"seat": 3, "ai": true, "ready": true},
	]
	network.mode = "client"
	network.net_node.round_number = 1
	network.net_node.lobby = {"ready_round": 1, "seats": seats,
		"return_vote": {"humans": [0, 1], "yes": {0: true, 1: false}}}
	table._settlement_card._refresh_next_round_controls()
	_expect(table._settlement_card._return_seat_button.text == "返回座位 1/2", "返回座位计数独立统计返回投票")
	_expect(table._next_round_button.text.begins_with("准备下一局 1/2"), "准备下一局计数独立统计 ready")
	network.mode = old_mode
	network.net_node.lobby = old_lobby
	network.net_node.round_number = old_round

func _physical_rect(control: Control) -> Rect2:
	return root.get_screen_transform() * _control_rect(control)

func _test_landscape_stretch() -> void:
	# Match the real Android canvas settings, including aspect expansion.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(2280, 1280)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_build_midgame()
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1920, 1080), Vector2i(2400, 1080), Vector2i(1280, 800)]:
		root.size = dimensions
		await process_frame
		await process_frame
		_expect(table._landscape, "The production canvas must select landscape on Android screen ratios")
		var screen_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		var scaled_surface := _physical_rect(table.surface)
		_expect(screen_rect.grow(0.01).encloses(scaled_surface), "The scaled table must fit the physical screen")
		for seat in 4:
			var seat_fallback: bool = table._player_tile_areas._exposed_layouts.get(seat, []).any(func(group): return bool(group.get("fallback", false)))
			for box in [table.hand_box[seat], table.draw_box[seat], table.meld_box[seat], table.chicken_box[seat]]:
				if seat_fallback and box in [table.meld_box[seat], table.chicken_box[seat]]:
					continue
				for tile in box.get_children():
					_expect(screen_rect.encloses(_physical_rect(tile)), "All player tiles must fit the physical Android screen")
		for control in [table._settings_button, table.action_bar]:
			_expect(screen_rect.encloses(_physical_rect(control)), "Landscape controls must remain inside the physical screen")
		if rendering:
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png("res://docs/android_table_%dx%d.png" % [dimensions.x, dimensions.y]) == OK)
	_test_result()
	var settlement = table._settlement_animation_controller
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1080, 1920), Vector2i(2400, 1080), Vector2i(1280, 800)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var screen_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		_expect(settlement.is_completed() and settlement.boards.size() == 4, "Rotation preserves the completed tabletop settlement")
		var rows: Array[Rect2] = []
		for seat in 4:
			var row: Control = settlement.boards[seat]
			var rect := _control_rect(row)
			_expect(row.is_visible_in_tree() and screen_rect.grow(0.01).encloses(_physical_rect(row)), "Each tabletop board must fit the physical screen")
			for index in 3:
				var amount: Label = settlement.payment_labels[seat][index]
				var direction: Label = amount.get_parent().get_node("Direction")
				_expect(direction.text == ["上", "对", "下"][index], "Resizing preserves each seat's relative payment directions")
				for label in [direction, amount]:
					_expect(rect.grow(0.01).encloses(_control_rect(label)), "Payment directions and amounts fit their tabletop board")
					_expect(TileView._font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x, "Tabletop payment text fits without clipping")
			for other in rows:
				_expect(not rect.intersects(other), "Tabletop boards must not overlap after rotation")
			rows.append(rect)
		var next: Button = table._next_round_button
		_expect(next.is_visible_in_tree() and screen_rect.encloses(_physical_rect(next)), "The bottom next-round button must remain fully visible")
		for rect in rows:
			_expect(not rect.intersects(_control_rect(next)), "Bottom next-round control never covers tabletop payments")
		_expect(screen_rect.encloses(_physical_rect(settlement._flip_view)), "The tabletop flipped chicken remains inside the physical screen")
		if rendering:
			await RenderingServer.frame_post_draw
			_expect(root.get_texture().get_image().save_png("res://docs/android_result_%dx%d.png" % [dimensions.x, dimensions.y]) == OK)
	root.size = Vector2i(1080, 1920)
	await process_frame
	await process_frame
	_expect(settlement.current_pairs == table.round.last_result.pairwise and table._settlement_card._post_controls.visible, "Rotation retains final payments and bottom controls")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 1520)
	await process_frame
	await process_frame
	print("[layout] Android canvas scaling, landscape controls and tabletop settlement rotation passed")

func _test_current_scores() -> void:
	_new_fixture()
	var scores := [-240.0, 1040.0, 0.0, 200.0]
	table.round.apply_scores(scores)
	for viewpoint in 4:
		table.human_seat = viewpoint
		table._refresh()
		await process_frame
		for seat in 4:
			var label: Label = table.center_labels[seat]
			_expect(label.visible and label.text.contains("%.0f分" % scores[seat]), "All viewpoints show each seat's current cumulative score")
			for line in label.text.split("\n"):
				_expect(TileView._font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x, "Positive and negative current scores fit labels")
			_expect(not table._status_labels[seat].visible, "Current scores don't expose table settlement text")
	table.human_seat = 0
	table._refresh()

func _expect(condition: bool, message: String = "Table assertion failed") -> void:
	if not condition:
		failed = true
		push_error(message)
