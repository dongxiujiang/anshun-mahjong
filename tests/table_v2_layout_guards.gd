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

func _fixture(hand_count: int = 13) -> RoundState:
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
	var seats: Array = []
	for seat in 4:
		var capacity := G.river_capacity(G.relative_seat(deck.human_seat, seat))
		var cards := []
		for i in capacity:
			cards.append("tiao1" if i % 3 == 0 else "wan2")
		var charges := []
		charges.resize(capacity)
		charges.fill(false)
		seats.append({"seat": seat, "discards": cards, "discard_ids": range(capacity),
			"discard_charge": charges})
	deck.snapshot = {"seats": seats}
	deck._clear(deck._red_layer)
	deck._clear(deck._discard_layer)
	deck._build_discards()
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
	deck.set_round(_fixture(13), 1)
	deck.refresh()
	var label_before: Array[Vector2] = []
	var name_before: Array[Vector2] = []
	var red_before: Array[Vector2] = []
	var meld_before: Array[Vector2] = []
	for seat in 4:
		label_before.append(deck._labels[seat].position)
		name_before.append(deck._name_labels[seat].position)
		red_before.append(_first_position(deck._red_layer, seat))
		meld_before.append(_first_position(deck._meld_layer, seat))
	deck.set_round(_fixture(3), 1)
	deck.refresh()
	for seat in 4:
		t.expect(deck._labels[seat].position == label_before[seat],
			"seat%d: 手牌缩短后分数锚点不变" % seat)
		t.expect(deck._name_labels[seat].position == name_before[seat],
			"seat%d: 手牌缩短后昵称锚点不变" % seat)
		t.expect(_first_position(deck._red_layer, seat) == red_before[seat],
			"seat%d: 手牌缩短后红色区锚点不变" % seat)
		t.expect(_first_position(deck._meld_layer, seat) == meld_before[seat],
			"seat%d: 手牌缩短后碰杠区锚点不变" % seat)

func _test_meld_clearance(deck) -> void:
	deck.set_round(_fixture(), 1)
	deck.refresh()
	for seat in 4:
		var hand_rect := G.hand13_rect(seat, deck.human_seat)
		var hand_clearance := true
		for rect in _seat_tiles(deck._red_layer, seat) + _seat_tiles(deck._meld_layer, seat):
			if rect.intersects(hand_rect.grow(-0.5)):
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
		player.name_label = "玩家名字需要在语音图标前截断"
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
			var icon: TextureRect = voice.get_node("SpeakerIcon")
			var score: Label = deck._labels[seat]
			var nickname: Label = deck._name_labels[seat]
			t.expect(G.TABLE_BOUNDS.encloses(voice.get_rect()), "whole voice control stays inside the table")
			t.expect(voice.get_rect().encloses(score.get_rect()) and voice.get_rect().encloses(nickname.get_rect()),
				"name and score both lie inside the same touch target")
			t.expect(icon.size.x < deck._dealer_meld_badges[seat].size.x and not _rect(icon).intersects(_rect(nickname))
				and not _rect(icon).intersects(_rect(score)), "speaker icon is smaller than the dealer badge and clears the text")
			for other in 4:
				t.expect(not voice.get_rect().intersects(G.hand13_rect(other, deck.human_seat)), "voice control does not intercept the hand")
			var closed_icon := icon.texture
			if seat != mock.human_seat:
				mock.remote_microphones[seat] = true
				deck.refresh_voice_control(seat)
				t.expect(icon.texture != closed_icon, "remote microphone must be on before the icon shows sound")
			var original_icon := icon.texture
			var original_mic := mock.microphone
			var original_speaker: bool = mock.speakers[seat]
			_click(nickname)
			t.expect(icon.texture != original_icon, "clicking a name changes its speaker icon")
			t.expect(mock.microphone == (not original_mic if seat == 1 else original_mic)
				and mock.speakers[seat] == (not original_speaker if seat != 1 else original_speaker),
				"own click changes the microphone, remote click changes only that player's playback")
			_click(score)
			t.expect(icon.texture == original_icon, "clicking the score toggles the same voice control back")
			if seat != mock.human_seat:
				mock.remote_microphones[seat] = false
				deck.refresh_voice_control(seat)
				t.expect(icon.texture == closed_icon, "remote microphone off returns the icon to mute")
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
