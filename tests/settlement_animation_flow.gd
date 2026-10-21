extends SceneTree
## Settled snapshots use a fixed RNG seed. Playback never owns or changes the ledger.
const H := preload("res://tests/test_harness.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const PLAN := preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const WIN := ["tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan3", "wan4", "wan5", "wan9", "wan9"]
const CASES := ["self_draw", "ron", "rob_kong", "multi_win", "draw", "all_called_draw", "gold_tiao", "gold_tong", "zero", "negative", "kongs", "double", "ready_self", "ready_ron", "dry", "big_dry", "triplets", "flush"]
var t := H.new()
var table

# Compile this real GameTable subclass after autoloads exist (CLI --script loads
# this suite earlier). Only external effects are replaced; dispatch stays real.
const ALL_CALLED_TABLE_SOURCE := """extends "res://scripts/ui/GameTable.gd"
var fake_mode := ""
var fake_ready
var new_game_requests := 0
func _ready() -> void:
	_build_static_ui()
	_layout()
func new_game() -> void:
	new_game_requests += 1
func _net_mode() -> String:
	return fake_mode
func _net_node():
	return fake_ready
"""

class ReadyEndpoint extends RefCounted:
	var round_number := 7
	var ready_calls: Array[bool] = []
	var lobby := {"ready_round": 7, "countdown": -1, "seats": [
		{"ready": false}, {"ready": true}, {"ready": false}, {"ready": true}]}

	func is_room_owner() -> bool:
		return true

	func set_ready(value: bool) -> void:
		ready_calls.append(value)
		lobby.seats[0].ready = value

func _initialize() -> void:
	call_deferred("_run")

func _fixture(kind: String, multiplier: int = 1) -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	for seat in 4:
		r.players[seat].concealed = WAIT.duplicate()
		r.players[seat].discards = ["wan7", "tong6"]
		r.players[seat].discard_ids = [0, 1]
		r.players[seat].discard_count = 2
	r.players[0].concealed = WIN.duplicate()
	r.players[0].just_drew = "wan9"
	r.round_meta.winner = 0
	r.round_meta.winners = [0]
	r.round_meta.self_draw = true
	r.round_meta.win_tile = "wan9"
	r.round_meta.chicken_multiplier = multiplier
	var flip := "wan8"
	match kind:
		"ready_self": r.players[0].ready = true
		"ready_ron":
			r.players[0].ready = true
			r.round_meta.self_draw = false
			r.round_meta.discard_seat = 2
		"dry", "big_dry":
			r.players[0].concealed = WAIT.duplicate() + ["wan9"]
			flip = "tiao6"
			if kind == "dry":
				r.players[1].concealed = ["tiao1", "tiao2", "tiao3"] + WAIT.slice(3)
		"triplets":
			r.players[0].concealed = ["wan1", "wan1", "wan1", "wan3", "wan3", "wan3", "tiao2", "tiao2", "tiao2", "tong5", "tong5", "tong5", "wan9", "wan9"]
		"flush", "ready_flush":
			r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "wan9", "wan9"]
			r.players[0].ready = kind == "ready_flush"
		"ron", "zero":
			r.round_meta.self_draw = false
			r.round_meta.discard_seat = 1
			if kind == "zero":
				r.players[0].concealed = WAIT.duplicate()
				r.players[0].concealed.append("wan9")
				flip = "tiao6"
		"rob_kong", "ready_rob_kong":
			r.players[0].ready = kind == "ready_rob_kong"
			r.round_meta.self_draw = false
			r.round_meta.discard_seat = 1
			r.round_meta.robbed_kong = true
			r.round_meta.burn_chicken_seat = 1
			r.round_meta.burn_chicken_reason = "robbed_added_kong"
			r.players[1].discards.append("tiao1")
			r.players[1].discard_ids.append(2)
			r.players[1].discard_count = 3
		"multi_win":
			r.round_meta.self_draw = false
			r.round_meta.discard_seat = 1
			r.round_meta.winner = 2
			r.round_meta.winners = [2, 0]
			r.players[2].concealed.append("wan9")
			r.players[2].ready = true
		"draw", "all_called_draw":
			r.round_meta.winner = -1
			r.round_meta.winners = []
			r.round_meta.self_draw = false
			r.round_meta.win_tile = ""
			r.players[0].concealed = WAIT.duplicate()
			r.players[0].just_drew = ""
			if kind == "draw":
				for seat in [1, 3]:
					r.players[seat].concealed = ["wan1", "tong4", "tiao7"]
					r.players[seat].discards.append("tong8")
					r.players[seat].discard_ids.append(2)
					r.players[seat].discard_count = 3
		"gold_tiao": flip = "tiao1"
		"gold_tong": flip = "tong8"
		"negative": r.apply_scores([788.0, 4.0, 4.0, 4.0])
		"kongs":
			r.players[2].concealed = ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
			r.players[2].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 1}]
			flip = "tiao1"
		"double": r.round_meta.chicken_multiplier = 2
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.wall._ring[0] = flip
	r._finish()
	return r

func _snapshot(r: RoundState) -> PackedByteArray:
	return var_to_bytes([r.serialize(), r.last_result, r.round_meta])

func _sum(values: Array) -> float:
	var total := 0.0
	for value in values: total += float(value)
	return total

func _zero() -> Array:
	return [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]

func _matrix(matrix: Array, context: String) -> void:
	if not t.expect(matrix.size() == 4, context + ": four matrix rows"): return
	var net := 0.0
	for seat in 4:
		if not t.expect(matrix[seat].size() == 4, context + ": four columns"): return
		for other in 4:
			t.expect(is_finite(float(matrix[seat][other])) and is_equal_approx(float(matrix[seat][other]), -float(matrix[other][seat])), context + ": finite antisymmetric payments")
		t.expect(is_zero_approx(float(matrix[seat][seat])), context + ": no self payment")
		net += _sum(matrix[seat])
	t.expect(is_zero_approx(net), context + ": conservation")

func _test_plan(r: RoundState, context: String, human: int) -> void:
	var before := _snapshot(r)
	var plan: Dictionary = PLAN.build(r.last_result, r.round_meta, r.players, human)
	t.expect(plan == PLAN.build(r.last_result, r.round_meta, r.players, human), context + ": deterministic plan")
	t.expect(_snapshot(r) == before, context + ": pure plan cannot write result/state")
	t.expect(plan.final == r.last_result.pairwise and plan.deltas == r.last_result.deltas, context + ": authoritative final matrix/deltas")
	var cumulative := _zero()
	var keys: Array = []
	var stage_winners: Array = []
	for stage in plan.stages:
		keys.append(stage.key)
		if stage.key == "win": stage_winners.append(stage.winner)
		t.expect(stage.has("key") and stage.has("matrix"), context + ": named stage with matrix")
		_matrix(stage.matrix, context + "/" + str(stage.key))
		for seat in 4:
			for other in 4: cumulative[seat][other] += float(stage.matrix[seat][other])
	t.expect(cumulative == plan.final, context + ": stages count each payment exactly once")
	_matrix(plan.final, context + "/final")
	for seat in 4:
		t.expect(is_equal_approx(_sum(plan.final[seat]), float(r.last_result.deltas[seat])), context + ": final rows equal deltas")
	t.expect(is_equal_approx(_sum(r.last_result.scores), 800.0), context + ": four scores total 800")
	t.expect(plan.is_draw == (r.round_meta.winner < 0), context + ": draw classification")
	t.expect(plan.all_called_draw == (context == "all_called_draw"), context + ": all-called classification")
	if context == "all_called_draw":
		t.expect(plan.stages.is_empty(), "all-called draw has no scoring stages")
	elif plan.is_draw:
		t.expect("flip" not in keys and "chicken" not in keys and "win" not in keys, "draw skips hand chicken, flip and win stages")
	else:
		t.expect(keys.slice(0, 3) == ["flip", "chicken", "kong"], "flip, ordinary chicken and kong stages preserve order")
		t.expect(stage_winners == plan.winners, "one separate win stage per winner")
	if context == "multi_win":
		var expected_winners: Array = [0, 2] if human in [0, 3] else [2, 0]
		t.expect(plan.winners == expected_winners, "multi-winner order follows viewing seat, without mutating metadata")
	if context in ["zero", "all_called_draw"]:
		t.expect(plan.final == _zero(), context + ": fixture really has zero payments")
	if context == "negative":
		t.expect(r.last_result.scores.any(func(value): return value < 0), "negative fixture crosses zero")
	if context == "rob_kong":
		t.expect(plan.burned == 1, "robbed kong marks burned source")
		for other in 4: t.expect(plan.final[1][other] <= 0, "burned player has no income")
	if context in ["gold_tiao", "gold_tong"]:
		t.expect(plan.gold_tiles == ["tiao1" if context == "gold_tiao" else "tong8"], "both kinds of gold chicken classified")
	# A caller is allowed to alter its own plan without poisoning input or later builds.
	plan.final[0][1] = 999999.0
	plan.stages.clear()
	t.expect(_snapshot(r) == before, context + ": output owns mutable arrays")
	t.expect(PLAN.build(r.last_result, r.round_meta, r.players, human).final == r.last_result.pairwise, context + ": no cached mutable plan")

func _test_gold_no_double_count() -> void:
	# An isolated ledger makes stage amounts independently checkable: gold is 4,
	# ordinary chicken is 2, and a flip-only tile is 1, each paid by three opponents.
	for gold in ["tiao1", "tong8"]:
		var other := "tong8" if gold == "tiao1" else "tiao1"
		var adjacent := "tiao2" if gold == "tiao1" else "tong9"
		var transfers: Array = []
		for payer in [1, 2, 3]: transfers.append({"from": payer, "to": 0, "amount": 7.0, "reason": "鸡分差额"})
		var result := {"called": [true, true, true, true], "winners": [0], "deltas": [21.0, -7.0, -7.0, -7.0],
			"transfers": transfers, "items": [[
				{"kind": "chicken", "tiles": [gold], "amount": 4.0, "unit_amount": 4.0},
				{"kind": "chicken", "tiles": [other], "amount": 2.0, "unit_amount": 2.0},
				{"kind": "flip", "tiles": [adjacent], "amount": 1.0}], [], [], []]}
		var meta := {"winner": 0, "winners": [0], "flip_tile": gold}
		var before := var_to_bytes([result, meta])
		var plan: Dictionary = PLAN.build(result, meta, [], 0)
		t.expect(plan.stages[0].gross == [5.0, 0.0, 0.0, 0.0], "gold plus adjacent flip appears only in flip gross")
		t.expect(plan.stages[1].gross == [2.0, 0.0, 0.0, 0.0], "ordinary gross excludes gold")
		for payer in [1, 2, 3]:
			t.expect(plan.stages[0].matrix[0][payer] == 5.0 and plan.stages[1].matrix[0][payer] == 2.0, "gold has no second payment in ordinary chicken stage")
		t.expect(plan.final == ScoringEngine.pairwise_payments(transfers), "gold final matches seven-point ledger once")
		t.expect(var_to_bytes([result, meta]) == before, "gold classification leaves ledger immutable")

func _bind(r: RoundState, human: int = 0) -> void:
	if table.round != null:
		table.round.cancel_opening()
		table.round.controllers = [null, null, null, null]
	table.round = r
	table.human_seat = human
	table._connect_audio_round()
	table._refresh()
	table._settlement_animation_controller.skip()

func _nodes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_nodes(child))
	return found

func _signed(value: float) -> String:
	return "%+.0f" % value if not is_zero_approx(value) else "0"

func _color(value: float) -> Color:
	return UI.SCORE_GAIN if value > 0 else (UI.SCORE_LOSS if value < 0 else UI.MUTED)

func _check_final(r: RoundState, context: String) -> void:
	var c = table._settlement_animation_controller
	t.expect(c.has_started() and c.is_completed() and not c.is_active(), context + ": completed")
	t.expect(c._tween == null or not c._tween.is_valid(), context + ": completion releases tween")
	t.expect(c.current_pairs == r.last_result.pairwise, context + ": exact final payments")
	t.expect(not c._skip_button.visible, context + ": skip hidden")
	var all_called: bool = r.round_meta.get("all_called_draw", false)
	if all_called:
		t.expect(c.boards.is_empty() and c.payment_labels.is_empty(), "all-called draw has no payment animation")
		t.expect(c._notice != null and c._notice.visible and c._notice.text == "黄牌，下局鸡分 × 2", "immediate all-called draw retains multiplier notice")
	else:
		t.expect(c.boards.size() == 4 and c.payment_labels.size() == 4, context + ": four tabletop boards")
	for seat in 4:
		t.expect(c.identity_labels.has(seat) and c.identity_labels[seat].is_visible_in_tree(), context + ": settled identity visible beside every score")
		t.expect(table.center_labels[seat].text == "%.0f分" % r.players[seat].score, context + ": exact final score including negatives")
		t.expect(table.center_labels[seat].get_theme_color("font_color").is_equal_approx(Color.WHITE), context + ": final score returns white")
		t.expect(table.net_labels[seat].visible == not all_called, context + ": final net visibility")
		if all_called:
			t.expect(table.discard_scroll[seat].get_node("Tiles").visible, "all-called draw retains rivers")
			if seat != table.human_seat:
				for tile in table.hand_box[seat].get_children():
					if tile is TileView: t.expect(not tile.face_up, "all-called draw does not reveal remote hand")
			continue
		t.expect(table.net_labels[seat].text == _signed(r.last_result.deltas[seat]), context + ": exact final net")
		var board: Control = c.boards[seat]
		var labels: Array = c.payment_labels[seat]
		t.expect(board.is_visible_in_tree() and board.get_child_count() == 3 and labels.size() == 3, context + ": exactly three visible rows, no extra total")
		for index in 3:
			var other: int = posmod(seat + [3, 2, 1][index], 4)
			var value := float(r.last_result.pairwise[seat][other])
			var label: Label = labels[index]
			var row := label.get_parent()
			t.expect(row.get_child_count() == 2 and row.get_node("Direction").text == ["上", "对", "下"][index], context + ": exact relative direction")
			t.expect(label.text == _signed(value), context + ": exact relative signed payment")
			t.expect(label.get_theme_color("font_color").is_equal_approx(_color(value)), context + ": gain/loss/zero colors")
			t.expect(label.is_visible_in_tree(), context + ": relative amount visible")
		t.expect(not table.discard_scroll[seat].get_node("Tiles").is_visible_in_tree(), context + ": river content hidden")
	for node in _nodes(table):
		if node is Button: t.expect(node.text not in ["查看结算", "看牌桌"], context + ": no old card entry buttons")
		t.expect(str(node.name) not in ["ResultPanel", "ResultShade", "SettlementCard", "ResultRestore"], context + ": no card/shade nodes")
	if r.round_meta.winner < 0:
		t.expect(c._flip_view == null, context + ": draws never flip a chicken")
	else:
		t.expect(c._flip_view != null and c._flip_view.face_up and c._flip_view.tile == r.round_meta.flip_tile, context + ": final flipped tile")
		t.expect(c._flip_view.scale.is_equal_approx(Vector2.ONE), context + ": skipping restores flip scale")

func _test_immediate() -> void:
	for kind in CASES:
		var r := _fixture(kind)
		var before := _snapshot(r)
		_bind(r)
		var c = table._settlement_animation_controller
		c.reset()
		c.start(DisplayServer.get_name() != "headless")
		_check_final(r, kind)
		var boards: Dictionary = c.boards.duplicate()
		c.start(true)
		c.skip()
		c.apply_displays()
		table._refresh()
		t.expect(c.boards == boards, kind + ": repeated start/skip/refresh is idempotent")
		t.expect(_snapshot(r) == before, kind + ": presentation never changes state")
		c.reset()
		c.start(true)
		_check_final(r, kind + "/immediate")
		for human in 4: _test_plan(r, kind, human)

func _check_layout() -> void:
	var c = table._settlement_animation_controller
	var screen := Rect2(Vector2.ZERO, Vector2(root.size))
	var occupied: Array[Rect2] = []
	for seat in 4:
		var board: Control = c.boards[seat]
		var bounds: Rect2 = board.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, board.size)
		t.expect(screen.grow(1).encloses(bounds), "payment board fits viewport")
		for previous in occupied: t.expect(not bounds.grow(-1).intersects(previous.grow(-1)), "boards never overlap")
		occupied.append(bounds)
		var rows: Array[Rect2] = []
		for label in c.payment_labels[seat]:
			var row: Control = label.get_parent()
			t.expect(row.get_parent() == board and Rect2(Vector2.ZERO, board.size).grow(1).encloses(row.get_rect()), "three rows fit board")
			for other in rows: t.expect(not row.get_rect().grow(-0.1).intersects(other.grow(-0.1)), "relative rows do not overlap")
			rows.append(row.get_rect())
		var relative: int = posmod(seat - table.human_seat, 4)
		var order: Array = [2, 1, 0] if relative in [1, 2] else [0, 1, 2]
		var directions: Array = [["上", "对", "下"], ["下", "对", "上"], ["下", "对", "上"], ["上", "对", "下"]][relative]
		for slot in 3:
			var row: Control = c.payment_labels[seat][order[slot]].get_parent()
			t.expect(row.get_node("Direction").text == directions[slot], "each seat retains its specified relative direction order")
			var position: Vector2 = row.position
			if slot > 0:
				var previous: Vector2 = c.payment_labels[seat][order[slot - 1]].get_parent().position
				if relative % 2 == 1:
					t.expect(is_equal_approx(position.x, previous.x) and position.y > previous.y, "side seats have three vertical payments in top-to-bottom order")
					t.expect(is_equal_approx(position.y - previous.y - UI.SETTLEMENT_PAYMENT_ROW_SIZE.y, 56.0), "side payment rows use the wider 56px vertical gap")
				else:
					t.expect(is_equal_approx(position.y, previous.y) and position.x > previous.x, "local and opposite seats have three horizontal payments in left-to-right order")
					t.expect(is_equal_approx(position.x - previous.x - UI.SETTLEMENT_PAYMENT_ROW_SIZE.x, 28.0), "local/opposite payment columns retain their 28px horizontal gap")
		var river: Control = table.discard_scroll[seat]
		var center := river.get_global_transform() * (river.size / 2)
		if relative % 2 == 0:
			t.expect((board.get_global_transform() * (board.size / 2)).is_equal_approx(center), "top/bottom board replaces river at its center")
		else:
			t.expect(is_equal_approx(board.get_rect().get_center().y, table._table_center().y), "side vertical boards remain centered beside the table")
			var offset_x: float = board.get_rect().get_center().x - table._table_center().x
			t.expect(is_equal_approx(offset_x, 560.0 if relative == 1 else -560.0), "side payment boards move inward symmetrically without changing vertical spacing")
	for seat in 4:
		var label: Label = c.identity_labels[seat]
		var bounds: Rect2 = label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, label.size)
		t.expect(screen.grow(1).encloses(bounds), "identity fits rotated/resized viewport")
		for previous in occupied: t.expect(not bounds.grow(-1).intersects(previous.grow(-1)), "identity does not overlap payment boards or other identities")
		occupied.append(bounds)
		if c._flip_view != null:
			var flip_bounds: Rect2 = c._flip_view.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c._flip_view.size)
			t.expect(not bounds.intersects(flip_bounds), "identity leaves flip tile visible")
		for other in 4:
			for other_label in [table.center_labels[other], table.net_labels[other], table._player_tile_areas.name_labels[other]]:
				if not other_label.visible: continue
				var other_bounds: Rect2 = other_label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, other_label.size)
				t.expect(not bounds.grow(-1).intersects(other_bounds.grow(-1)), "identity avoids score, net and nickname")
		var text_size := TileView._font().get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
		t.expect(text_size.x <= label.size.x and text_size.y <= label.size.y, "full identity text fits its label without ellipsis")

func _test_reconnect_layout() -> void:
	var host := _fixture("multi_win")
	var before := _snapshot(host)
	for human in 4:
		var client := RoundState.new()
		client.set_rng_seed(20261018)
		client.apply_sync(host.serialize_for_seat(human))
		var client_before := _snapshot(client)
		_bind(client, human)
		for dimensions in [Vector2i(1440, 1520), Vector2i(1280, 720), Vector2i(1080, 1920), Vector2i(960, 540)]:
			root.size = dimensions
			await process_frame
			await process_frame
			table._settlement_animation_controller.refresh_layout()
			_check_final(client, "reconnect seat %d" % human)
			_check_layout()
		client.apply_sync(host.serialize_for_seat(human))
		table._refresh()
		t.expect(_snapshot(client) == client_before, "repeated settled sync/rotation never changes client")
	t.expect(_snapshot(host) == before, "reconnect never changes host")

func _prepare_timed(r: RoundState) -> Tween:
	_bind(r)
	var c = table._settlement_animation_controller
	c.reset()
	if not t.expect(c._prepare(), "settled round prepares timed playback"): return null
	c._play()
	var tween: Tween = c._tween
	if not t.expect(tween != null and tween.is_valid(), "timed path owns a tween"): return null
	tween.pause()
	t.expect(c.is_active() and c.has_started() and not c.is_completed(), "prepared playback is active")
	t.expect(c._skip_button.visible, "skip available during playback")
	t.expect(not table._settlement_card._post_controls.visible, "next round is unavailable during playback")
	for node in _nodes(c.layer): t.expect(not node is Timer, "settlement has no timer nodes")
	for seat in 4:
		t.expect(table.center_labels[seat].text == "%.0f分" % (r.players[seat].score - r.last_result.deltas[seat]), "timed playback begins at pre-settlement score")
	return tween

func _test_highlights() -> void:
	for kind in ["gold_tiao", "gold_tong", "rob_kong", "draw", "kongs"]:
		var r := _fixture(kind)
		var before := _snapshot(r)
		var tween := _prepare_timed(r)
		if tween == null: return
		var c = table._settlement_animation_controller
		for key in ["flip", "chicken"]:
			c._begin_stage(key)
			var highlighted := 0
			for seat in 4:
				for box in [table.hand_box[seat], table.draw_box[seat], table.meld_box[seat], table.chicken_box[seat]]:
					for node in _nodes(box):
						if not node is TileView: continue
						var expected := false
						if not c.plan.is_draw and seat != c.plan.burned and ScoringEngine.is_called(r, seat):
							expected = node.tile in c.plan.flip_tiles if key == "flip" else (Tiles.is_chicken(node.tile) and node.tile not in c.plan.gold_tiles)
						t.expect(node.score_highlight == expected, kind + ": highlight exactly the scoring tiles for " + key)
						if node.score_highlight: highlighted += 1
			if kind in ["gold_tiao", "gold_tong", "kongs"]:
				t.expect(highlighted > 0, "gold fixture exercises actual " + key + " highlights")
			c._end_stage()
			for node in _nodes(table):
				if node is TileView: t.expect(not node.score_highlight, "stage completion clears every highlight")
		c._skip_button.pressed.emit()
		_check_final(r, kind + "/skip button")
		t.expect(_snapshot(r) == before, "highlight/skip presentation cannot change tiles or scoring")

func _test_timed() -> void:
	var r := _fixture("gold_tiao")
	var before := _snapshot(r)
	var tween := _prepare_timed(r)
	if tween == null: return
	var c = table._settlement_animation_controller
	var saw_intermediate := false
	for frame in 3600:
		if not c.is_active(): break
		tween.custom_step(1.0 / 60.0)
		if c.is_active():
			t.expect(c._tween == tween, "all stages share the same owned tween")
			_matrix(c.current_pairs, "frame %d" % frame)
			if c.current_pairs != _zero() and c.current_pairs != r.last_result.pairwise: saw_intermediate = true
	t.expect(saw_intermediate, "manual stepping exercises intermediate payment interpolation")
	_check_final(r, "timed")
	t.expect(_snapshot(r) == before, "timed playback never writes ledger")
	for elapsed in [0.0, 0.1, 0.7, 1.5, 3.0]:
		tween = _prepare_timed(r)
		if tween == null: return
		tween.custom_step(elapsed)
		c.skip()
		c.skip()
		t.expect(not tween.is_valid(), "skip kills tween at %.1fs" % elapsed)
		_check_final(r, "skip %.1fs" % elapsed)
		await process_frame
		await process_frame
		t.expect(_snapshot(r) == before and c.current_pairs == r.last_result.pairwise, "skipped callbacks cannot resume or settle twice")
	tween = _prepare_timed(r)
	if tween == null: return
	tween.custom_step(0.2)
	c.reset()
	c.reset()
	t.expect(not tween.is_valid() and not c.has_started() and not c.is_active() and not c.is_completed(), "reset cancels timeline and flags")
	t.expect(c.boards.is_empty() and c.payment_labels.is_empty(), "reset removes boards")
	t.expect(c.identity_labels.is_empty(), "reset removes settled identities for the next round")
	for seat in 4: t.expect(table.discard_scroll[seat].get_node("Tiles").visible, "reset restores river content")
	var next := _fixture("draw")
	_bind(next)
	await process_frame
	_check_final(next, "next round after cancel")
	t.expect(_snapshot(r) == before, "cancelled previous round remains immutable")
	c.reset()
	next.phase = RoundState.Phase.PLAYING
	c.start()
	c.skip()
	t.expect(not c.has_started() and c.boards.is_empty(), "active game cannot enter settlement")

func _test_counting() -> void:
	var c = table._settlement_animation_controller
	for delta in [-999, -61, -60, -1, 0, 1, 60, 61, 999]:
		var start := 20.0
		var target: float = start + delta
		var previous := start
		for index in 101:
			var value: float = c.counted_score(start, target, index / 100.0)
			t.expect(value >= minf(start, target) and value <= maxf(start, target), "score count never overshoots, including negatives")
			t.expect((value - previous) * signf(delta) >= 0, "score count is monotone")
			previous = value
		t.expect(previous == target, "score count ends exactly on odd/even delta")
		t.expect(c._score_duration_for_delta(delta) <= 1.5, "score count has bounded duration")
	t.expect(c.counted_score(200, 260, 0.5) == 230 and c.counted_score(200, 261, 0.5) == 230, "60 uses single steps; 61 uses double steps")
	var r := _fixture("negative")
	var before := _snapshot(r)
	var tween := _prepare_timed(r)
	if tween == null: return
	c._begin_final()
	for seat in 4:
		t.expect(table.center_labels[seat].get_theme_color("font_color").is_equal_approx(_color(r.last_result.deltas[seat])), "final counting begins in the sign color")
		t.expect(table.net_labels[seat].visible, "final counting shows net delta")
	c._roll_final(0.5)
	for seat in 4:
		var score_text: String = table.center_labels[seat].text.trim_suffix("分")
		t.expect(score_text.is_valid_int(), "counting renders only whole points")
	c._roll_final(1.0)
	for seat in 4:
		t.expect(table.center_labels[seat].text == "%.0f分" % r.players[seat].score, "count animation reaches exact signed score")
		t.expect(table.center_labels[seat].get_theme_color("font_color").is_equal_approx(Color.WHITE), "completed score counting restores white")
	c.skip()
	t.expect(c._particles.is_empty(), "skip removes digit particles")
	t.expect(_snapshot(r) == before, "score counting never applies deltas again")

func _test_score_identity_refresh() -> void:
	var r := _fixture("self_draw")
	var before := _snapshot(r)
	_bind(r)
	var c = table._settlement_animation_controller
	c.reset()
	# Reproduce the gap while win visuals drain: refresh identity alone, without
	# table._refresh(), which would automatically start settlement and hide a flash.
	for repeat in 3:
		for seat in 4:
			table._player_tile_areas._refresh_identity(seat)
			var old_score: float = r.players[seat].score - r.last_result.deltas[seat]
			t.expect(table.center_labels[seat].text == "%.0f分" % old_score, "identity before settlement starts retains pre-settlement score")
		t.expect(not c.has_started(), "identity refresh alone cannot start settlement")
	t.expect(_snapshot(r) == before, "pre-settlement identity refresh never rewinds authoritative scores")
	c.start(true)
	for seat in 4:
		t.expect(table.center_labels[seat].text == "%.0f分" % r.players[seat].score, "immediate start replaces old score with authoritative final score")
		table._player_tile_areas._refresh_identity(seat)
		t.expect(table.center_labels[seat].text == "%.0f分" % r.players[seat].score, "identity refresh after completion preserves final score")
	t.expect(_snapshot(r) == before, "immediate score display never reapplies settlement")
	var tween := _prepare_timed(r)
	if tween == null: return
	c._begin_final()
	var saw_intermediate := false
	for progress in [0.25, 0.5, 0.75]:
		c._roll_final(progress)
		for seat in 4:
			var label: Label = table.center_labels[seat]
			var caption := label.text
			var color := label.get_theme_color("font_color")
			var old_score: float = r.players[seat].score - r.last_result.deltas[seat]
			if caption != "%.0f分" % old_score and caption != "%.0f分" % r.players[seat].score:
				saw_intermediate = true
			for repeat in 3:
				table._player_tile_areas._refresh_identity(seat)
				t.expect(label.text == caption, "identity refresh during counting preserves intermediate score without a final-score flash")
				t.expect(label.get_theme_color("font_color").is_equal_approx(color), "identity refresh preserves controller-owned counting color")
		t.expect(_snapshot(r) == before, "identity refresh during counting leaves result and state immutable")
	t.expect(saw_intermediate, "identity regression exercises a genuine intermediate total")
	c.skip()
	t.expect(_snapshot(r) == before, "finishing identity regression leaves authoritative settlement unchanged")

func _all_called_timeline(view) -> Tween:
	var c = view._settlement_animation_controller
	c.reset()
	if not t.expect(c._prepare(), "all-called draw prepares its notice timeline"): return null
	c._play()
	var tween: Tween = c._tween
	if not t.expect(tween != null and tween.is_valid(), "all-called notice owns one live tween"): return null
	tween.pause()
	t.expect(c.is_active() and not c.is_completed(), "notice is active before its deadline")
	t.expect(c.boards.is_empty() and c.payment_labels.is_empty() and c._flip_view == null, "notice creates no boards or flipped tile")
	t.expect(not c._skip_button.visible and not view._post_controls.visible, "notice has neither skip nor next-round controls")
	t.expect(c._notice != null and c._notice.is_visible_in_tree() and c._notice.text == "黄牌，下局鸡分 × 2", "all-called notice remains visible until its deadline")
	for seat in 4:
		t.expect(view.discard_scroll[seat].get_node("Tiles").visible, "all-called notice leaves rivers visible")
		for node in _nodes(view.hand_box[seat]) + _nodes(view.draw_box[seat]):
			if node is TileView:
				t.expect(not node.score_highlight and (seat == view.human_seat or not node.face_up), "notice never highlights or reveals remote hands")
	return tween

func _test_all_called_timeline() -> void:
	var view_script := GDScript.new()
	view_script.source_code = ALL_CALLED_TABLE_SOURCE
	if not t.expect(view_script.reload() == OK, "compile isolated GameTable subclass"): return
	var config := root.get_node("GameConfig")
	var previous_speed: String = config.settlement_speed
	for speed in ["standard", "slow", "detail", "instant"]:
		config.set_settlement_speed(speed)
		var duration := 1.5 # An all-called notice is not a scoring animation.
		for mode in ["", "client"]:
			var r := _fixture("all_called_draw")
			var before := _snapshot(r)
			var endpoint := ReadyEndpoint.new()
			var view = view_script.new()
			view.fake_mode = mode
			view.fake_ready = endpoint
			view.size = Vector2(root.size)
			root.add_child(view)
			view.round = r
			view._refresh()
			# Flush deferred layout work before exercising a paused timeline.
			await process_frame
			var c = view._settlement_animation_controller
			var tween := _all_called_timeline(view)
			if tween == null:
				view.free()
				continue
			view._next_round_button.pressed.emit()
			t.expect(view.new_game_requests == 0 and endpoint.ready_calls.is_empty(), "next-round dispatch is locked while notice is active")
			tween.custom_step(duration - 0.001)
			t.expect(c.is_active() and not c.is_completed() and c._notice != null and c._notice.visible, "notice persists just before the scaled 1.5-second deadline")
			t.expect(view.new_game_requests == 0 and endpoint.ready_calls.is_empty(), "no offline or online advance before deadline")
			tween.custom_step(0.002)
			t.expect(c.is_completed() and not c.is_active() and c._notice == null, "notice is removed immediately after deadline")
			t.expect(not tween.is_valid() and c._tween == null, "all-called natural completion releases its timeline")
			t.expect(c.boards.is_empty() and c._flip_view == null and not c._skip_button.visible, "natural completion never creates a scoring animation")
			if mode == "":
				t.expect(view.new_game_requests == 1, "offline natural completion dispatches real next-round handler exactly once")
				t.expect(endpoint.ready_calls.is_empty(), "offline advance does not send readiness")
			else:
				t.expect(view.new_game_requests == 0 and endpoint.ready_calls.is_empty(), "online natural completion waits for human readiness")
				t.expect(view._post_controls.visible and not view._next_round_button.disabled, "online completion exposes enabled bottom ready button")
				t.expect(view._next_round_status.text.contains("2 / 4") and view._next_round_button.text.contains("准备"), "online completion shows authoritative ready counts")
				view._next_round_button.pressed.emit()
				view._refresh_next_round_controls()
				t.expect(endpoint.ready_calls == [true] and endpoint.lobby.seats[0].ready, "real next-round handler calls endpoint set_ready(true)")
				t.expect(view._next_round_status.text.contains("3 / 4") and view._next_round_button.text.contains("3/4"), "ready acknowledgment updates bottom count and cancel action")
				view._next_round_button.pressed.emit()
				view._refresh_next_round_controls()
				t.expect(endpoint.ready_calls == [true, false] and view._next_round_status.text.contains("2 / 4"), "ready button dispatches cancellation through same handler")
			var requests: int = view.new_game_requests
			var ready_calls := endpoint.ready_calls.duplicate()
			c.start()
			c.skip()
			await process_frame
			t.expect(view.new_game_requests == requests and endpoint.ready_calls == ready_calls, "completed notice never advances again on start/skip or later frame")
			# Cancelling a pending notice must also cancel its automatic-next callback.
			tween = _all_called_timeline(view)
			if tween != null:
				tween.custom_step(duration / 2.0)
				c.reset()
				c.reset()
				await process_frame
				t.expect(not tween.is_valid() and c._notice == null and not c.has_started(), "reset removes notice and cancels its pending callback")
				t.expect(view.new_game_requests == requests and endpoint.ready_calls == ready_calls, "reset cannot auto-advance or change readiness")
			# Programmatic skip follows the normal final-snapshot behavior, without
			# running the interactive auto-next callback that belongs to the timer.
			tween = _all_called_timeline(view)
			if tween != null:
				tween.custom_step(duration / 2.0)
				c.skip()
				c.skip()
				await process_frame
				t.expect(c.is_completed() and not c.is_active() and not tween.is_valid(), "skip completes and cancels the all-called timeline")
				t.expect(c._notice != null and c._notice.visible, "skipped all-called draw retains its final notice")
				t.expect(view.new_game_requests == requests and endpoint.ready_calls == ready_calls, "skip cannot replay the delayed automatic-next callback")
			t.expect(_snapshot(r) == before and _sum(r.last_result.scores) == 800.0, "all-called timeline and ready actions preserve scores and settled state")
			view.free()
			await process_frame
	config.set_settlement_speed(previous_speed)

func _test_settlement_speed() -> void:
	var config := root.get_node("GameConfig")
	var old_animation: String = config.animation_speed
	var old_draw: String = config.draw_animation_speed
	var old_settlement: String = config.settlement_speed
	var r := _fixture("gold_tiao")
	var snapshot := _snapshot(r)
	for general in ["instant", "fast", "standard"]:
		config.set_animation_speed(general)
		var general_duration: float = config.animation_duration(1.0)
		for settlement in ["standard", "slow", "detail"]:
			config.set_settlement_speed(settlement)
			t.expect(config.animation_speed == general and config.animation_duration(1.0) == general_duration, "settlement speed never changes play animation speed")
			var duration: float = config.settlement_duration(UI.SETTLEMENT_FADE_SECONDS)
			var tween := _prepare_timed(r)
			if tween == null: return
			var c = table._settlement_animation_controller
			tween.custom_step(duration / 2.0)
			t.expect(is_equal_approx(c._river_alpha, 0.5), "settlement fade uses only its own selected duration, including instant play animation")
			t.expect(c.is_active() and c._tween == tween, "speed scaling does not replace or skip timeline")
			c.skip()
			_check_final(r, general + "/" + settlement)
	config.set_animation_speed("instant")
	config.set_settlement_speed("standard")
	var tween := _prepare_timed(r)
	if tween == null: return
	var c = table._settlement_animation_controller
	tween.custom_step(0.05)
	t.expect(is_equal_approx(c._river_alpha, 0.75), "initial fade advances at normal settlement speed")
	var settings = table._sound_settings
	settings.settlement_speed_buttons.slow.pressed.emit()
	t.expect(c._tween == tween and is_equal_approx(c._river_alpha, 0.75), "live setting preserves exact animation progress")
	t.expect(settings.settlement_speed_buttons.slow.modulate != Color.WHITE, "selected settlement speed is marked")
	tween.custom_step(0.1)
	t.expect(is_equal_approx(c._river_alpha, 0.5), "live slow setting halves playback rate immediately")
	settings.settlement_speed_buttons.detail.pressed.emit()
	tween.custom_step(0.175)
	t.expect(is_equal_approx(c._river_alpha, 0.25), "live detailed setting applies without restarting fade")
	t.expect(config.animation_speed == "instant", "settlement selection preserves instant play animation")
	settings.draw_speed_buttons.fast.pressed.emit()
	t.expect(config.settlement_speed == "detail", "general animation selection preserves detailed settlement")
	settings.settlement_speed_buttons.instant.pressed.emit()
	t.expect(not tween.is_valid() and c._tween == null, "instant selection immediately cancels active timeline")
	_check_final(r, "live instant")
	config.set_settlement_speed("invalid")
	t.expect(config.settlement_speed == "instant", "invalid settlement speed is ignored")
	t.expect(_snapshot(r) == snapshot, "all speed changes leave authoritative settlement immutable")
	var groups: Array = [settings.speed_buttons, settings.draw_speed_buttons, settings.discard_speed_buttons, settings.settlement_speed_buttons]
	var rectangles: Array[Rect2] = []
	for group in groups:
		for button in group.values():
			t.expect(Rect2(Vector2.ZERO, settings.panel.size).encloses(button.get_rect()), "all speed controls stay inside settings")
			for previous in rectangles: t.expect(not button.get_rect().intersects(previous), "independent speed controls never overlap")
			rectangles.append(button.get_rect())
	config.set_animation_speed(old_animation)
	config.set_draw_animation_speed(old_draw)
	config.set_settlement_speed(old_settlement)

func _test_settlement_identities(render: bool = true) -> void:
	for sample in [["self_draw", "自摸 +4", "", 1],
		["ready_self", "报听自摸 +24", "", 1],
		["ready_ron", "报听胡对家 +24", "", 1], ["ron", "下家放炮", "", 1],
		["rob_kong", "抢杠下家 +12", "", 1], ["dry", "自摸", "干扣 +14", 1],
		["big_dry", "自摸", "大干扣 +24", 1], ["triplets", "自摸", "大对子 +14", 1],
		["flush", "自摸", "清一色 +24", 1],
		["ready_flush", "报听自摸 +24", "清一色 +24", 1],
		["ready_rob_kong", "抢杠下家 +12", "报听 +24", 1],
		["self_draw", "自摸 +8", "", 2],
		["ready_self", "报听自摸 +48", "", 2],
		["ready_ron", "报听胡对家 +48", "", 2],
		["ready_rob_kong", "抢杠下家 +24", "报听 +48", 2],
		["ready_flush", "报听自摸 +48", "清一色 +48", 2],
		["dry", "自摸", "干扣 +28", 2], ["big_dry", "自摸", "大干扣 +48", 2],
		["triplets", "自摸", "大对子 +28", 2]]:
		var r := _fixture(sample[0], sample[3])
		var before := _snapshot(r)
		var identities: Array = PLAN.build(r.last_result, r.round_meta, r.players).identities
		t.expect(identities[0].title == sample[1], sample[0] + ": winner source matches settled metadata")
		t.expect(identities[0].detail == sample[2], sample[0] + ": actual scored pattern appears without rerunning hand analysis")
		t.expect(identities[0].winner and identities[0].called, "winner/called identity fields remain compatible")
		if render:
			_bind(r)
			var c = table._settlement_animation_controller
			var expected: String = sample[1] + ("\n" + sample[2] if sample[2] != "" else "")
			t.expect(c.identity_labels[0].text == expected, sample[0] + ": full status rendered next to total")
			if sample[0] in ["ron", "rob_kong"]: t.expect(c.identity_labels[1].text == "叫牌", "nonwinner shows called state only, including discarder and robbed player")
		for human in 4:
			var client := RoundState.new()
			client.apply_sync(r.serialize_for_seat(human))
			t.expect(PLAN.build(client.last_result, client.round_meta, client.players, human).identities == identities, "reconnect retains every source and detail amount for each viewing seat")
		t.expect(_snapshot(r) == before and _sum(r.last_result.scores) == 800.0, "identity does not change score, hands or result")
	if not render:
		_test_identity_item_amounts()
		return
	var draw := _fixture("draw")
	_bind(draw)
	for seat in 4:
		t.expect(table._settlement_animation_controller.identity_labels[seat].text == ("叫牌" if seat in [0, 2] else "未叫牌"), "draw shows called status without invented win type")
	var multi := _fixture("multi_win")
	var before := _snapshot(multi)
	for human in 4:
		var client := RoundState.new()
		client.set_rng_seed(20261018)
		client.apply_sync(multi.serialize_for_seat(human))
		_bind(client, human)
		var c = table._settlement_animation_controller
		for seat in 4: table._player_tile_areas.name_labels[seat].show()
		_check_layout()
		t.expect(c.identity_labels[0].text == "下家放炮", "multi-win source is relative to winner zero, not viewer")
		t.expect(c.identity_labels[2].text == "报听胡上家 +24", "reconnected second winner retains ready/source metadata and item amount")
		t.expect(c.identity_labels[3].text == "叫牌", "nonwinning called player has no potential win pattern")
	t.expect(_snapshot(multi) == before, "reconnected identity rendering leaves host unchanged")
	_test_identity_item_amounts()
	# Exercise long, two-line labels at every physical position, without mutating
	# a settled round to fabricate hand patterns or scoring bonuses.
	for human in 4:
		_bind(multi, human)
		var c = table._settlement_animation_controller
		for label in c.identity_labels.values(): c._remove_visual(label)
		c.identity_labels.clear()
		for seat in 4:
			c.plan.identities[seat] = {"title": "抢杠上家 +12", "detail": "报听 +24 · 清龙七对 +64", "winner": true, "called": true}
			table._player_tile_areas.name_labels[seat].show()
		c._build_identities()
		c.refresh_layout()
		_check_layout()
	t.expect(_snapshot(multi) == before, "long-label layout leaves the real round and ledger unchanged")

func _expect_identity_items(entries: Array, meta: Dictionary, title: String, detail: String, ready: bool = false) -> void:
	# Deliberately unrelated net/transfer totals expose any accidental substitution
	# of player income or three payers' combined receipts for an item's amount.
	var result := {"winners": [0], "called": [true, true, false, false], "deltas": [321.0, -107.0, -107.0, -107.0],
		"items": [entries, [{"kind": "pattern", "label": "清一色", "amount": 24}],
			[{"kind": "ready", "label": "报听胡牌", "amount": 24}], []], "transfers": [
			{"from": 1, "to": 0, "amount": 24.0, "reason": "报听胡牌"},
			{"from": 2, "to": 0, "amount": 24.0, "reason": "报听胡牌"},
			{"from": 3, "to": 0, "amount": 24.0, "reason": "报听胡牌"}]}
	var players := [{"ready": ready}, {"ready": true}, {"ready": true}, {"ready": false}]
	var snapshot := var_to_bytes([result, meta, players])
	var identities: Array = PLAN.build(result, meta, players).identities
	t.expect(identities[0] == {"title": title, "detail": detail, "winner": true, "called": true},
		"independent settled item text: " + title + " / " + detail + "; got " + str(identities[0]))
	for seat in [1, 2, 3]:
		t.expect(identities[seat] == {"title": "叫牌" if seat == 1 else "未叫牌", "detail": "", "winner": false, "called": seat == 1},
			"nonwinner cannot expose readiness fees or potential pattern amounts")
	t.expect(var_to_bytes([result, meta, players]) == snapshot, "identity amounts leave all ledger and metadata inputs unchanged")

func _test_identity_item_amounts() -> void:
	# Cover every label with both missing and nonstandard ledger amounts. The
	# display must never fetch its price from the rule table or apply meta's multiplier.
	for pattern in ["大对子", "大对子单吊", "小七对", "龙七对", "清一色", "清大对", "清七对", "清单吊", "清龙对", "干扣", "大干扣"]:
		for amount in [null, 37.5]:
			var entries := [{"kind": "bonus" if pattern in ["干扣", "大干扣"] else "pattern", "label": pattern},
				{"kind": "bonus", "label": "杠开"}, {"kind": "bonus", "label": "海底捞"}]
			if amount != null:
				for item in entries: item.amount = amount
			var suffix := "" if amount == null else " +37.5"
			_expect_identity_items(entries, {"winner": 0, "self_draw": true, "chicken_multiplier": 2}, "自摸",
				("清龙七对" if pattern == "清龙对" else pattern) + suffix + " · 杠开" + suffix + " · 海底捞" + suffix)
	for seat in 4:
		for offset in [1, 2, 3]:
			var plan := PLAN.build({"items": [[], [], [], []]}, {"winner": seat, "discard_seat": (seat + offset) % 4, "robbed_kong": true}, [])
			t.expect(plan.identities[seat].title == "抢杠" + ["", "下家", "对家", "上家"][offset], "robbed source is correct at every absolute seat")
	var self_meta := {"winner": 0, "self_draw": true, "chicken_multiplier": 2}
	var ron_meta := {"winner": 0, "discard_seat": 2}
	var rob_meta := {"winner": 0, "discard_seat": 1, "robbed_kong": true}
	var base := {"kind": "bonus", "label": "自摸", "amount": 4.0}
	var ready := {"kind": "ready", "label": "报听胡牌", "amount": 24.0}
	var robbed := {"kind": "win", "label": "抢杠胡基础分", "amount": 12.0}
	_expect_identity_items([base, ready], self_meta, "报听自摸 +24", "自摸 +4")
	_expect_identity_items([ready, base], self_meta, "报听自摸 +24", "自摸 +4")
	_expect_identity_items([ready], self_meta, "报听自摸 +24", "")
	_expect_identity_items([base], self_meta, "报听自摸", "自摸 +4", true)
	_expect_identity_items([], self_meta, "自摸", "")
	_expect_identity_items([], ron_meta, "报听胡对家", "", true)
	_expect_identity_items([ready, {"kind": "pattern", "label": "清一色", "amount": 24.0}], self_meta,
		"报听自摸 +24", "清一色 +24")
	_expect_identity_items([robbed, ready], rob_meta, "抢杠下家 +12", "报听 +24")
	_expect_identity_items([ready, robbed], rob_meta, "抢杠下家 +12", "报听 +24")
	_expect_identity_items([ready], rob_meta, "抢杠下家", "报听 +24")
	_expect_identity_items([robbed], rob_meta, "报听抢杠下家 +12", "", true)
	for sample in [["点炮基础分（叫牌）", 17], ["点炮基础分（未叫牌）", 21]]:
		var entry := {"kind": "win", "label": sample[0], "amount": sample[1]}
		_expect_identity_items([entry], ron_meta, "对家放炮 +%d" % sample[1], "")
		_expect_identity_items([entry, ready], ron_meta, "报听胡对家 +24", "%s +%d" % sample)
	_expect_identity_items([
		{"kind": "bonus", "label": "自摸", "amount": 6.25},
		{"kind": "ready", "label": "报听胡牌", "amount": 31.5}], self_meta,
		"报听自摸 +31.5", "自摸 +6.25")
	# Missing or invalid amounts preserve known captions without inventing zero,
	# default rule prices, own_amount totals, or a missing ordinary self-draw item.
	_expect_identity_items([{"kind": "ready", "label": "报听胡牌", "own_amount": 72},
		{"kind": "bonus", "label": "自摸"}], self_meta, "报听自摸", "自摸")
	for amount in [null, "unknown", INF, NAN]:
		_expect_identity_items([{"kind": "ready", "label": "报听胡牌", "amount": amount},
			{"kind": "pattern", "label": "清一色", "amount": amount}], self_meta, "报听自摸", "清一色")
	_expect_identity_items([{"kind": "bonus", "label": "自摸", "amount": 0},
		{"kind": "pattern", "label": "清一色", "amount": -1.25}], self_meta, "自摸 +0", "清一色 -1.25")
	# Repeated labels remain independent rows, even when their amounts agree.
	_expect_identity_items([base, ready, ready, {"kind": "pattern", "label": "清一色", "amount": 24},
		{"kind": "pattern", "label": "清一色", "amount": 48}], self_meta,
		"报听自摸 +24", "自摸 +4 · 报听 +24 · 清一色 +24 · 清一色 +48")
	_expect_identity_items([base, {"kind": "chicken", "label": "报听胡牌", "amount": 99},
		{"kind": "kong", "label": "清一色", "amount": 88}], self_meta, "自摸 +4", "")
	_expect_identity_items([ready, {"kind": "pattern", "label": "清龙对", "amount": 128},
		{"kind": "bonus", "label": "杠开", "amount": 10}, {"kind": "bonus", "label": "海底捞", "amount": 10}],
		self_meta, "报听自摸 +24", "清龙七对 +128 · 杠开 +10 · 海底捞 +10")

func _test_exit() -> void:
	var r := _fixture("rob_kong")
	var before := _snapshot(r)
	var tween := _prepare_timed(r)
	if tween == null: return
	var c = table._settlement_animation_controller
	tween.custom_step(0.15)
	table.free()
	await process_frame
	t.expect(c.table == null and not tween.is_valid(), "freeing table kills timeline and releases table")
	t.expect(_snapshot(r) == before, "exit cannot alter round")

func _test_settlement_audio() -> void:
	var audio := root.get_node("AudioManager")
	var saved_enabled: bool = audio.enabled.effects
	var saved_volume: float = audio.volumes.effects
	var cues: Array[String] = []
	var heard := func(cue: String): cues.append(cue)
	audio.settlement_cue_played.connect(heard)
	audio.set_enabled("effects", true, false)
	audio.set_volume("effects", 0.65, false)
	for kind in ["gold_tiao", "kongs", "ron", "rob_kong", "multi_win", "draw", "zero"]:
		var r := _fixture(kind)
		var snapshot := _snapshot(r)
		var tween := _prepare_timed(r)
		if tween == null: return
		var c = table._settlement_animation_controller
		cues.clear()
		var expected: Array[String] = []
		for stage in c.plan.stages:
			if c._matrix_changed(stage.matrix): expected.append(str(stage.key))
		if c.plan.deltas.any(func(delta): return not is_zero_approx(float(delta))): expected.append("coins")
		for frame in 3600:
			if not c.is_active(): break
			tween.custom_step(1.0 / 60.0)
		t.expect(c.is_completed() and cues == expected, kind + ": one cue per changed scoring stage, then coins with final particles")
		for refresh in 3: c.apply_displays()
		t.expect(cues == expected, "refresh does not replay scoring or coin sounds")
		t.expect(_snapshot(r) == snapshot and _sum(r.last_result.scores) == 800.0, "sound callbacks never change scoring")
	# Final snapshots, headless start and all-called draws remain silent.
	cues.clear()
	for kind in ["ron", "draw", "all_called_draw"]: _bind(_fixture(kind))
	t.expect(cues.is_empty(), "instant/headless/reconnect snapshots never replay settlement sounds")
	var r := _fixture("gold_tiao")
	var tween := _prepare_timed(r)
	if tween == null: return
	var c = table._settlement_animation_controller
	c._begin_stage("flip")
	t.expect(audio.settlement_player.playing, "active scoring stage starts its effect")
	c.skip()
	t.expect(not audio.settlement_player.playing, "skip cancels the currently playing settlement cue")
	var count := cues.size()
	c.apply_displays()
	c.start(true)
	t.expect(cues.size() == count, "skip and final refresh do not play an arrival cue")
	for zero_volume in [false, true]:
		audio.set_enabled("effects", zero_volume, false)
		audio.set_volume("effects", 0.0 if zero_volume else 0.65, false)
		tween = _prepare_timed(r)
		if tween == null: return
		c._begin_stage("win")
		c._begin_final()
		t.expect(not audio.settlement_player.playing and cues.size() == count, "effects off or zero volume suppresses stages and coins")
		c.skip()
	audio.set_enabled("effects", true, false)
	audio.set_volume("effects", 0.65, false)
	tween = _prepare_timed(r)
	if tween == null: return
	c._begin_stage("chicken")
	c.reset()
	t.expect(not audio.settlement_player.playing and not tween.is_valid(), "new-round/reset stops both sound and visual timeline")
	audio.set_enabled("effects", saved_enabled, false)
	audio.set_volume("effects", saved_volume, false)
	audio.settlement_cue_played.disconnect(heard)

func _capture_review() -> void:
	if DisplayServer.get_name() == "headless": return
	var folder := "res://build/ui_review/settlement_animation"
	t.expect(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) == OK, "create screenshot review directory")
	root.size = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	var r := _fixture("gold_tiao")
	var tween := _prepare_timed(r)
	if tween == null: return
	var c = table._settlement_animation_controller
	for key in ["flip", "chicken"]:
		for frame in 3600:
			if not c.is_active() or c._stage_key == key: break
			tween.custom_step(1.0 / 60.0)
		if not t.expect(c._stage_key == key, "capture active " + key + " stage"): break
		await process_frame
		await RenderingServer.frame_post_draw
		t.expect(root.get_texture().get_image().save_png(folder + "/golden_chicken_" + key + ".png") == OK, "save active " + key + " screenshot")
		# Leave the current stage so the next search advances to its successor.
		for frame in 3600:
			if not c.is_active() or c._stage_key != key: break
			tween.custom_step(1.0 / 60.0)
	c.skip()
	await process_frame
	await RenderingServer.frame_post_draw
	t.expect(root.get_texture().get_image().save_png(folder + "/golden_chicken_final.png") == OK, "save final tabletop screenshot")
	for sample in ["ready_ron", "multi_win", "rob_kong", "draw", "big_dry", "flush"]:
		_bind(_fixture(sample))
		for seat in 4:
			# Exercise the reserved nickname space even in this offline fixture.
			table._player_tile_areas.name_labels[seat].show()
		await process_frame
		_check_layout()
		await RenderingServer.frame_post_draw
		t.expect(root.get_texture().get_image().save_png(folder + "/identity_" + sample + ".png") == OK, "save identity screenshot: " + sample)
	table._sound_settings.persist_changes = false
	table._sound_settings.open()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	t.expect(root.get_texture().get_image().save_png(folder + "/settlement_speed_settings.png") == OK, "save independent speed settings screenshot")
	table._sound_settings.close(false)

func _run() -> void:
	# Allow ledger/text checks while presentation collaborators are updating UI
	# helpers; the default run still exercises the complete rendered flow.
	if "--identity-items-only" in OS.get_cmdline_user_args():
		_test_settlement_identities(false)
		quit(t.finish("settlement_identity_items"))
		return
	var master := AudioServer.get_bus_index("Master")
	var was_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	_test_immediate()
	_test_gold_no_double_count()
	await _test_reconnect_layout()
	_test_highlights()
	await _test_timed()
	_test_counting()
	_test_score_identity_refresh()
	_test_settlement_speed()
	_test_settlement_identities()
	_test_settlement_audio()
	await _test_all_called_timeline()
	await _capture_review()
	await _test_exit()
	AudioServer.set_bus_mute(master, was_muted)
	await H.quit_cleanly(self, t.finish("settlement_animation_flow"))
