extends SceneTree
## V2 原生结算：验证阶段顺序、两两支付明细，以及完成动画后解锁下一局按钮的钩子。

const H := preload("res://tests/test_harness.gd")
const PLAN := preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
const SCORING := preload("res://scripts/core/ScoringEngine.gd")
const ROWS := preload("res://scripts/ui/table/v2/SettlementRows.gd")
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const WIN := ["tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan3", "wan4", "wan5", "wan9", "wan9"]

var t := H.new()

class SettlementTableStub extends Node:
	var round: RoundState
	var human_seat := 0
	var finished := false
	func _clear_actions() -> void:
		pass
	func _update_interactivity() -> void:
		pass
	func _on_settlement_animation_finished() -> void:
		finished = true

func _initialize() -> void:
	call_deferred("_run")

func _fixture(kind: String) -> RoundState:
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
	var flip := "wan8"
	if kind == "ron":
		r.round_meta.self_draw = false
		r.round_meta.discard_seat = 1
		r.round_meta.winner = 0
		r.round_meta.winners = [0]
		r.round_meta.win_tile = "wan9"
	elif kind in ["draw", "all_called_draw"]:
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
	else:
		r.round_meta.winner = 0
		r.round_meta.winners = [0]
		r.round_meta.self_draw = true
		r.round_meta.win_tile = "wan9"
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.wall._ring[0] = flip
	r._finish()
	return r

func _stage_keys(plan: Dictionary) -> Array:
	var keys: Array = []
	for stage in plan.get("stages", []):
		keys.append(str(stage.get("key", "")))
	return keys

func _check_stage_order(plan: Dictionary, kind: String) -> void:
	var keys := _stage_keys(plan)
	if kind == "all_called_draw":
		t.expect(keys.is_empty(), kind + ": all-called draw skips staged scoring")
		return
	if kind == "draw":
		for key in keys:
			t.expect(key in ["kong", "other"], kind + ": draw only emits kong/other stages")
		return
	t.expect(keys.find("flip") >= 0, kind + ": flip stage present")
	t.expect(keys.find("chicken") > keys.find("flip"), kind + ": chicken follows flip")
	t.expect(keys.find("kong") > keys.find("chicken"), kind + ": kong follows chicken")
	t.expect(keys.find("win") > keys.find("kong"), kind + ": win follows kong")

func _check_details(plan: Dictionary, r: RoundState, kind: String) -> void:
	t.expect(plan.final == r.last_result.pairwise, kind + ": final matrix equals settled pairwise")
	t.expect(plan.deltas == r.last_result.deltas, kind + ": deltas equal settled deltas")
	for seat in 4:
		var rel := SCORING.relative_payments(plan.final, seat)
		var total := 0.0
		for value in rel:
			total += float(value)
		t.expect(is_equal_approx(total, float(plan.deltas[seat])), kind + ": seat%d relative payments sum to delta" % seat)
	for stage in plan.get("stages", []):
		var matrix: Array = stage.matrix
		var scores: Array = stage.scores
		for a in 4:
			for b in 4:
				t.expect(is_equal_approx(float(matrix[a][b]), -float(matrix[b][a])), kind + ": antisymmetric stage matrix")
				t.expect(is_equal_approx(float(scores[a][b]) - float(scores[b][a]), float(matrix[a][b])),
					kind + ": each pair of signed scores explains its payment")

func _check_relative_scores() -> void:
	var result := {
		"called": [true, true, false, false],
		"winners": [0],
		"items": [
			[{"kind": "flip", "amount": 2}, {"kind": "chicken", "amount": 8, "tiles": ["tiao1", "tong8"]}],
			[{"kind": "flip", "amount": 4}, {"kind": "chicken", "amount": 2, "tile": "tiao1"}],
			[{"kind": "kong", "amount": 8, "flip_amount": 4, "tile": "wan5"}],
			[],
		],
		"transfers": [
			{"from": 1, "to": 0, "amount": 4, "reason": "鸡分差额"},
			{"from": 2, "to": 0, "amount": 10, "reason": "鸡分差额"},
			{"from": 2, "to": 1, "amount": 6, "reason": "鸡分差额"},
			{"from": 2, "to": 0, "amount": 2, "reason": "未叫牌出牌鸡"},
			{"from": 2, "to": 0, "amount": 4, "reason": "未叫牌杠分"},
			{"from": 2, "to": 0, "amount": 4, "reason": "自摸基础分"},
			{"from": 1, "to": 0, "amount": 4, "reason": "自摸基础分"},
			{"from": 3, "to": 0, "amount": 4, "reason": "自摸基础分"},
		],
	}
	var plan := PLAN.build(result, {"flip_tile": "wan6"}, [])
	t.expect(plan.stages[0].scores[0][1] == 2 and plan.stages[0].scores[1][0] == 4,
		"flip keeps both called players' scores when the viewer pays")
	t.expect(plan.stages[1].scores[0][1] == 8 and plan.stages[1].scores[1][0] == 2,
		"ordinary chicken keeps both gross scores before comparison")
	var self_vs_called := 0.0
	var called_vs_self := 0.0
	var self_vs_uncalled := 0.0
	var uncalled_vs_self := 0.0
	for stage in plan.stages:
		self_vs_called += float(stage.scores[0][1])
		called_vs_self += float(stage.scores[1][0])
		self_vs_uncalled += float(stage.scores[0][2])
		uncalled_vs_self += float(stage.scores[2][0])
	t.expect(self_vs_called == 14 and called_vs_self == 6, "called pair includes applicable self draw fee")
	t.expect(self_vs_uncalled == 14 and uncalled_vs_self == -6,
		"uncalled debt includes actual discard and kong base but excludes ordinary flip")
	var draw := PLAN.build({
		"called": [true, false, true, false],
		"items": [[], [{"label": "未叫牌出牌鸡", "amount": -2}], [], []],
		"transfers": [
			{"from": 1, "to": 0, "amount": 6, "reason": "荒牌包鸡"},
			{"from": 1, "to": 0, "amount": 4, "reason": "荒牌基础补付"},
		],
	}, {}, [])
	t.expect(draw.stages.back().scores[0][1] == 8 and draw.stages.back().scores[1][0] == -2,
		"draw package separates each player's chickens and credits the called fee")
	t.expect(draw.stages.back().scores[0][2] == 0 and draw.stages.back().scores[2][0] == 0,
		"called players do not compare their chickens on a draw")

func _run_native_api() -> void:
	var config = root.get_node("GameConfig")
	var previous_score_details: bool = config.score_details_enabled
	config.set_score_details_enabled(false, false)
	var r := _fixture("self_draw")
	var stub := SettlementTableStub.new()
	stub.round = r
	stub.human_seat = 0
	root.add_child(stub)
	var deck = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(deck)
	deck.round = r
	deck.human_seat = 0
	deck.table = stub
	deck.snapshot = TableV2Model.build(r, 0)
	deck._build_wall()
	var flip_index := r.wall.peek_head_index()
	var wall_count := r.wall.remaining
	var source: TileView
	for tile in deck._wall_layer.get_children():
		if int(tile.get_meta("wall_ring_index", -1)) == flip_index:
			source = tile
			break
	t.expect(source != null and not source.face_up, "settlement source starts as a face-down wall tile")
	var client := RoundState.new()
	client.apply_sync(r.serialize_for_seat(2))
	t.expect(client.wall == null and TableV2Model.flip_wall_index(client) == flip_index, "client knows the same flip slot without receiving the wall deck")
	var old_wall := WallRing.new(TileSetFactory.create_deck())
	old_wall.set_head(54)
	for i in 20:
		old_wall.draw_head()
	var old_snapshot := r.serialize_for_seat(2)
	old_snapshot.round_meta.erase("flip_wall_index")
	old_snapshot.wall_stacks[1] = old_wall.wall_stack_counts(1)
	old_snapshot.visual_events.append({"type": "draw", "kind": "head", "wall_index": 73})
	client.apply_sync(old_snapshot)
	t.expect(TableV2Model.flip_wall_index(client) == 74, "older snapshots recover the head in a reversed physical wall")
	await process_frame
	t.expect(not deck.native_settlement_active(), "native settlement starts not active")
	deck.start_native_settlement(true)
	t.expect(deck.native_settlement_started(), "native settlement marks started")
	t.expect(not deck.native_settlement_active(), "immediate settlement is not active")
	t.expect(deck.native_settlement_complete(), "immediate settlement completes")
	t.expect(stub.finished, "completed native settlement unlocks next-round-button hook")
	t.expect(deck._settlement_plan.get("winners", []).size() > 0, "plan retains winners")
	t.expect(deck._native_wall_flip_tile() == source and source.face_up and source.tile == r.wall.peek_head(),
		"immediate settlement reveals the original wall tile")
	t.expect(not source.score_highlight, "revealed wall tile uses normal face color")
	t.expect(r.wall.remaining == wall_count and r.wall.peek_head_index() == flip_index, "flip neither consumes nor advances the wall")
	t.expect(deck._native_settlement is Panel and not deck._discard_layer.visible, "personal panel replaces ordinary discards")
	t.expect(deck._settlement_pairs == r.last_result.pairwise, "panel net values match the final ledger")
	for seat in 4:
		t.expect(int(deck._settlement_net_labels[seat].text) == int(r.last_result.deltas[seat]), "each player row shows the actual ledger net")
	t.expect(deck._native_settlement.get_node("ScoreHeading").text == "得分项", "score heading uses the requested wording")
	t.expect(deck._native_settlement.get_node("ScoreHeading").horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "score item heading is centered")
	t.expect(deck._native_settlement.get_node("TotalHeading").text == "总分", "single-rate totals have their own column")
	t.expect(deck._native_settlement.find_children("PlayerDivider*", "ColorRect", false, false).size() == 4, "header and all player rows have horizontal separators")
	t.expect(deck._score_inspection == null, "settlement has no score detail overlay by default")
	config.set_score_details_enabled(true, false)
	t.expect(is_instance_valid(deck._score_inspection), "enabling score details applies to the current settlement")
	var inspection = deck._score_inspection
	var rich_terms: Array[String] = ["叫牌", "大对子 14分", "报听 12分", "5万 · 杠 4分", "5万 · 翻鸡 4分",
		"幺鸡 · 杠 4分", "幺鸡 · 杠中鸡 8分", "八筒 · 杠 4分", "八筒 · 杠中鸡 8分",
		"9万 · 杠 4分", "幺鸡 · 冲锋鸡 4分", "八筒 · 普通鸡 4分", "6筒 · 翻鸡 2分"]
	inspection._fit_two_lines(rich_terms)
	t.expect(inspection._breakdown.get_line_count() == 2 and inspection._breakdown.get_theme_font_size("font_size") >= 18,
		"rich score details occupy exactly two readable lines")
	for term in rich_terms:
		t.expect(inspection._breakdown.text.contains(term), "two-line formatting retains the complete score item: " + term)
	t.expect(inspection.find_children("*", "ScrollContainer", true, false).is_empty(), "score details do not contain a scroll container")
	config.set_score_details_enabled(false, false)
	t.expect(deck._score_inspection == null, "disabling score details removes the current overlay and tile inputs")
	t.expect(int(deck._settlement_net_labels[0].text) == int(r.last_result.deltas[0]), "toggling details preserves the settlement total")
	config.set_score_details_enabled(true, false)
	deck.reset_native_settlement()
	t.expect(not deck.native_settlement_started(), "reset clears native settlement started flag")
	t.expect(deck._native_settlement == null and deck._discard_layer.visible, "next round restores ordinary discard layer")
	t.expect(deck._score_inspection == null, "next round removes score inspection")
	t.expect(not source.face_up and source.scale == Vector2.ONE, "reset restores the wall tile's normal appearance")
	config.set_score_details_enabled(previous_score_details, false)
	deck.queue_free()
	stub.queue_free()
	await process_frame

func _check_called_headers() -> void:
	const UI = preload("res://scripts/ui/table/TableUiConfig.gd")
	for kind in ["self_draw", "ron", "draw", "all_called_draw"]:
		var local := _fixture(kind)
		for viewer in 4:
			var client := RoundState.new()
			client.apply_sync(local.serialize_for_seat(viewer))
			for state in [local, client]:
				var deck = load("res://scenes/table/TableV2.tscn").instantiate()
				root.add_child(deck)
				deck.round = state
				deck.human_seat = viewer
				deck._settlement_plan = PLAN.build(state.last_result, state.round_meta, state.players, viewer)
				deck._build_native_settlement_panel()
				var panel: Control = deck._native_settlement
				var dealer: Label = deck._hud_badge("庄", Vector2.ZERO, UI.DEALER_BACKGROUND, UI.DEALER_BORDER)
				for index in 4:
					var seat := posmod(viewer + index, 4)
					var heading: Label = panel.get_node("SettlementSeat%d" % seat)
					var badge: Label = panel.get_node_or_null("CalledStatus%d" % seat)
					var called := bool(deck._settlement_plan.called[seat])
					t.expect(heading.text == str(deck._seat_display_names([]).get(seat, ["你", "上家", "对家", "下家"][index])), "row uses the player's display name on local and synced tables")
					t.expect((badge != null) == called, "uncalled seats have no badge on local or synced tables")
					if badge != null:
						t.expect(badge.text == "叫" and badge.size == dealer.size, "called badge matches the dealer badge size and single-character style")
						t.expect(badge.get_theme_stylebox("normal").bg_color == Color("#30784e"), "called seats and winners use green badges")
						t.expect(not badge.get_rect().intersects(heading.get_rect()) and panel.get_rect().size.y > badge.get_rect().end.y, "status badge does not overlap its seat label or leave the panel")
					var self_draw: Label = panel.get_node_or_null("SelfDrawStatus%d" % seat)
					t.expect((self_draw != null) == (bool(state.round_meta.get("self_draw", false)) and seat in deck._settlement_plan.winners), "self-draw badge belongs only to the self-drawing winner")
					if self_draw != null:
						t.expect(self_draw.text == "自摸" and not self_draw.get_rect().intersects(heading.get_rect()), "self-draw badge sits to the right of the player name")
				deck.free()

func _check_total_values() -> void:
	var scores: Array = [[0.0, 42.0, 34.0, 42.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
	var plan := {"stages": [{"scores": scores}]}
	var before := plan.duplicate(true)
	var roles := [["（上）", "（下）"], ["（我）", "（对）"], ["（下）", "（上）"], ["（对）", "（我）"]]
	for viewer in 4:
		var totals := ROWS.totals(plan, {"chicken_multiplier": 2}, 0, viewer)
		t.expect(totals.size() == 3 and totals[0].amount == 17 and totals[0].suffix == "", "common total stays single-rate and is shown once")
		for index in 2:
			var source: int = [1, 3][index]
			var matching := totals.filter(func(row): return row.opponent == source)
			t.expect(matching.size() == 1 and matching[0].amount == 21 and matching[0].suffix == roles[viewer][index], "exposed-kong total identifies the payer relative to the viewer")
	t.expect(plan == before, "reading totals never changes the payment plan")
	scores[0] = [0.0, 13.0, 17.0, 13.0]
	var ron := ROWS.totals(plan, {}, 0, 0)
	t.expect(ron.size() == 2 and ron[0].amount == 13 and ron[1].amount == 17 and ron[1].suffix == "（对）", "discard-win fee belongs only to the responsible payer before comparison")
	scores[0] = [0.0, -12.0, -8.0, -8.0]
	var debt := ROWS.totals(plan, {}, 0, 0)
	t.expect(debt.size() == 2 and debt[0].amount == -8 and debt[1].amount == -12 and debt[1].suffix == "（上）", "uncalled kong debt retains its sign and responsible payer")
	var zero := ROWS.totals({"stages": []}, {}, 0, 0)
	t.expect(zero.size() == 1 and zero[0].amount == 0, "all-called draw has a single zero total")

func _check_two_exposed_example() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.round_meta = {"winner": 0, "winners": [0], "self_draw": true, "win_tile": "tong6", "chicken_multiplier": 1}
	r.players[0].concealed = ["wan3", "wan4", "wan5", "tong6", "tong6"]
	r.players[0].just_drew = "tong6"
	r.players[0].melds = [{"kind": "kong", "tile": "wan9", "from_seat": 1}, {"kind": "kong", "tile": "tong8", "from_seat": 3}, {"kind": "add_kong", "tile": "tiao7", "from_seat": 2}]
	var deck: Array = TileSetFactory.create_deck()
	var used: Array = r.players[0].concealed.duplicate()
	for meld in r.players[0].melds:
		for i in 4: used.append(meld.tile)
	for card in used: deck.erase(card)
	deck.erase("wan2") # Reserve the actual face-up flip tile.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	for seat in [1, 2, 3]:
		for i in 13:
			var index := rng.randi_range(0, deck.size() - 1)
			r.players[seat].concealed.append(deck[index])
			used.append(deck[index])
			deck.remove_at(index)
	r.wall = WallRing.new(used + ["wan2"] + deck)
	r.wall.set_head(0)
	for i in used.size(): r.wall.draw_head()
	r._finish()
	var plan: Dictionary = PLAN.build(r.last_result, r.round_meta, r.players, 0)
	var totals := ROWS.totals(plan, r.round_meta, 0, 0)
	t.expect(totals == [{"amount": 17.0, "opponent": -1, "suffix": ""}, {"amount": 21.0, "opponent": 1, "suffix": "（上）"}, {"amount": 21.0, "opponent": 3, "suffix": "（下）"}], "actual scorer produces the requested 17/21/21 double-exposed-kong example")
	var entries := ROWS.entries(r.last_result, r.round_meta, r.players, plan, 0)
	t.expect(entries.filter(func(entry): return entry.get("kong", {}).get("label", "") == "明杠").size() == 2, "both exposed kongs remain in the score items")
	for viewer in 4:
		var synced := RoundState.new()
		synced.apply_sync(r.serialize_for_seat(viewer))
		var client_plan: Dictionary = PLAN.build(synced.last_result, synced.round_meta, synced.players, viewer)
		t.expect(ROWS.totals(client_plan, synced.round_meta, 0, viewer) == ROWS.totals(plan, r.round_meta, 0, viewer), "solo and network retain the same totals and viewer-relative sources")
	if DisplayServer.get_name() != "headless":
		var stub := SettlementTableStub.new()
		stub.round = r
		root.add_child(stub)
		var view = load("res://scenes/table/TableV2.tscn").instantiate()
		root.add_child(view)
		view.set_round(r, 0)
		view.table = stub
		view.start_native_settlement(true)
		t.expect(view._native_settlement != null and view._native_settlement.get_node("PlayerTotal0").tooltip_text == "+17　+21（上）　+21（下）", "real double-kong panel displays all requested total variants")
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/total-column")
		root.get_texture().get_image().save_png("res://build/total-column/two-exposed-17-21-21.png")
		view.queue_free()
		stub.queue_free()
		await process_frame

func _run() -> void:
	_check_total_values()
	await _check_two_exposed_example()
	_check_called_headers()
	_check_relative_scores()
	for kind in ["self_draw", "ron", "draw", "all_called_draw"]:
		var r := _fixture(kind)
		t.expect(r.phase == RoundState.Phase.SETTLED, kind + ": fixture reaches settled phase")
		var plan: Dictionary = PLAN.build(r.last_result, r.round_meta, r.players, 0)
		t.expect(plan == PLAN.build(r.last_result, r.round_meta, r.players, 0), kind + ": deterministic plan")
		_check_stage_order(plan, kind)
		_check_details(plan, r, kind)
	await _run_native_api()
	root.get_node("AudioManager").stop_effects()
	root.get_node("AudioManager").end_table(null)
	quit(t.finish("table_v2_settlement"))
