extends SceneTree
const H := preload("res://tests/test_harness.gd")
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
	await _finish_search(view)
	var original: Array = player.concealed.duplicate()
	var choices: Array = view._arrangement_choices
	for i in choices.size():
		var before: String = view._local_arrangement.key
		view._sort_own_hand()
		view._sort_own_hand(-1)
		t.expect(view._local_arrangement.key == before, "Previous reverses Next including cycle boundaries and future exchanges")
		_check_controls(view, table)
		view._sort_own_hand()
	t.expect(player.concealed == original, "browsing in both directions never changes authoritative cards")
	var upgrade: Array = choices.filter(func(choice): return choice.has("change_from"))
	t.expect(not upgrade.is_empty(), "all one-tile big-hand suggestions remain available")
	view._local_arrangement = upgrade[0]
	table._refresh()
	t.expect(view._arrangement_caption.text.begins_with("换牌设想") and view._arrangement_caption.text.contains("再听"), "future exchange is explicitly distinguished from the current wait")
	_check_controls(view, table)
	view._restore_own_hand()
	player.concealed.assign(["wan1", "wan1", "wan1", "wan1", "tiao2", "tiao2", "tiao2", "tiao5", "tiao5", "tiao5", "tong8", "tong8", "tong8"])
	table._refresh()
	view._sort_own_hand()
	t.expect(not view._arrangement_caption.text.contains("还差") and not view._arrangement_caption.text.contains("未叫牌"),
		"sorting describes groups rather than inventing a called/uncalled verdict from a display estimate")
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
		_check_controls(view, table)
		var action_id: int = view._begin_visual_action()
		t.expect(view._sort_button.visible and view._previous_sort_button.disabled and view._restore_button.disabled, "sorting controls remain visible but lock together during animation")
		view._complete_visual_action(action_id, Callable())
		table._refresh()
		if fixed_count == 4:
			t.expect(view._sort_button.text == "仅此一种" and view._previous_sort_button.disabled, "single remaining tile clearly indicates one arrangement")
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
	var mark = view._hand_groups.get_node_or_null("ArrangementDiscardMark")
	t.expect(mark != null and view._local_arrangement.cards.back() == view._local_arrangement.discard, "discard hint marks an actual rightmost card rather than an imaginary tile")
	if mark != null:
		t.expect(mark.mouse_filter == Control.MOUSE_FILTER_IGNORE, "discard underline never intercepts a tile tap")
	table.queue_free()
	await H.quit_cleanly(self, t.finish("sort_usability"))

func _check_controls(view, table) -> void:
	var controls: Array = [view._sort_button, view._restore_button, view._previous_sort_button]
	for i in controls.size():
		t.expect(controls[i].visible and controls[i].size.y >= 76, "each sorting control remains a full-height touch target")
		if view._table_3d != null:
			for source in view.hand_boxes[view.human_seat].get_children() + view.draw_boxes[view.human_seat].get_children():
				t.expect(not controls[i].get_rect().intersects(view._table_3d.project_tile(source)), "sorting and restore controls never cover the arranged hand")
		for j in range(i):
			t.expect(not controls[i].get_global_rect().intersects(controls[j].get_global_rect()), "sorting controls do not overlap")
		t.expect(not controls[i].get_global_rect().intersects(view._arrangement_caption.get_global_rect()), "caption never covers a sorting control")
	t.expect(not table.status_label.get_global_rect().intersects(view._arrangement_caption.get_global_rect()), "AI teaching has a separate text area")
	var font: Font = view._arrangement_caption.get_theme_font("font")
	var size: int = view._arrangement_caption.get_theme_font_size("font_size")
	t.expect(size >= 20 and view._arrangement_caption.text.split("\n").size() <= 2, "caption stays at least20 design pixels in at most two lines")
	for line in view._arrangement_caption.text.split("\n"):
		t.expect(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x <= view._arrangement_caption.size.x, "every caption line fits without clipping")

func _finish_search(view) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while view._arrangement_thread != null and Time.get_ticks_msec()<deadline: await process_frame
	t.expect(view._arrangement_thread == null, "exchange search finishes")

func _wan(digits: String) -> Array:
	var cards: Array = []
	for digit in digits: cards.append("wan"+digit)
	return cards
