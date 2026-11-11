extends SceneTree
## V2 布局守卫：红色区上限、短手牌固定锚点、鸡牌碰杠与普通碰杠避让。

const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class VoiceTable extends Control:
	var round: RoundState
	var human_seat := 1
	var _table_animation_controller = null
	var mode := "online"
	var microphone := false
	var speakers := [true, true, true, true]
	var remote_microphones := [false, false, false, false]
	func _net_mode(): return mode
	func _can_toggle_voice_chat(): return true
	func _local_voice_enabled(): return microphone
	func _toggle_voice_chat(): microphone = not microphone
	func _remote_voice_enabled(seat): return speakers[seat]
	func _remote_microphone_on(seat): return remote_microphones[seat]
	func _toggle_remote_voice(seat): speakers[seat] = not speakers[seat]

func _initialize() -> void:
	call_deferred("_run")

func _fixture(hand_count: int = 1) -> RoundState:
	var round := RoundState.new()
	round.set_rng_seed(20261105)
	round.build_players(1)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	round.current_turn = 1
	var hand := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7",
		"wan8", "wan9", "tiao2", "tiao3", "tong2", "tong3"]
	for seat in 4:
		round.players[seat].concealed = hand.slice(0, hand_count)
		round.players[seat].discards = []
		round.players[seat].discard_ids = []
		round.players[seat].discard_count = 0
		round.players[seat].melds = [
			{"kind": "pung", "tile": "tiao1", "from_seat": (seat + 1) % 4,
				"formed_at": 1, "concealed": false, "revealed": true},
			{"kind": "kong", "tile": "tong8", "from_seat": seat,
				"formed_at": 2, "concealed": false, "revealed": true},
			{"kind": "pung", "tile": "wan6", "from_seat": (seat + 2) % 4,
				"formed_at": 3, "concealed": false, "revealed": true},
			{"kind": "kong", "tile": "wan4", "from_seat": seat,
				"formed_at": 4, "concealed": false, "revealed": true},
		]
	return round

func _rect(node: Control) -> Rect2:
	var xf := node.get_global_transform()
	var points := [xf * Vector2.ZERO, xf * Vector2(node.size.x, 0),
		xf * node.size, xf * Vector2(0, node.size.y)]
	return Rect2(points[0], Vector2.ZERO).expand(points[1]).expand(points[2]).expand(points[3])

func _seat_tiles(layer: Control, seat: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for child in layer.get_children():
		if child is Control and int(child.get_meta("v2_seat", -1)) == seat:
			out.append(_rect(child))
	return out

func _test_red_cap(deck) -> void:
	var r := _fixture(13)
	for seat in 4:
		var player = r.players[seat]
		player.melds.clear()
		player.discards = ["tiao1", "tong8"]
		for i in 22: player.discards.append("wan2")
		player.discard_ids = range(24)
	deck.set_round(r, 1)
	deck.refresh()
	for seat in 4:
		var rects := _seat_tiles(deck._red_layer, seat) + _seat_tiles(deck._discard_layer, seat)
		t.expect(rects.size() == G.river_capacity(G.relative_seat(deck.human_seat, seat)),
			"seat%d: full mixed river keeps every tile" % seat)
		var clear := true
		for i in rects.size():
			clear = clear and G.TABLE_BOUNDS.encloses(rects[i])
			for j in range(i):
				clear = clear and not rects[i].intersects(rects[j].grow(-0.05))
		t.expect(clear, "seat%d: mixed chicken and ordinary slots stay clear" % seat)

func _test_short_hand_anchor(deck) -> void:
	# Real shuffled game: reaching four melds leaves one hand tile and a kong draw.
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/meld_layout_replay.json"))
	var r := RoundState.new()
	r.set_rng_seed(int(record.seed))
	r.next_dealer_seat = int(record.dealer)
	r.controllers = [null, null, null, null]
	r.pause_after_opening = true
	r.start_round(1, int(record.red), int(record.white))
	r.resume_after_opening()
	for action in record.actions:
		var accepted: bool = r.submit_turn(int(action.seat), action.decision) if action.kind == "turn" else r.submit_response(int(action.seat), str(action.tile), action.decision)
		t.expect(accepted, "layout regression replays only legal game actions")
	t.expect(r.players[0].melds.size() == 4 and r.players[0].concealed.size() == 2,
		"fourth meld regression contains a real single hand tile and replacement draw")
	for viewer in 4:
		deck.set_round(r, viewer)
		deck.refresh()
		var positions := []
		for seat in 4:
			positions.append([deck._labels[seat].position, deck._name_labels[seat].position,
				_first_position(deck._red_layer, seat), _first_position(deck._meld_layer, seat)])
		deck.refresh()
		for seat in 4:
			t.expect(positions[seat] == [deck._labels[seat].position, deck._name_labels[seat].position,
				_first_position(deck._red_layer, seat), _first_position(deck._meld_layer, seat)],
				"same legal state keeps names, scores, chickens and melds stable for every viewer")

func _test_meld_clearance(deck) -> void:
	deck.set_round(_fixture(), 1)
	deck.refresh()
	for seat in 4:
		var hand_rects := _seat_tiles(deck.hand_boxes[seat], seat)
		var hand_clearance := true
		for rect in _seat_tiles(deck._red_layer, seat) + _seat_tiles(deck._meld_layer, seat):
			if hand_rects.any(func(hand): return rect.intersects(hand.grow(-0.5))):
				hand_clearance = false
		t.expect(hand_clearance, "seat%d: 鸡牌与普通碰杠不压固定手牌区" % seat)
		var overlap := false
		for red in _seat_tiles(deck._red_layer, seat):
			for meld in _seat_tiles(deck._meld_layer, seat):
				if red.intersects(meld.grow(-0.5)):
					overlap = true
		t.expect(not overlap, "seat%d: 鸡牌碰杠与普通碰杠不互相遮挡" % seat)

func _test_scaled_layout(deck) -> void:
	deck.set_round(_fixture(), 1)
	deck.refresh()
	var before: Array[Vector2] = []
	for seat in 4:
		before.append(_first_position(deck._red_layer, seat))
	deck.scale = Vector2(1.25, 0.78)
	deck.refresh()
	for seat in 4:
		t.expect(_first_position(deck._red_layer, seat).is_equal_approx(before[seat]),
			"seat%d: Android 非等比缩放下红牌本地落点不变" % seat)
	deck.scale = Vector2.ONE

func _test_hud_clearance(deck) -> void:
	var r := _fixture()
	r.players[1].concealed.append("wan2")
	r.players[1].just_drew = "wan2"
	for player in r.players:
		player.is_human = true
		player.name_label = "一段很长的玩家昵称应当单行省略"
		player.ready = true
		player.score = -1234567.0
	deck.set_round(r, 1)
	deck.refresh()
	var tiles: Array[Rect2] = []
	for layer in deck.hand_boxes + deck.draw_boxes + [deck._red_layer, deck._meld_layer, deck._wall_layer]:
		for node in layer.get_children():
			tiles.append(_rect(node))
	var occupied: Array[Rect2] = []
	var clear := true
	for node in deck._label_layer.get_children():
		var rect := _rect(node)
		for other in occupied + tiles:
			if rect.intersects(other):
				clear = false
		occupied.append(rect)
	t.expect(clear, "long names, large scores, ready badges and dealer badge avoid every visible tile and one another")
	var badge: Label = deck._dealer_meld_badges[r.dealer_seat]
	t.expect(badge.visible and not occupied.any(func(rect): return rect.intersects(_rect(badge))),
		"dealer badge is visible outside the name and score areas")

	var audio := root.get_node("AudioManager")
	var old_packs: Array = audio.seat_voice_packs.duplicate()
	for seat in [0, 2, 3]:
		r.players[seat].is_human = false
		audio.set_seat_voice_pack(seat, "luoxiaohei", false)
	deck.refresh()
	var names := {}
	for seat in [0, 2, 3]:
		names[deck._name_labels[seat].text] = true
	t.expect(names.size() == 3 and names.has("罗小黑") and names.has("罗小黑 3"), "duplicate voice packs get distinct AI names")
	audio.set_seat_voice_pack(2, "wangye", false)
	await process_frame
	t.expect(deck._name_labels[2].text == "王也", "changing a seat voice refreshes its visible name")
	for seat in 4:
		audio.set_seat_voice_pack(seat, old_packs[seat], false)

func _test_new_round_reset(deck) -> void:
	deck.set_round(_fixture(), 1)
	deck._sort_started = true
	deck._sort_animating = true
	deck._draw_flights[1] = {}
	deck._pending_draws[1] = "wan9"
	deck._frozen_hands = [["wan1"]]
	deck.set_round(_fixture(), 1)
	t.expect(not deck._sort_started and not deck._sort_animating,
		"新一局重置理牌运行态")
	t.expect(deck._draw_flights.is_empty(),
		"新一局重置摸牌隐藏状态")
	t.expect(deck._pending_draws.values().all(func(value): return str(value) == ""),
		"新一局清空上一局待处理摸牌")
	t.expect(deck._frozen_hands.is_empty(), "新一局清空上一局理牌快照")

func _first_position(layer: Control, seat: int) -> Vector2:
	for child in layer.get_children():
		if child is Control and int(child.get_meta("v2_seat", -1)) == seat:
			return child.position
	return Vector2(-99999.0, -99999.0)

func _run() -> void:
	var deck = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(deck)
	deck.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	deck.size = G.DESIGN_SIZE
	await process_frame
	_test_red_cap(deck)
	_test_short_hand_anchor(deck)
	_test_meld_clearance(deck)
	_test_scaled_layout(deck)
	await _test_hud_clearance(deck)
	await _test_voice_hud_bounds(deck)
	_test_new_round_reset(deck)
	deck.queue_free()
	await process_frame
	quit(t.finish("table_v2_layout_guards"))

func _test_voice_hud_bounds(deck) -> void:
	var mock := VoiceTable.new()
	root.add_child(mock)
	mock.round = _fixture()
	for seat in 4:
		var player: PlayerState = mock.round.players[seat]
		player.name_label = "玩家名字过长时需要截断"
		player.score = 200
		player.is_human = seat != 3
		player.melds.clear()
	mock.round.players[mock.round.dealer_seat].ready = true
	deck.set_table(mock)
	deck.set_round(mock.round, mock.human_seat)
	for mode in ["online", "lan"]:
		mock.mode = mode
		await process_frame
		t.expect(not deck._voice_buttons.has(3), "AI seats have no live voice control")
		for seat in [0, 1, 2]:
			var voice: Button = deck._voice_buttons[seat]
			t.expect(voice.get_node_or_null("SpeakerIcon") == null, "voice control has no speaker icon")
			var score: Label = deck._labels[seat]
			var nickname: Label = deck._name_labels[seat]
			t.expect(Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(voice.get_rect()), "whole voice control stays inside the screen")
			t.expect(voice.get_rect().encloses(score.get_rect()) and voice.get_rect().encloses(nickname.get_rect()),
				"name and score both lie inside the same touch target")
			t.expect(nickname.get_theme_color("font_color") == deck.UI.INK, "closed voice uses white name even on its turn")
			for other in 4:
				t.expect(not _seat_tiles(deck.hand_boxes[other], other).any(func(rect): return voice.get_rect().intersects(rect)), "voice control does not intercept the hand")
			var closed_color := nickname.get_theme_color("font_color")
			if seat != mock.human_seat:
				mock.remote_microphones[seat] = true
				deck.refresh_voice_control(seat)
				t.expect(nickname.get_theme_color("font_color") == deck.UI.GOLD, "remote microphone on makes the name yellow")
			var original_color := nickname.get_theme_color("font_color")
			var original_mic := mock.microphone
			var original_speaker: bool = mock.speakers[seat]
			_click(nickname)
			t.expect(nickname.get_theme_color("font_color") != original_color, "clicking a name changes its voice color")
			t.expect(mock.microphone == (not original_mic if seat == 1 else original_mic)
				and mock.speakers[seat] == (not original_speaker if seat != 1 else original_speaker),
				"own click changes the microphone, remote click changes only that player's playback")
			_click(score)
			t.expect(nickname.get_theme_color("font_color") == original_color, "clicking the score toggles the same voice control back")
			if seat != mock.human_seat:
				mock.remote_microphones[seat] = false
				deck.refresh_voice_control(seat)
				t.expect(nickname.get_theme_color("font_color") == closed_color, "remote microphone off returns name to white")
		var name_position: Vector2 = deck._name_labels[1].position
		for turn in 4:
			mock.round.current_turn = turn
			deck.refresh()
			t.expect(deck._name_labels[1].position == name_position, "turn changes do not move the name")
			for seat in 4:
				var marker = deck._label_layer.get_node_or_null("SeatTurn%d" % seat)
				t.expect((marker != null) == (seat == turn), "only the current player has a turn marker")
				t.expect(deck._name_labels[seat].get_theme_color("font_color") == deck.UI.INK, "turn alone never makes a name yellow")
				if marker != null:
					t.expect(marker.get_theme_color("font_color") == deck.UI.GOLD, "turn marker stays yellow")
					t.expect(not marker.get_rect().intersects(deck._name_labels[seat].get_rect()), "turn marker clears the name")
	if DisplayServer.get_name() != "headless":
		_click(deck._name_labels[2])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/seat-controls-online.png")
	var original_score: Rect2 = deck._labels[0].get_rect()
	deck.round.phase = RoundState.Phase.SETTLED
	deck.refresh()
	t.expect(deck._labels[0].get_rect() == original_score and deck._voice_buttons.has(0),
		"settlement keeps the same score anchor and voice control")
	deck.table = null
	mock.queue_free()

func _click(control: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_transform_with_canvas() * (control.size / 2.0)
		root.push_input(event, true)
