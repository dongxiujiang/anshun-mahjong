extends SceneTree
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const PLAN = preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
var t = H.new()

class Host extends Control:
	var round: RoundState
	var human_seat = 1
	var _table_animation_controller = null
	var _settlement_card = null
	func _net_mode(): return ""

func _initialize(): call_deferred("_run")

func _capture(view, name: String):
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/ui-feedback"))
	root.get_texture().get_image().save_png("res://build/ui-feedback/" + name + ".png")

func _round():
	var r = RoundState.new()
	r.build_players(1)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	for player in r.players:
		player.concealed = ["wan1","wan1","wan2","wan3","wan4","tiao2","tiao3","tiao4","tong3","tong4","tong5","tong7","tong7"]
	return r

func _settlement_round():
	var r = _round()
	var bag: Array = []
	for card in Tiles.all_values():
		for copy in 4: bag.append(card)
	r.players[1].score = 199
	r.players[2].score = 201
	r.players[3].concealed = ["wan1","wan1","wan2","wan2","wan4","wan4","tiao2","tiao2","tiao5","tiao5","tong3","tong3","tong7","tong7"]
	for seat in [1,3]:
		for card in r.players[seat].concealed:
			t.expect(card in bag, "fixture uses no more than four copies of a tile")
			bag.erase(card)
	bag.erase("tong8")
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261109
	for seat in [0,2]:
		var hand: Array = []
		for attempt in 100:
			var available = bag.duplicate()
			hand = []
			for i in 13: hand.append(available.pop_at(rng.randi_range(0,available.size()-1)))
			if not RuleEngine.is_tenpai(hand,[]): break
		t.expect(not RuleEngine.is_tenpai(hand,[]), "fixture has a genuine uncalled player")
		r.players[seat].concealed = hand
		for card in hand: bag.erase(card)
	var used: Array = []
	for player in r.players: used.append_array(player.concealed)
	r.wall = WallRing.new(used + ["tong8"] + bag)
	r.wall.set_head(0)
	for i in used.size(): r.wall.draw_head()
	t.expect(used.size()+r.wall.remaining == 108, "visible hands and remaining wall form one physical deck")
	r.current_turn = 3
	r.players[3].ready = true
	r.players[3].just_drew = "tong7"
	r.round_meta = {"winner":3,"winners":[3],"self_draw":true,"discard_seat":-1,"win_tile":"tong7", "flip_tile":"tong8","flip_wall_index":r.wall.peek_head_index(),"chicken_multiplier":1}
	return r

func _ready_borders(view):
	var authority = _settlement_round()
	authority.players[3].ready = true
	for viewer in 4:
		var client = RoundState.new()
		client.apply_sync(authority.serialize_for_seat(viewer))
		view.set_round(client, viewer)
		for seat in 4:
			var cards = view.hand_boxes[seat].get_children()
			t.expect(cards.size() == 13, "all seats retain every hand tile")
			for tile in cards:
				t.expect(tile.get("ready_locked") == (seat == 3), "ready gold border reaches viewer %d seat %d" % [viewer,seat])
				t.expect(tile.face_up == (seat == viewer), "gold border does not reveal opponents' concealed faces")
		if viewer == 1: await _capture(view,"02-ready-opponent-backs")
		var retained = view.hand_boxes[3].get_child(0)
		authority.players[3].ready = false
		client.apply_sync(authority.serialize_for_seat(viewer))
		view.refresh()
		t.expect(view.hand_boxes[3].get_child(0) == retained and retained.get("ready_locked") == false, "snapshot clears the border without rebuilding the tile")
		authority.players[3].ready = true
	var old_draw = authority.players[3].just_drew
	authority.players[3].concealed.erase(old_draw)
	authority.players[3].discards.append(old_draw)
	authority.players[3].discard_ids.append(0)
	var replacement = authority.wall.draw_head()
	authority.players[3].just_drew = replacement
	authority.players[3].concealed.append(replacement)
	view.set_round(authority,3)
	var drawn = view.draw_boxes[3].get_child(0)
	t.expect(drawn.get("ready_locked") == true and drawn.interactive, "ready draw shows the status without blocking the legal discard")
	var pooled = view._tile_pool.acquire()
	pooled.set("ready_locked",true)
	view._tile_pool.release(pooled)
	pooled = view._tile_pool.acquire()
	t.expect(pooled.get("ready_locked") == false, "pooled tile never leaks a ready border into the next round")
	view._tile_pool.release(pooled)

func _buttons(view):
	var r = _round()
	view.set_round(r,1)
	var bar = Control.new()
	view.add_child(bar)
	view.adopt_action_bar(bar)
	var wall = TileView.new()
	wall.face_up = false
	wall.z_index = 2
	view._wall_layer.add_child(wall)
	var button = Button.new()
	button.text = "碰"
	button.size = Vector2(177,112)
	bar.add_child(button)
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#eacf83")
	button.add_theme_stylebox_override("normal",style)
	bar.position = Vector2(1100,900)
	wall.position = bar.position
	wall.set_unit(2.0)
	t.expect(view._action_layer.z_index > wall.z_index + view._wall_layer.z_index, "action buttons render over overlapping wall tiles")
	t.expect(view._action_layer.z_index > view._deal_layer.z_index, "action buttons render above flying tiles too")
	t.expect(view._action_layer.z_index < view._settlement_layer.z_index, "settlement still covers the in-game controls")
	if DisplayServer.get_name() != "headless":
		await _capture(view,"01-buttons-over-wall")
		var image = root.get_texture().get_image()
		var at = button.get_global_transform_with_canvas() * Vector2(20,20)
		at *= Vector2(image.get_size()) / root.get_visible_rect().size
		var pixel = image.get_pixelv(Vector2i(at))
		t.expect(pixel.r > 0.75 and pixel.g > 0.6 and pixel.b < 0.7, "rendered action surface stays visible over the wall")
	view._wall_layer.remove_child(wall)
	wall.queue_free()
	bar.queue_free()

func _settlement(view):
	var host = Host.new()
	root.add_child(host)
	host.round = _settlement_round()
	var r = host.round
	view.table = host
	view.set_round(r,1)
	var original_scores = []
	for score in view._labels: original_scores.append(Rect2(score.position,score.size))
	var scored = ScoringEngine.settle(r)
	t.expect(scored.called[1] and RuleEngine.is_tenpai(r.players[1].concealed,[]), "the preview's own listening hand is marked called by the real scoring engine")
	r.last_result = scored.duplicate(true)
	# 标题单测替换条目；截图前恢复规则引擎的真实结果。
	r.players[3].ready = false
	view._settlement_plan = PLAN.build(r.last_result,r.round_meta,r.players,1)
	t.expect(view._settlement_result_title() == "对家自摸-小七对", "winning pattern is appended once to the self draw outcome")
	r.players[3].ready = true
	t.expect(view._settlement_result_title() == "对家报听自摸-小七对", "ready and pattern both appear in the result title")
	for label in ["大对子","清一色","龙七对","清龙对"]:
		r.last_result.items[3] = [{"kind":"pattern","label":label,"amount":24.0}]
		t.expect(view._settlement_result_title().ends_with("-" + ("清龙七对" if label == "清龙对" else label)), "all recorded winning patterns appear")
	r.last_result.items[3] = []
	t.expect(view._settlement_result_title() == "对家报听自摸", "plain win does not fabricate a pattern")
	r.last_result.items[3] = [{"kind":"pattern","label":"小七对","amount":24.0}]
	r.round_meta.self_draw = false
	r.round_meta.discard_seat = 0
	t.expect(view._settlement_result_title() == "对家报听胡下家-小七对", "discard win keeps source, ready and pattern")
	r.round_meta.self_draw = true
	r.round_meta.discard_seat = -1
	r.last_result = scored.duplicate(true)
	r.last_result.erase("called") # 正式联机结果通过 status 传递叫牌判定。
	for seat in 4: r.players[seat].score += scored.deltas[seat]
	r.phase = RoundState.Phase.SETTLED
	view.refresh()
	view.start_native_settlement(true)
	for seat in 4:
		var badge = view._native_settlement.get_node_or_null("CalledStatus%d" % seat)
		t.expect((badge != null) == bool(scored.called[seat]), "only called seats show the green called badge")
		if badge != null: t.expect(badge.get_theme_stylebox("normal").bg_color == Color("#30784e"), "called badge stays green")
		var score = view._labels[seat]
		t.expect(not score.has_theme_stylebox_override("normal"), "player score text has no background or border")
		var delta = score.get_meta("round_delta", null)
		t.expect(delta != null and delta.visible, "settlement shows each seat's round delta")
		if delta == null: continue
		var expected = str(int(r.last_result.deltas[seat]))
		if r.last_result.deltas[seat] > 0: expected = "+" + expected
		t.expect(delta.text == expected, "round delta is the signed ledger total, including zero")
		t.expect(Rect2(score.position,score.size) == original_scores[seat], "settlement never shifts or shrinks the original score area")
		var ink_right = score.position.x + (score.size.x + view._hud_text_width(score.text,score.get_theme_font_size("font_size"))) / 2.0
		t.expect(delta.position.x >= ink_right + 4 or delta.position.y >= score.position.y + score.size.y, "delta avoids the running score text")
		var bounds = G.seat_hud_rect(G.relative_seat(1,seat))
		t.expect(bounds.encloses(Rect2(delta.position,delta.size)), "delta stays inside the reserved seat corner")
		t.expect(score.tooltip_text.ends_with("分"), "running total remains separate from the round delta")
	await _capture(view,"03-settlement-pattern-deltas")
	if DisplayServer.get_name() != "headless":
		var image = root.get_texture().get_image()
		var stretch = Vector2(image.get_size()) / root.get_visible_rect().size
		for seat in [1,2,3]:
			var delta = view._labels[seat].get_meta("round_delta")
			var bounds = Rect2i(delta.get_global_rect().position * stretch, delta.size * stretch)
			var ink = 0
			for y in range(bounds.position.y,bounds.end.y):
				for x in range(bounds.position.x,bounds.end.x):
					var pixel = image.get_pixel(x,y)
					if r.last_result.deltas[seat] < 0:
						if pixel.r > 0.5 and pixel.r > pixel.g * 1.3: ink += 1
					elif pixel.g > 0.5 and pixel.g > pixel.r * 1.3: ink += 1
			t.expect(ink > 3, "round delta digits really render in the reserved corner")

	for viewer in 4:
		var client = RoundState.new()
		client.apply_sync(r.serialize_for_seat(viewer))
		host.round = client
		host.human_seat = viewer
		view.set_round(client,viewer)
		view.start_native_settlement(true)
		for seat in 4:
			t.expect((view._native_settlement.get_node_or_null("CalledStatus%d" % seat) != null) == bool(scored.called[seat]), "all network viewers show the authoritative called badges")
			t.expect(view._labels[seat].get_meta("round_delta").text == view._settlement_signed(scored.deltas[seat]), "all network viewers show the same round totals")
	var next = _round()
	host.human_seat = 1
	host.round = next
	view.set_round(next,1)
	t.expect(not view._labels[1].has_meta("round_delta"), "next round clears the previous round delta")
	view.table = null
	host.queue_free()

func _run():
	root.size = Vector2i(1280,720)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	await process_frame
	await _buttons(view)
	await _ready_borders(view)
	await _settlement(view)
	view.queue_free()
	await H.quit_cleanly(self,t.finish("table_v2_feedback"))
