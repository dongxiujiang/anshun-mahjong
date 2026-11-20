extends SceneTree
const H := preload("res://tests/test_harness.gd")
const ARRANGE := preload("res://scripts/ui/table/v2/HandArrangement.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.cancel_opening()
	table._table_animation_controller.cancel()
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table.round.phase = RoundState.Phase.PLAYING
	table.round.awaiting = false
	var view = table._new_areas
	view.auto_sort_hands = false
	view._sort_started = true
	var player: PlayerState = table.round.players[table.human_seat]
	player.concealed.assign(_wan("1112223334445"))
	player.just_drew = ""
	table._refresh()
	view._sort_own_hand()
	t.expect(view._arrangement_thread == null, "cycling arrangements does not start a worker")
	var original: Array = player.concealed.duplicate()
	var choices: Array = view._arrangement_choices
	for i in choices.size():
		var before: String = view._local_arrangement.key
		view._sort_own_hand()
		view._sort_own_hand(-1)
		t.expect(view._local_arrangement.key == before, "moving backward reverses moving forward across current-hand cycle boundaries")
		t.expect(_toolbar_hidden(view), "cycling keeps the removed toolbar and caption hidden")
		view._sort_own_hand()
	t.expect(player.concealed == original, "browsing in both directions never changes authoritative cards")
	var upgrade := ARRANGE.with_one_tile_changes(original, false).filter(func(choice): return choice.has("change_from"))
	t.expect(not upgrade.is_empty(), "all one-tile big-hand suggestions remain available")
	t.expect(upgrade.all(func(choice): return choice.has("change_to") and Tiles.sort_hand(choice.cards) == original),
		"hypothetical exchanges describe a future draw without altering current cards")
	view._restore_own_hand()
	player.concealed.assign(["wan1", "wan1", "wan1", "wan1", "tiao2", "tiao2", "tiao2", "tiao5", "tiao5", "tiao5", "tong8", "tong8", "tong8"])
	table._refresh()
	view._sort_own_hand()
	t.expect(_toolbar_hidden(view), "grouping a hand does not display arrangement captions")
	for fixed_count in range(5):
		view._restore_own_hand()
		player.melds.clear()
		for i in fixed_count: player.melds.append({"kind":"pung", "tile":"tiao"+str(i+1)})
		player.concealed.assign(_wan("1122334455667").slice(fixed_count*3))
		player.ready = true
		player.just_drew = ""
		table._ai_assist_enabled = true
		table._ai_teach_message = "先打9万。\n也可以考虑1万、5万。"
		table._refresh()
		view._sort_own_hand()
		t.expect(table.status_label.is_visible_in_tree() and _toolbar_hidden(view), "teaching remains visible without the arrangement toolbar")
		var action_id: int = view._begin_visual_action()
		var before: String = view._local_arrangement.key
		view._sort_own_hand()
		view._restore_own_hand()
		t.expect(view._local_arrangement.get("key", "") == before and _toolbar_hidden(view),
			"arrangement changes stay locked during tile animation")
		view._complete_visual_action(action_id, Callable())
		table._refresh()
		if fixed_count == 4:
			t.expect(view._arrangement_choices.size() == 1, "single remaining tile has exactly one arrangement")
	view._restore_own_hand()
	player.ready = false
	player.melds.clear()
	player.concealed.assign(_wan("11122233344455"))
	player.just_drew = "wan5"
	table.round.current_turn = table.human_seat
	table.round.awaiting = true
	table._table_actions.auto_ready_enabled = false
	table._table_actions._selecting = true
	table._refresh()
	view._sort_own_hand()
	t.expect(player.passed_self_draw, "sorting keeps the explicitly requested pass-self-win behavior")
	t.expect(view._local_arrangement.cards.back() == view._local_arrangement.discard, "the calculated discard is the actual rightmost card")
	t.expect(not view._hand_groups.visible and view._hand_groups.get_child_count() == 0, "the removed underline cannot intercept a tile tap")
	table.queue_free()
	await H.quit_cleanly(self, t.finish("sort_usability"))

func _toolbar_hidden(view) -> bool:
	for button in [view._sort_button, view._restore_button, view._previous_sort_button]:
		if button.visible or not button.disabled or button.mouse_filter != Control.MOUSE_FILTER_IGNORE: return false
	return not view._arrangement_caption.visible

func _wan(digits: String) -> Array:
	var cards: Array = []
	for digit in digits: cards.append("wan"+digit)
	return cards
