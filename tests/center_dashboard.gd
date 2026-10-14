extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var table
var rendering := false
var directory := "res://build/ui_review/center_dashboard"

func _initialize() -> void: call_deferred("_run")

func _shot(name: String) -> void:
	if not rendering: return
	await create_timer(0.28).timeout
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	screenshot.save_png(directory.path_join(name + ".png"))
	if name.begins_with("02_online_side"):
		var side: int = table._table_layout.turn_indicator.active_side
		var rect: Rect2 = table._table_layout.center_rect()
		for fraction in [0.25, 0.75]:
			var point: Vector2 = [Vector2(rect.position.x+rect.size.x*fraction,rect.end.y), Vector2(rect.end.x,rect.position.y+rect.size.y*fraction), Vector2(rect.position.x+rect.size.x*fraction,rect.position.y), Vector2(rect.position.x,rect.position.y+rect.size.y*fraction)][side]
			var outward: Vector2 = [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT][side]
			var samples: Array[Color] = []
			for distance in [0.0, 6.0, 24.0]:
				var pixel: Vector2 = table.surface.get_global_transform() * (point + outward*distance)
				samples.append(screenshot.get_pixelv(Vector2i(pixel)))
			t.expect(samples[0].r > samples[2].r + 0.15, "Both halves of the active edge render a bright yellow rim")
			t.expect(samples[1].r > samples[2].r + 0.025, "Soft light spreads outside both halves of the active edge")

func _check_positions() -> void:
	var center: Vector2 = table._table_layout.center_rect().get_center()
	var areas = table._player_tile_areas
	for seat in 4:
		var score: Label = table.center_labels[seat]
		var relative: int = table._relative_seat(seat)
		var midpoint := score.get_rect().get_center()
		t.expect(is_equal_approx(midpoint.x, center.x) if relative % 2 == 0 else is_equal_approx(midpoint.y, center.y), "Scores align with the square's horizontal/vertical center on every viewpoint")
		t.expect(score.text == "%.0f分" % table.round.players[seat].score, "Score text contains only the player's cumulative score")
		t.expect(not table.avatars[seat].visible and not table.wind_labels[seat].visible, "No compass/relative-seat labels remain visible")
		var badge: Label = areas.dealer_badges[seat]
		t.expect(badge.visible == table.round.players[seat].is_dealer, "Only the dealer has a badge")
		if badge.visible:
			t.expect(is_equal_approx(badge.get_rect().get_center().y, midpoint.y), "Dealer badge is vertically centered next to the score")
		if areas.name_labels[seat].visible:
			t.expect(is_equal_approx(areas.name_labels[seat].get_rect().get_center().x, midpoint.x) and areas.name_labels[seat].get_rect().end.y <= score.position.y + 2, "Name stays centered above the score without overlap")

func _run() -> void:
	rendering = DisplayServer.get_name() != "headless"
	if rendering:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1280,720)
	root.get_node("UpdateManager").auto_check = false
	var network = root.get_node("Network")
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null,null,null,null]
	while table.round.phase == RoundState.Phase.DEALING or table._table_animation_controller.input_locked(): await process_frame
	await process_frame
	var game: RoundState = table.round
	game.apply_scores([224.0,-24.0,1040.0,0.0])
	for viewer in 4:
		table.human_seat = viewer
		for turn in 4:
			game.current_turn = turn
			table._refresh()
			t.expect(table._table_layout.turn_indicator.active_side == posmod(turn-viewer,4), "Active light follows the current player relative to the local viewer")
		_check_positions()
		for name in table._player_tile_areas.name_labels.values(): t.expect(not name.visible, "Single-player dashboard displays scores only")
	table.human_seat = 0
	game.current_turn = 0
	table._refresh()
	await _shot("01_single_bottom")
	# Names and human/AI flags are the same data received through network snapshots.
	game.players[0].name_label = "小秀"
	game.players[1].name_label = "人机2"
	game.players[2].name_label = "长昵称测试玩家不能盖住庄家或者分数"
	game.players[3].name_label = "阿明"
	for seat in 4: game.players[seat].is_human = seat != 1
	var wire := game.serialize_for_seat(0)
	var client := RoundState.new()
	client.apply_sync(wire)
	network.mode = "client"
	network.net_node.game = client
	network.net_node.my_seat = 0
	network.net_node.round_number = 1
	table.round = client
	for turn in 4:
		client.current_turn = turn
		table._refresh()
		_check_positions()
		for seat in 4:
			var nickname: Label = table._player_tile_areas.name_labels[seat]
			t.expect(nickname.text == ("人机" if seat == 1 else game.players[seat].name_label), "Online humans show their entered names; all AI names are simply 人机")
		await _shot("02_online_side%d" % turn)
	client.phase = RoundState.Phase.PLAYING
	client.last_discard = {"seat": 1, "tile":"wan1"}
	client._response_stage = RoundState.ResponseStage.WIN
	client._awaiting_response = {"seat": 2, "disc_seat": 1, "tile":"wan1", "stage": RoundState.ResponseStage.WIN}
	var logical_turn_before_response: int = client.current_turn
	table._refresh_center()
	t.expect(table._table_layout.turn_indicator.active_side == table._relative_seat(posmod(1 + GameConfig.TURN_DIRECTION, 4)), "Response window lights the theoretical next discarder")
	var response_side: int = table._table_layout.turn_indicator.active_side
	client._awaiting_response.seat = 3
	table._refresh_center()
	t.expect(table._table_layout.turn_indicator.active_side == response_side, "Response light does not reveal which seat has an option")
	t.expect(client.current_turn == logical_turn_before_response, "Response light does not change the logical turn")
	client._awaiting_response.clear()
	client._response_stage = RoundState.ResponseStage.NONE
	client.phase = RoundState.Phase.DEALING
	table._refresh_center()
	t.expect(table._table_layout.turn_indicator.active_side == -1, "Dealing has no active-discard light")
	client.phase = RoundState.Phase.SETTLED
	table._refresh_center()
	t.expect(table._table_layout.turn_indicator.active_side == -1, "Settlement extinguishes every edge")
	client.phase = RoundState.Phase.PLAYING
	for dimensions in [Vector2i(960,540),Vector2i(2400,1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		table._refresh()
		_check_positions()
		await _shot("03_online_%dx%d" % [dimensions.x,dimensions.y])
	network.mode = ""
	table.round = game
	table.queue_free()
	await process_frame
	quit(t.finish("center_dashboard"))
