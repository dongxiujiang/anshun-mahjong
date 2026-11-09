extends SceneTree
## Run with a renderer for frame captures, or --headless for just the ledger assertions.
## -- --case=ID selects a case; captures go to build/settlement-scenarios/cases/ID/.
const H := preload("res://tests/test_harness.gd")
const PLAIN := ["wan1","wan2","wan3","wan4","wan5","wan6","tiao2","tiao3","tiao4","tong2","tong3","tong4","wan9","wan9"]
const FLUSH := ["wan1","wan2","wan3","wan2","wan3","wan4","wan4","wan5","wan6","wan6","wan7","wan8","wan9","wan9"]
const SEVEN := ["wan1","wan1","wan2","wan2","wan4","wan4","tiao2","tiao2","tiao5","tiao5","tong3","tong3","tong7","tong7"]
const DRAGON := ["wan1","wan1","wan1","wan2","wan2","tiao2","tiao2","tiao5","tiao5","tong3","tong3","tong7","tong7","wan1"]
const TRIPLETS_KONG := ["tiao2","tiao2","tiao2","tiao3","tiao3","tiao3","tong7","tong7","tong7","tong9","tong9"]
const OTHER_WAIT := ["tiao1","tiao2","tiao3","tiao4","tiao5","tiao6","tong4","tong5","tong6","tong7","tong8","tong9","wan9"]
const CASES := ["plain-self-draw", "ready-seven-pairs", "triplets-exposed-kong", "flush-ron", "dragon-seven-pairs-ron", "rob-added-kong", "kong-draw-last-four", "double-ron", "mixed-draw", "all-called-draw", "dry-pattern-ready"]
var _visual := false
var _case := ""
var _checks := 0
var _failures := 0
var _captures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_visual = DisplayServer.get_name() != "headless"
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): only = arg.trim_prefix("--case=")
	if only == "all": only = ""
	if only != "" and only not in CASES:
		printerr("Unknown case: ", only)
		quit(2)
		return
	root.get_node("UpdateManager").auto_check = false
	root.get_node("GameConfig").set_tile_animation_seconds(0.35, false)
	root.get_node("GameConfig").set_settlement_speed("0.45", false)
	root.get_node("GameConfig").set_score_details_enabled(true, false)
	if _visual:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1280, 720)
	for id: String in CASES:
		if only != "" and only != id: continue
		_case = id
		var failures_before := _failures
		await _run_case()
		print("[%s] %s" % ["ok" if failures_before == _failures else "fail", id])
	print("Settlement scenarios: %d checks, %d failures, %d screenshots" % [_checks, _failures, _captures])
	if _failures == 0:
		print("[table_v2_settlement_scenarios] passed (%d checks)" % _checks)
	await H.quit_cleanly(self, 0 if _failures == 0 else 1)

func _run_case() -> void:
	var table: Control
	var r: RoundState
	if _visual:
		table = load("res://scenes/GameTable.tscn").instantiate()
		table.human_seat = 3 if _case == "double-ron" else (1 if _case == "rob-added-kong" else 0)
		root.add_child(table)
		await process_frame
		r = table.round
		table._ai_service.stop()
		r.cancel_opening()
		table._table_animation_controller.cancel()
		table._new_areas.recover_after_resume()
	else:
		r = RoundState.new()
		r.build_players(0)
	r._reset_meta()
	if _case in ["ready-seven-pairs", "triplets-exposed-kong", "mixed-draw"]:
		r.round_meta.chicken_multiplier = 2
		r.round_meta.dice_double = _case != "mixed-draw"
		r.round_meta.previous_draw_double = _case != "ready-seven-pairs"
	r.cancel_ai()
	r.controllers = [null, null, null, null]
	var spec := _fixture(r)
	if not spec.is_empty():
		if _visual:
			table._refresh()
			await process_frame
			await _capture("00-before")
		_resolve(r, spec)
		if _check(r.phase == RoundState.Phase.SETTLED, "production round did not reach settlement"):
			_check_ledger(r, spec)
			if _visual:
				if _case == "plain-self-draw":
					table._new_areas._pending_draws[1] = "hidden0"
				table._refresh()
				await _check_animation(table, r, spec)
	if is_instance_valid(table):
		table.queue_free()
		await process_frame

func _fixture(r: RoundState) -> Dictionary:
	var hands := [[], [], [], []]
	var melds := [[], [], [], []]
	var discards := [[], [], [], []]
	var hand: Array = PLAIN.duplicate()
	var mode := "self"
	var flip := "tong9"
	var source := 1
	var ready := false
	var tail := ""
	var fees: Array = [] # payer, recipient, reason, amount per pair
	match _case:
		"plain-self-draw":
			hand[6] = "tiao1"
			hand[7] = "tiao2"
			hand[8] = "tiao3"
			hand[9] = "tiao1"
			hand[10] = "tiao2"
			hand[11] = "tiao3"
			for payer in [1, 2, 3]: fees.append([payer, 0, "自摸基础分", 4])
		"ready-seven-pairs":
			hand = SEVEN.duplicate()
			ready = true
			flip = "tong8"
			for payer in [1, 2, 3]:
				fees.append([payer, 0, "小七对", 24])
				fees.append([payer, 0, "报听胡牌", 20])
		"triplets-exposed-kong":
			hand = TRIPLETS_KONG.duplicate()
			mode = "ron"
			flip = "wan6"
			melds[0] = [{"kind":"kong", "tile":"wan5", "from_seat":2, "concealed":false}]
			fees = [[1, 0, "大对子", 14], [2, 0, "明杠", 4]]
		"flush-ron":
			hand = FLUSH.duplicate()
			mode = "ron"
			flip = "tiao6"
			fees = [[1, 0, "清一色", 24]]
		"dragon-seven-pairs-ron":
			hand = DRAGON.duplicate()
			mode = "ron"
			flip = "tong8"
			fees = [[1, 0, "龙七对", 44]]
		"rob-added-kong":
			mode = "rob"
			flip = "tong3"
			melds[1] = [{"kind":"pung", "tile":"tong5", "from_seat":2, "concealed":false}]
			# Four copies are required by the declared kong. Wait for the tile at
			# the end of a sequence, with no copy already in the winner's hand.
			hand.assign(["wan1","wan2","wan3","tiao2","tiao3","tiao4","tong3","tong4","wan7","wan8","wan9","tiao5","tiao5","tong5"])
			fees = [[1, 0, "抢杠胡基础分", 12]]
		"kong-draw-last-four":
			mode = "kong-self"
			flip = "tiao6"
			hand = TRIPLETS_KONG.slice(0, 10) + ["wan8", "wan8", "wan8", "wan8"]
			tail = "tong9"
			for payer in [1, 2, 3]:
				fees.append([payer, 0, "大对子", 14])
				fees.append([payer, 0, "杠开", 5])
				fees.append([payer, 0, "海底捞", 5])
				fees.append([payer, 0, "暗杠", 4])
		"double-ron":
			mode = "double"
			ready = true
			hands[2] = OTHER_WAIT.duplicate()
			fees = [[1, 0, "干扣", 14], [1, 0, "报听胡牌", 20], [1, 2, "报听胡牌", 24]]
		"mixed-draw", "all-called-draw":
			mode = "draw"
			flip = ""
			hand = FLUSH.duplicate()
			hands[2] = OTHER_WAIT.duplicate()
			if _case == "all-called-draw":
				hands[1] = ["tiao2","tiao3","tiao4","tiao5","tiao6","tiao7","tong1","tong2","tong3","tong5","tong6","tong7","wan9"]
				hands[3] = ["tiao1","tiao2","tiao3","tiao4","tiao5","tiao6","tong1","tong2","tong3","tong7","tong8","tong9","wan9"]
			else:
				fees = [[1, 0, "荒牌牌型分", 24], [1, 2, "荒牌基础补付", 4], [3, 0, "荒牌牌型分", 24], [3, 2, "荒牌基础补付", 4]]
		"dry-pattern-ready":
			hand = FLUSH.duplicate()
			flip = "tiao6"
			ready = true
			for payer in [1, 2, 3]:
				fees.append([payer, 0, "清一色", 24])
				fees.append([payer, 0, "报听胡牌", 20])
	var card := str(hand.back())
	if mode not in ["self", "kong-self"]: hand.pop_back()
	hands[0] = hand
	if mode in ["ron", "double"]: discards[source].append(card)
	if mode == "rob": hands[source].append(card)
	if not _install_deck(r, hands, melds, discards, mode, flip, tail): return {}
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0 if mode in ["self", "kong-self"] else source
	r._draw_remaining_before = r.wall.remaining + 1
	r.awaiting = true
	r.players[0].ready = ready
	r.players[2].ready = mode == "double"
	r.players[0].announced_ready = r.players[0].ready
	r.players[2].announced_ready = r.players[2].ready
	if mode in ["self", "kong-self"]: r.players[0].just_drew = card
	if mode == "rob": r.players[source].just_drew = card
	if mode in ["ron", "double"]: r.last_discard = {"seat":source,"tile":card,"discard_id":0}
	return {"mode":mode, "source":source, "card":card, "flip":flip, "tail":tail, "fees":fees}

func _install_deck(r: RoundState, hands: Array, melds: Array, discards: Array, mode: String, flip: String, tail: String) -> bool:
	var bag: Array = TileSetFactory.create_deck()
	var used: Array = []
	for seat in 4:
		used.append_array(hands[seat])
		used.append_array(discards[seat])
		for meld in melds[seat]:
			for i in (3 if meld.kind == "pung" else 4): used.append(meld.tile)
	for tile in used:
		if not _check(tile in bag, "a fifth physical copy of %s" % tile): return false
		bag.erase(tile)
	if flip != "":
		if not _check(flip in bag, "no copy left for the wall flip"): return false
		bag.erase(flip)
	if tail != "":
		if not _check(tail in bag, "no copy left for the kong supplement"): return false
		bag.erase(tail)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261107
	for seat in range(1, 4):
		var target: int = 13 - 3 * melds[seat].size() + (1 if mode == "rob" and seat == 1 else 0)
		if hands[seat].size() == target: continue
		var fill: Array = []
		for attempt in 100:
			var available := bag.duplicate()
			fill.clear()
			for i in target - hands[seat].size(): fill.append(available.pop_at(rng.randi_range(0, available.size() - 1)))
			if not RuleEngine.is_tenpai(hands[seat] + fill, melds[seat]): break
		if not _check(not RuleEngine.is_tenpai(hands[seat] + fill, melds[seat]), "could not generate uncalled filler"): return false
		hands[seat].append_array(fill)
		used.append_array(fill)
		for tile in fill: bag.erase(tile)
	if mode in ["draw", "kong-self"]:
		var discard_pool := bag.slice(0, bag.size() - (2 if mode == "kong-self" else 0))
		var index := 0
		for tile in discard_pool:
			discards[index % 4].append(tile)
			bag.erase(tile)
			index += 1
		used.append_array(discard_pool)
		r.round_meta.charge_chickens = {}
		for river_index in discards.map(func(river): return river.size()).max():
			for seat in 4:
				if river_index >= discards[seat].size(): continue
				var tile: String = discards[seat][river_index]
				if Tiles.is_chicken(tile) and not r.round_meta.charge_chickens.has(tile):
					r.round_meta.charge_chickens[tile] = {"owner": seat, "location": "discard", "discard_id": river_index}
	else:
		# Give the pre-settlement table populated rivers with ordinary tiles.
		for seat in 4:
			var count := 0
			for tile in bag.duplicate():
				if Tiles.is_chicken(tile): continue
				discards[seat].insert(count, tile)
				bag.erase(tile)
				used.append(tile)
				count += 1
				if count == 5: break
	for seat in 4:
		var p: PlayerState = r.players[seat]
		p.ready = false
		p.just_drew = ""
		p.score = 200.0
		p.first_turn_done = true
		p.concealed.assign(hands[seat])
		p.melds.assign(melds[seat])
		p.discards.assign(discards[seat])
		p.discard_history.assign(discards[seat])
		p.discard_ids.assign(range(discards[seat].size()))
		p.discard_count = discards[seat].size()
	var ring: Array = used + ([] if flip == "" else [flip]) + bag + ([] if tail == "" else [tail])
	r.wall = WallRing.new(ring)
	r.wall.set_head(0)
	for i in used.size(): r.wall.draw_head()
	return _check(ring.size() == 108 and r.wall.peek_head() == flip, "physical deck/head mismatch")

func _resolve(r: RoundState, spec: Dictionary) -> void:
	var source: int = spec.source
	var card: String = spec.card
	match spec.mode:
		"self":
			_check(r.submit_turn(0, {"self_win":true}), "self draw rejected by turn validator")
		"kong-self":
			if not _check(r.wall.remaining == 4, "kong case must start at the last four tiles"): return
			if not _check(r.submit_turn(0, {"kong_declares":[card]}), "concealed kong rejected by turn validator"): return
			if not _check(r.wall.remaining == 3 and r.players[0].just_drew == spec.tail, "kong supplement must come from the physical wall tail"): return
			_check(r.submit_turn(0, {"self_win":true}), "supplement win rejected by turn validator")
		"ron", "double":
			r.last_discard.discard_id = r.players[source].discard_ids.back()
			r._response_stage = RoundState.ResponseStage.WIN
			r._pending_responders.assign([0, 2] if spec.mode == "double" else [0])
			r._ask_next_responder(source, card)
			_answer_wins(r, card)
		"rob":
			_check(r.submit_turn(source, {"add_kong":[card]}), "add kong rejected by turn validator")
			_answer_wins(r, card)
		"draw":
			if _check(r.wall.remaining == 0, "draw requires empty wall"): r._finish()

func _answer_wins(r: RoundState, card: String) -> void:
	for i in 4:
		if r.phase == RoundState.Phase.SETTLED or r._awaiting_response.is_empty(): return
		var seat := int(r._awaiting_response.seat)
		if not _check(r.submit_response(seat, card, {"action":"win" if seat == 0 or (_case == "double-ron" and seat == 2) else "pass"}), "response rejected for seat %d" % seat): return

func _check_ledger(r: RoundState, spec: Dictionary) -> void:
	var result: Dictionary = r.last_result
	_check(r.round_meta.flip_tile == spec.flip, "flip identity mismatch")
	_check(r.round_meta.get("winners", []) == ([0, 2] if spec.mode == "double" else ([] if spec.mode == "draw" else [0])), "wrong winners")
	_check(result.deltas.reduce(func(a, b): return a + b, 0.0) == 0.0, "four-seat ledger is not zero-sum")
	for seat in 4:
		var row: Array = result.pairwise[seat]
		_check(row.reduce(func(a, b): return a + b, 0.0) == result.deltas[seat], "pairwise row does not match net score")
		_check(r.players[seat].score == 200.0 + result.deltas[seat], "score not applied exactly once")
	for expected in spec.fees:
		var amount := 0.0
		for entry: Dictionary in result.transfers:
			if entry.from == expected[0] and entry.to == expected[1] and entry.reason == expected[2]: amount += float(entry.amount)
		var actual_fee := int(expected[3]) * int(r.round_meta.chicken_multiplier)
		_check(amount == actual_fee, "%d→%d %s: expected %d, got %.0f" % [expected[0], expected[1], expected[2], actual_fee, amount])
	if _case in ["flush-ron", "dry-pattern-ready"]:
		# 总纲 8.5/10.1: verify the total, independent of which component keeps 基础4.
		for payer in ([1] if _case == "flush-ron" else [1, 2, 3]):
			var amount := 0.0
			for entry: Dictionary in result.transfers:
				if entry.from == payer and entry.to == 0 and entry.reason in ["清一色", "大干扣", "报听胡牌"]:
					amount += float(entry.amount)
			var expected := 44 if _case == "flush-ron" else 64
			_check(amount == expected, "%d→0 清一色＋大干扣%s: expected %d, got %.0f" % [payer, "＋报听" if expected == 64 else "", expected, amount])
	if spec.mode == "draw":
		_check(r.next_chicken_multiplier == 2, "any draw must double next round")
		_check(bool(r.round_meta.all_called_draw) == (_case == "all-called-draw"), "incorrect all-called draw status")
		if _case == "all-called-draw": _check(result.transfers.is_empty(), "all-called draw must have zero transfers")
	if spec.mode == "rob": _check(r.round_meta.get("robbed_kong", false) and r.players[spec.source].melds[0].kind == "pung", "robbed kong should remain a pung")
	print("  deltas=", result.deltas, " transfers=", result.transfers)

func _check_animation(table: Control, r: RoundState, spec: Dictionary) -> void:
	var view: Control = table._new_areas
	var index := 1
	var seen := {}
	var last_display: Array = []
	var previous_stage := ""
	var win_captions: Array[String] = []
	var flight_frames := 0
	var next_flight_capture := 0
	var early_score := false
	var deadline := Time.get_ticks_msec() + 12000
	while (not view.native_settlement_started() or not view.native_settlement_complete()) and Time.get_ticks_msec() < deadline:
		await process_frame
		if not view.native_settlement_started():
			if spec.mode == "kong-self" and view._labels.size() == 4:
				for label: Label in view._labels:
					if label.text != "200分": early_score = true
			if spec.mode == "kong-self" and table._table_animation_controller.has_pending() and flight_frames < 12 and Time.get_ticks_msec() >= next_flight_capture:
				await _capture("00-kong-flight-%02d" % flight_frames)
				flight_frames += 1
				next_flight_capture = Time.get_ticks_msec() + 100
			continue
		var stage: String = view._settlement_stage_key
		if stage == "" and is_instance_valid(view._settlement_notice):
			var caption: String = view._settlement_notice.text
			if caption.begins_with("翻鸡  "): stage = "wall-reveal"
			elif caption.begins_with("黄牌"): stage = "all-called"
			elif caption.begins_with("本局得分"): stage = "count-total"
		elif stage == "win" and spec.mode == "double":
			var caption: String = view._settlement_notice.text
			if caption not in win_captions: win_captions.append(caption)
			stage = "win-%d" % (win_captions.find(caption) + 1)
		var display: Array = view._settlement_display_scores if stage == "count-total" else view._settlement_pairs
		if stage != "" and not seen.has(stage):
			seen[stage] = true
			last_display = display.duplicate(true)
			_check(not view._discard_layer.visible, "discard river visible during settlement")
			_check(not table._settlement_card._post_controls.visible, "next round button visible before settlement ends")
			await _capture("%02d-%s" % [index, stage])
			index += 1
		elif stage not in ["", "wall-reveal", "all-called"] and stage == previous_stage and not seen.has(stage + "-roll") and display != last_display:
			seen[stage + "-roll"] = true
			await _capture("%02d-%s-roll" % [index, stage])
			index += 1
		previous_stage = stage
	if not _check(view.native_settlement_started() and view.native_settlement_complete(), "settlement animation timeout"): return
	if _case == "plain-self-draw":
		_check(r.players[1].just_drew == "" and view.draw_boxes[1].get_child_count() == 0,
			"settled hand must not retain an earlier masked draw tile")
	_check(seen.has("all-called") if _case == "all-called-draw" else seen.has("count-total"), "final animation stage missing")
	if _case == "triplets-exposed-kong":
		_check(seen.has("kong") and not seen.has("other"), "exposed kong base fee did not animate in the kong stage")
	if spec.mode == "kong-self":
		_check(flight_frames >= 2 and seen.has("kong"), "kong and supplement flights must precede the kong settlement stage")
		_check(not early_score, "seat totals changed before settlement counting started")
	if spec.mode == "double":
		_check(win_captions.size() == 2, "two winners must have distinct score announcements")
	if spec.flip != "":
		var flip: TileView = view._native_wall_flip_tile()
		_check(seen.has("wall-reveal") and is_instance_valid(flip) and flip.face_up and not flip.score_highlight, "wall tile did not remain face-up and unhighlighted")
	else:
		_check(not seen.has("wall-reveal"), "draw must not flip a wall tile")
	for seat in 4:
		_check(view._settlement_display_scores[seat] == r.players[seat].score, "final UI score does not match ledger")
		for tile: TileView in view._native_tiles_for_seat(seat):
			_check(not tile.score_highlight, "tile remained highlighted after animation")
	var self_seat: int = table.human_seat
	for offset in [1, 2, 3]:
		var peer := posmod(self_seat + offset, 4)
		_check(view._settlement_pairs[self_seat][peer] == r.last_result.pairwise[self_seat][peer], "final relative column does not match ledger")
	var panel: Control = view._native_settlement
	var titles := {
		"plain-self-draw": "你自摸", "ready-seven-pairs": "你报听自摸-小七对",
		"triplets-exposed-kong": "你胡上家-大对子", "flush-ron": "你胡上家-清一色", "dragon-seven-pairs-ron": "你胡上家-龙七对",
		"rob-added-kong": "下家抢你的杠胡牌", "kong-draw-last-four": "你杠开海底自摸-大对子",
		"double-ron": "下家报听胡对家、上家报听胡对家", "mixed-draw": "本局流局",
		"all-called-draw": "四家叫牌流局", "dry-pattern-ready": "你报听自摸-清一色",
	}
	var multiplier_titles := {
		"ready-seven-pairs": "双骰同点 · 本局双倍",
		"mixed-draw": "上局流局 · 本局双倍",
		"triplets-exposed-kong": "上局流局、双骰同点 · 本局双倍",
	}
	_check(panel.get_node("ResultTitle").text == titles[_case], "settlement title shows the outcome in the viewer's seat order")
	_check(panel.get_node("MultiplierTitle").text == multiplier_titles.get(_case, ""), "multiplier identifies the exact source")
	var next: Control = table._settlement_card._post_controls
	var sizes := [Vector2i(1280, 720)]
	if _case in ["triplets-exposed-kong", "double-ron", "all-called-draw"]: sizes.append_array([Vector2i(960, 540), Vector2i(2400, 1080)])
	for dimensions: Vector2i in sizes:
		root.size = dimensions
		await process_frame
		await process_frame
		var bounds := root.get_visible_rect()
		_check(panel.is_visible_in_tree() and bounds.encloses(panel.get_global_rect()), "settlement panel clipped at %s" % dimensions)
		_check(next.is_visible_in_tree() and bounds.encloses(next.get_global_rect()), "next round control clipped at %s" % dimensions)
		_check(not panel.get_global_rect().intersects(next.get_global_rect()), "next round control overlaps settlement")
		for tile: TileView in view._native_tiles_for_seat(table.human_seat):
			_check(not next.get_global_rect().intersects(tile.get_global_rect()), "next round control overlaps own tile")
		await _capture("%02d-final-%dx%d" % [index, dimensions.x, dimensions.y])
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	if spec.mode != "draw" and view.draw_boxes[0].get_child_count() > 0:
		var tile: Control = view.draw_boxes[0].get_child(0)
		var before: Dictionary = r.last_result.duplicate(true)
		await _click(tile)
		var details = view._score_inspection
		if _check(is_instance_valid(details) and details._detail_panel.visible, "winning tile not inspectable through pointer input"):
			_check(details._selected == 0 and details._heading.text.ends_with("得分明细（单倍）") and not details._breakdown.text.is_empty(),
				"hand click opens all score categories for that player")
			var expected_parts: Array = {
				"plain-self-draw": ["自摸 4分"],
				"ready-seven-pairs": ["小七对 24分", "报听 20分", "7筒 · 翻鸡 2分"],
				"triplets-exposed-kong": ["大对子 14分"],
				"flush-ron": ["清一色 24分", "大干扣 20分"],
				"dragon-seven-pairs-ron": ["龙七对 44分"],
				"rob-added-kong": ["抢杠 12分"],
				"kong-draw-last-four": ["大对子 14分", "杠开 5分", "海底捞 5分"],
				"double-ron": ["干扣 14分", "报听 20分"],
				"dry-pattern-ready": ["清一色 24分", "大干扣 20分", "报听 20分"],
			}.get(_case, [])
			var parts: String = details._breakdown.text
			_check(expected_parts.all(func(part): return parts.contains(part)), "winning tile splits single-rate scores: %s" % [parts])
			await _capture("%02d-winning-tile-detail" % (index + 1))
		_check(before == r.last_result, "inspection altered ledger")
	var details = view._score_inspection
	var before: Dictionary = r.last_result.duplicate(true)
	for seat in 4:
		var hand_tile: Control = null
		for tile: TileView in view._native_tiles_for_seat(seat):
			if str(tile.get_meta("new_kind", "")) == "hand":
				hand_tile = tile
				break
		if not _check(hand_tile != null, "all four players have a clickable hand region"):
			continue
		await _click(hand_tile)
		_check(details._detail_panel.visible and details._selected == seat,
			"clicking any hand switches to that player's full details")
		_check(details._heading.text.begins_with(["你", "上家", "对家", "下家"][posmod(seat - view.human_seat, 4)]),
			"player heading uses the viewer's relative position")
		if seat == 0 and _case == "triplets-exposed-kong":
			_check(details._breakdown.text.contains("5万 · 杠 4分") and details._breakdown.text.contains("5万 · 翻鸡 4分")
				and details._breakdown.text.contains("大对子 14分"), "hand click includes the meld and winning pattern")
		elif seat == 0 and _case == "plain-self-draw":
			_check(details._breakdown.text.contains("幺鸡 · 普通鸡 4分") and details._breakdown.text.contains("自摸 4分"),
				"hand click includes all matching chicken tiles and self-draw")
		elif _case == "all-called-draw":
			_check(details._breakdown.text == "叫牌0分", "all-called draw remains inspectable with no scores")
		var called: bool = bool(view._settlement_plan.called[seat])
		_check(details.find_children("*", "ScrollContainer", true, false).is_empty(), "score details have no scroll container")
		_check(details._breakdown.get_line_count() <= 2, "all score entries fit in at most two lines")
		_check(details._breakdown.get_theme_font_size("font_size") >= 18, "two-line details retain a readable font")
		_check(Rect2(Vector2.ZERO, details._detail_panel.size).encloses(details._breakdown.get_rect()), "full detail text fits its panel")
		var parts: Dictionary = details._seat_details[seat].parts
		var status: String = "叫牌" if called else "未叫牌"
		if parts.is_empty():
			_check(details._breakdown.text == status + "0分", "empty scores show called or uncalled zero")
		else:
			_check(details._breakdown.text.begins_with(status), "scoring details identify called status")
		if not called:
			var total := 0.0
			for value in parts.values(): total += float(value) / int(r.round_meta.chicken_multiplier)
			if total < 0.0:
				_check(details._breakdown.text.begins_with("未叫牌%.0f分" % total), "uncalled chicken debts show a negative single-rate total")
		await _click(hand_tile)
		_check(details._detail_panel.visible and details._selected == seat, "repeated hand click keeps details visible")
		for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(2400, 1080)]:
			root.size = dimensions
			await process_frame
			await process_frame
			_check(root.get_visible_rect().encloses(details._detail_panel.get_global_rect()), "player details fit the screen")
			_check(not details._detail_panel.get_global_rect().intersects(panel.get_global_rect()), "player details do not overlap settlement")
			for wall: TileView in view._wall_layer.get_children():
				var bounds: Rect2 = wall.get_global_transform() * Rect2(Vector2.ZERO, wall.size)
				_check(not details._detail_panel.get_global_rect().intersects(bounds), "player details must not cover the remaining wall")
				_check(not panel.get_global_rect().intersects(bounds), "settlement must not cover the remaining wall")
		root.size = Vector2i(1280, 720)
		await process_frame
		await _capture("final-player-%d-detail" % seat)
	for receiving_seat in 4:
		var client := RoundState.new()
		client.apply_sync(JSON.parse_string(JSON.stringify(r.serialize_for_seat(receiving_seat))))
		var plan: Dictionary = preload("res://scripts/ui/table/SettlementAnimationPlan.gd").build(
			client.last_result, client.round_meta, client.players, view.human_seat)
		var remote = load("res://scripts/ui/table/v2/TableV2ScoreInspection.gd").new(
			view, client.last_result, client.round_meta, client.players, plan)
		view._settlement_layer.add_child(remote)
		_check(remote._seat_details == details._seat_details, "network snapshot produces identical details for every player")
		remote.free()
	_check(before == r.last_result, "switching players never changes scores or transfers")
	details._hide_detail()
	_check(not details._detail_panel.visible, "player score details can be closed")

func _click(tile: Control) -> void:
	var center := tile.get_global_transform_with_canvas() * (tile.size / 2.0)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center
		event.global_position = center
		event.pressed = pressed
		# Center was computed in the viewport; stretch may change screen coordinates.
		root.push_input(event, true)
		await process_frame

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://build/settlement-scenarios/cases/" + _case
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if _check(root.get_texture().get_image().save_png(path.path_join(name + ".png")) == OK, "could not save " + name): _captures += 1

func _check(ok: bool, message: String) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[FAIL] %s: %s" % [_case, message])
	return ok


