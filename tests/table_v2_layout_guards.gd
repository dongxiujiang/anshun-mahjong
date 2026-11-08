extends SceneTree
## V2 布局守卫：红色区上限、短手牌固定锚点、鸡牌碰杠与普通碰杠避让。

const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class VoiceTable extends Control:
	func _net_mode(): return "online"
	func _remote_voice_enabled(_seat): return true
	func _toggle_remote_voice(_seat): pass

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
	var timeline: Array = []
	for i in 30:
		timeline.append({"kind": "ordinary", "tile": "tiao1", "order": i})
	var seats: Array = []
	for seat in 4:
		seats.append({
			"seat": seat,
			"discards": [],
			"discard_charge": [],
			"red_timeline": timeline.duplicate(true),
			"melds": [],
		})
	deck.snapshot = {"seats": seats}
	deck._clear(deck._red_layer)
	deck._build_red()
	for seat in 4:
		var rects := _seat_tiles(deck._red_layer, seat)
		t.expect(rects.size() == 24, "seat%d: 红色区超过24张时只显示24张" % seat)
		var in_bounds := true
		for rect in rects:
			if not G.TABLE_BOUNDS.grow(-1.0).encloses(rect):
				in_bounds = false
		t.expect(in_bounds, "seat%d: 24张红牌不越出牌桌安全边界" % seat)

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
		t.expect(_first_position(deck._red_layer, seat) == before[seat],
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
	var dealer_name: Label = deck._name_labels[r.dealer_seat]
	var badge: Label = deck._badges[r.dealer_seat]
	t.expect(badge.position.x > dealer_name.position.x + dealer_name.size.x
		and badge.position.y < dealer_name.position.y + dealer_name.size.y, "dealer badge sits beside the name")

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
	_test_voice_hud_bounds(deck)
	_test_new_round_reset(deck)
	deck.queue_free()
	await process_frame
	quit(t.finish("table_v2_layout_guards"))

func _test_voice_hud_bounds(deck) -> void:
	var mock := VoiceTable.new()
	root.add_child(mock)
	deck.table = mock
	deck.round = _fixture()
	deck.human_seat = 1
	deck.snapshot = {"turn": 0}
	var seats := []
	for seat in 4:
		seats.append({"seat": seat, "ready": false, "is_dealer": false,
			"name": "玩家", "score": 200, "is_human": true})
	deck._clear(deck._label_layer)
	deck._build_labels(seats)
	var remote := 0 # relative seat 1, at the bottom right
	var voice: Button = deck._voice_buttons[remote]
	var score: Label = deck._labels[remote]
	t.expect(G.TABLE_BOUNDS.encloses(Rect2(voice.position, voice.size)), "remote speaker button stays inside the table")
	t.expect(not Rect2(voice.position, voice.size).intersects(Rect2(score.position, score.size)), "remote speaker does not cover the score")
	for seat in 4:
		t.expect(not Rect2(voice.position, voice.size).intersects(G.hand13_rect(seat, deck.human_seat)), "remote speaker avoids seat %d hand" % seat)
	deck.table = null
	mock.queue_free()
