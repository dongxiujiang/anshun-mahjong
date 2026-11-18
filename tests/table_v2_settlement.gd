extends SceneTree
## V2 原生结算：验证阶段顺序、两两支付明细，以及完成动画后解锁下一局按钮的钩子。

const H := preload("res://tests/test_harness.gd")
const PLAN := preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
const SCORING := preload("res://scripts/core/ScoringEngine.gd")
const ROWS := preload("res://scripts/ui/table/v2/SettlementRows.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const WIN := ["tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan3", "wan4", "wan5", "wan9", "wan9"]

var t := H.new()

class SettlementTableStub extends Node:
	var round: RoundState
	var human_seat := 0
	var finished := false
	var _table_animation_controller = null
	func _net_mode() -> String: return ""
	func _clear_actions() -> void:
		pass
	func _update_interactivity() -> void:
		pass
	func _on_settlement_animation_finished() -> void:
		finished = true

func _initialize() -> void:
	call_deferred("_run")

func _fixture(kind: String, flip_card: String = "wan8", flip_index: int = 0, multiplier: int = 1) -> RoundState:
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
	var flip := flip_card
	r.round_meta.chicken_multiplier = multiplier
	r.round_meta.dice_double = multiplier > 1
	r.round_meta.previous_draw_double = multiplier > 1
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
	r.wall.set_head(flip_index)
	r.wall._ring[flip_index] = flip
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

func _check_flip_preview(view, card: String, case: String) -> TileView:
	var panel: Control = view._native_settlement
	var preview: TileView = panel.get_node_or_null("SettlementFlipTile")
	if not t.expect(preview != null, case + ": panel contains a readable flip tile independent of the physical wall"):
		return null
	t.expect(panel.find_children("SettlementFlipTile", "", true, false).size() == 1, case + ": exactly one flip preview")
	t.expect(preview.tile == card and preview.face_up and preview.is_visible_in_tree(), case + ": flip identity remains face-up and visible")
	t.expect(not preview.interactive and preview.mouse_filter == Control.MOUSE_FILTER_IGNORE, case + ": flip preview cannot intercept input")
	t.expect(preview.unit >= 0.8, case + ": flip face is no smaller than existing score-row tiles")
	var bounds := preview.get_global_rect()
	t.expect(panel.get_global_rect().encloses(bounds) and root.get_visible_rect().encloses(bounds), case + ": complete flip tile stays inside panel and screen")
	for other in panel.get_children():
		if other == preview or not other is Control or not other.is_visible_in_tree(): continue
		if other is Label and other.text.is_empty(): continue
		t.expect(not bounds.intersects(other.get_global_rect()), case + ": flip clears " + other.name)
	for other in view._name_labels + view._labels + view._dealer_meld_badges + view._ready_meld_badges:
		if other.is_visible_in_tree(): t.expect(not bounds.intersects(other.get_global_rect()), case + ": flip clears player identity markers")
	return preview

func _check_flip_previews() -> void:
	var original_size := root.size
	var original_scale := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var config := root.get_node("GameConfig")
	var previous_details: bool = config.score_details_enabled
	var previous_speed: String = config.settlement_speed
	config.set_score_details_enabled(false, false)
	config.set_settlement_speed("0.50", false)
	var captures: Array = []
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864), Vector2i(1600, 1000)]:
		root.size = screen
		for side in 4:
			var card: String = ["wan8", "tong8", "tiao1", "tong9"][side]
			for mode in ["instant", "animated", "restored"]:
				var case := "%dx%d side%d %s %s" % [screen.x, screen.y, side, card, mode]
				var r := _fixture("self_draw", card, side * 27, 2 if side % 2 else 1)
				if mode == "restored":
					var synced := RoundState.new()
					synced.apply_sync(r.serialize_for_seat(0))
					r = synced
				var stub := SettlementTableStub.new()
				stub.round = r
				root.add_child(stub)
				var surface := Control.new()
				surface.size = TableV2Geometry.DESIGN_SIZE
				surface.scale = Vector2(screen) / TableV2Geometry.DESIGN_SIZE
				root.add_child(surface)
				var view = load("res://scenes/table/TableV2.tscn").instantiate()
				view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
				view.test_touch_height = 150.0
				surface.add_child(view)
				view.table = stub
				view.auto_sort_hands = false
				view.set_round(r, 0)
				view.start_native_settlement(mode != "animated")
				var preview := _check_flip_preview(view, card, case)
				if mode == "animated" and view._settlement_tween != null:
					view._settlement_tween.pause()
					view._settlement_tween.custom_step(0.2)
					t.expect(view.native_settlement_active(), case + ": checks an actual active settlement timeline")
					_check_flip_preview(view, card, case + " during flip")
					view._finish_native_settlement()
				_check_flip_preview(view, card, case + " completed")
				var physical: TileView = view._native_wall_flip_tile()
				if t.expect(physical != null and physical.face_up, case + ": actual wall tile is revealed"):
					view._table_3d.sync_tiles()
					var projected: Rect2 = view._table_3d.project_tile(physical)
					t.expect(projected.has_area() and not projected.intersects(view._native_settlement.get_rect()),
						case + ": result panel leaves the physical flip visible")
				t.expect(view._settlement_complete and stub.finished, case + ": original settlement completion hook remains intact")
				if mode == "animated" and DisplayServer.get_name() != "headless":
					await process_frame
					await RenderingServer.frame_post_draw
					captures.append(["%dx%d-side%d-%s.png" % [screen.x, screen.y, side, card], root.get_texture().get_image()])
				view.reset_native_settlement()
				t.expect(view._native_settlement == null and (preview == null or not preview.is_inside_tree()), case + ": reset removes the flip preview with the panel")
				for kind in ["draw", "all_called_draw"] if side == 0 and mode == "instant" else []:
					stub.round = _fixture(kind)
					view.set_round(stub.round, 0)
					view.start_native_settlement(true)
					t.expect(view._native_settlement.get_node_or_null("SettlementFlipTile") == null, kind + ": no invented or stale flip preview")
					view.reset_native_settlement()
				surface.queue_free()
				stub.queue_free()
				await process_frame
	var destination := OS.get_environment("SETTLEMENT_FLIP_CAPTURE_DIR")
	if not destination.is_empty():
		DirAccess.make_dir_recursive_absolute(destination)
		for capture in captures: capture[1].save_png(destination.path_join(capture[0]))
	config.set_score_details_enabled(previous_details, false)
	config.set_settlement_speed(previous_speed, false)
	root.size = original_size
	root.content_scale_mode = original_scale

func _check_wall_flip_landing() -> void:
	var stub := SettlementTableStub.new()
	root.add_child(stub)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.table = stub
	view.auto_sort_hands = false
	# Four walls, each corner, a partial next stack, an isolated tile, and a supported upper tile.
	for example in [[11, 12], [35, 36], [65, 66], [91, 92], [27, 28], [53, 54],
			[81, 82], [107, 0], [103, 0], [105, 107], [107, -1], [64, -1]]:
		var index: int = example[0]
		var support: int = example[1]
		var r := _fixture("self_draw", "tong8", index)
		if support == 107 or (support < 0 and index == 107):
			r.wall.set_head(0)
			for i in index: r.wall.draw_head()
			if support == 107: r.wall.draw_tail()
		elif index % 2 == 1:
			r.wall.set_head(index - 1)
			r.wall.draw_head()
			if index == 103:
				for i in 4: r.wall.draw_tail()
		for synced in [false, true]:
			stub.round = r
			if synced:
				stub.round = RoundState.new()
				stub.round.apply_sync(r.serialize_for_seat(stub.human_seat))
			view.set_round(stub.round, stub.human_seat)
			var renderer = view._table_3d
			renderer.sync_tiles()
			var walls := {}
			for tile in view._wall_layer.get_children():
				walls[int(tile.get_meta("wall_ring_index"))] = tile
			var mesh: MeshInstance3D = renderer.tile_nodes[walls[index].get_instance_id()]
			var before := mesh.position
			var count: int = view._wall_layer.get_child_count()
			view.start_native_settlement(true)
			renderer.sync_tiles()
			var tag := "%d->%d remote=%s" % [index, support, synced]
			t.expect(view._native_wall_flip_tile() == walls[index] and walls[index].face_up,
				tag + ": retains the original tile identity and face")
			t.expect(view._wall_layer.get_child_count() == count, tag + ": preserves the wall tile count")
			if support >= 0:
				var below: MeshInstance3D = renderer.tile_nodes[walls[support].get_instance_id()]
				t.expect(mesh.position.is_equal_approx(below.position + Vector3.UP * mesh.basis.x.length() * 0.62)
					and mesh.basis.x.is_equal_approx(below.basis.x), tag + ": lands flush above its next stack")
			else:
				t.expect(mesh.position.is_equal_approx(before), tag + ": lands at its supported original height")
			var landed := mesh.transform
			view.refresh()
			t.expect(mesh.transform.is_equal_approx(landed), tag + ": a settlement refresh preserves the landing")
			if not synced and support >= 0:
				view._restore_native_wall_flip(false)
				view._settlement_complete = false
				view._play_native_settlement()
				var tween: Tween = view._settlement_tween
				tween.pause()
				tween.set_speed_scale(1.0)
				t.expect(view._settlement_matrix_changed(view._settlement_plan.stages[0].scores),
					tag + ": the first score stage can immediately replace the reveal")
				tween.custom_step(0.34)
				renderer.sync_tiles()
				t.expect(walls[index].face_up and not view._native_settlement.visible
					and not mesh.position.is_equal_approx(landed.origin), tag + ": the face travels with the result clear of its path")
				tween.custom_step(0.12)
				renderer.sync_tiles()
				t.expect(view._native_settlement.visible and mesh.transform.is_equal_approx(landed),
					tag + ": the result appears once the tile is resting")
				var notice: Label = view._settlement_notice
				t.expect(is_instance_valid(notice) and notice.is_visible_in_tree()
					and notice.text == "翻鸡  " + view._tile_short("tong8") and view._settlement_stage_key == "",
					tag + ": the landed tile name is shown before scoring")
				tween.custom_step(UI.SETTLEMENT_PAUSE_SECONDS)
				t.expect(view._settlement_stage_key == "flip", tag + ": scoring follows the reveal pause")
			view.reset_native_settlement()
			renderer.sync_tiles()
			t.expect(mesh.position.is_equal_approx(before) and not walls[index].face_up,
				tag + ": reset restores the original wall pose")
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
	await _check_flip_previews()
	await _check_wall_flip_landing()
	root.get_node("AudioManager").stop_effects()
	root.get_node("AudioManager").end_table(null)
	quit(t.finish("table_v2_settlement"))
