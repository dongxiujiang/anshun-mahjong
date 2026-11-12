extends SceneTree

const H := preload("res://tests/test_harness.gd")
const ARRANGE := preload("res://scripts/ui/table/v2/HandArrangement.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var hand := _wan("1112223334445")
	var wide := ARRANGE.build(hand, false)
	var pattern := ARRANGE.build(hand, true)
	t.expect(wide.size() > 1, "ambiguous hand has several distinct winning splits")
	t.expect(wide.all(func(choice): return choice.width <= wide[0].width)
		and pattern.all(func(choice): return choice.score <= pattern[0].score),
		"preferences rank the actual wait width and actual scoring pattern")
	var all_waits := {}
	for layout in wide:
		t.expect(Tiles.sort_hand(layout.cards) == hand, "every layout contains exactly the original tiles")
		all_waits.merge(layout.waits)
	t.expect(all_waits.size() == RuleEngine.waiting_tiles(hand, []).size(), "layouts cover all legal waits")
	var pairs := _wan("1122334455667")
	t.expect(ARRANGE.build(pairs, true).any(func(choice): return choice.lengths == [2, 2, 2, 2, 2, 2]), "seven pairs remain available as six pairs and one single")
	var near := ["wan1", "wan1", "wan3", "wan5", "wan6", "wan8", "tiao1", "tiao5", "tiao9", "tong1", "tong3", "tong4", "tong9"]
	var near_choices := ARRANGE.build(near, false)
	t.expect(not near_choices.is_empty() and near_choices[0].grouped >= 2 and near_choices[0].width == 0, "an uncalled hand groups what it can without inventing waits")

	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.cancel_opening()
	var controller = table._table_animation_controller
	controller.cancel()
	controller._dealt = [13, 13, 13, 13]
	table.round.phase = RoundState.Phase.PLAYING
	table.round.awaiting = false
	var view = table._new_areas
	view.auto_sort_hands = false
	view._sort_started = true
	var player = table.round.players[table.human_seat]
	player.concealed.assign(hand)
	player.just_drew = ""
	table._refresh()
	t.expect(view._sort_button.visible and not view._restore_button.visible, "13 tiles show Sort below the draw slot")
	t.expect(view._sort_button.position.y >= TableV2Geometry.HAND_BOTTOM, "Sort does not cover the hand")
	view._sort_own_hand()
	var first: Array = view._local_arrangement.cards
	view._sort_own_hand()
	t.expect(first != view._local_arrangement.cards and view._restore_button.visible, "second tap cycles layouts and shows Restore")
	var deadline := Time.get_ticks_msec()+5000
	while view._arrangement_thread != null and Time.get_ticks_msec()<deadline:
		await process_frame
	t.expect(view._arrangement_thread == null and view._arrangement_choices.any(func(choice):return choice.has("change_from")), "background search adds the complete one-tile upgrade choices")
	var seen := {}
	for i in view._arrangement_choices.size():
		view._sort_own_hand()
		seen[view._local_arrangement.key] = true
	t.expect(seen.size()==view._arrangement_choices.size(), "repeated taps visit every distinct arrangement instead of stopping after one")
	t.expect(player.concealed == hand, "view sort leaves authoritative indices unchanged")
	view._local_arrangement = view._arrangement_choices.filter(func(choice): return choice.has("change_from"))[0]
	table._refresh()
	var arranged: Array = view._local_arrangement.cards
	player.concealed.append("wan9")
	player.just_drew = "wan9"
	table._refresh()
	t.expect(view._sort_button.visible and not view._sort_button.disabled and view._local_arrangement.cards == arranged, "Sort stays available with a separate draw")
	view._sort_own_hand()
	t.expect(view.draw_boxes[table.human_seat].get_child_count() == 0
		and view._local_arrangement.cards.size() == 14 and view.hand_boxes[table.human_seat].get_child_count() == 14, "sorting merges the drawn tile without changing the authoritative hand")
	if DisplayServer.get_name() != "headless":
		table._ai_assist_enabled = true
		table._apply_proxy_teach({"discard": "wan9", "recommendations": [
			{"tile": "wan9", "distance": 0, "outs": 12}, {"tile": "wan1"}, {"tile": "wan5"}]})
		t.expect(not table.status_label.get_global_rect().intersects(view._arrangement_caption.get_global_rect()), "teaching and sorting keep separate readable text areas")
		await _capture("teaching-and-sorting")
		table._ai_assist_enabled = false
		table._clear_ai_teach()
		table._refresh()
	await _capture("sorting-with-draw")
	var merged_draw = view.hand_boxes[table.human_seat].get_children().filter(func(tile): return tile.get_meta("drawn", false))[0]
	player.concealed.pop_back()
	player.just_drew = ""
	var merged_finished := {"value": false}
	view.animate_draw_discard(table.human_seat, func(): merged_finished.value = true, "wan9")
	t.expect(merged_draw.get_parent() != view.hand_boxes[table.human_seat], "merged draw flies from its real hand entity")
	await create_timer(0.8).timeout
	t.expect(merged_finished.value, "merged draw discard animation finishes")
	table._refresh()
	t.expect(Tiles.sort_hand(view._local_arrangement.cards) == hand, "discard after merging retains exactly the remaining thirteen tiles")
	var before_insert: Dictionary = view._local_arrangement
	player.concealed.append("wan6")
	player.just_drew = "wan6"
	table._refresh()
	var drawn: TileView = view.draw_boxes[table.human_seat].get_child(0)
	player.concealed.remove_at(12)
	player.just_drew = ""
	var finished := {"value": false}
	var sorted_slots := {13: 12}
	for index in 12: sorted_slots[index] = index
	view.animate_draw_insert(table.human_seat, "wan5", "wan6", func(): finished.value = true, 12, sorted_slots)
	await create_timer(0.8).timeout
	t.expect(finished.value and drawn.get_parent() == view.hand_boxes[table.human_seat], "draw physically joins the arranged row")
	var most_retained := 0
	for choice in ARRANGE.build(player.concealed, false):
		most_retained = maxi(most_retained, ARRANGE.retained_groups(before_insert, choice))
	t.expect(ARRANGE.retained_groups(before_insert, view._local_arrangement) == most_retained, "insertion retains the most complete groups among valid layouts")
	for tile in view.hand_boxes[table.human_seat].get_children():
		t.expect(tile.tile == player.concealed[int(tile.get_meta("concealed_index"))], "inserted tile and each touch target retain their real indices")
	player.concealed.assign(hand + ["wan9"])
	player.just_drew = "wan9"
	table._refresh()
	view._sort_own_hand()
	var merged_discard = view.hand_boxes[table.human_seat].get_children().filter(func(tile): return int(tile.get_meta("concealed_index")) == 12)[0]
	player.concealed.remove_at(12)
	player.just_drew = ""
	merged_finished.value = false
	view.animate_draw_insert(table.human_seat, "wan5", "wan9", func(): merged_finished.value = true, 12)
	t.expect(merged_discard.get_parent() != view.hand_boxes[table.human_seat], "discard from merged hand reuses the exact chosen entity")
	await create_timer(0.8).timeout
	t.expect(merged_finished.value, "merged hand discard animation finishes")
	table._refresh()
	for tile in view.hand_boxes[table.human_seat].get_children():
		t.expect(tile.tile == player.concealed[int(tile.get_meta("concealed_index"))], "merged discard keeps subsequent touch indices correct")
	view._restore_own_hand()
	player.concealed.assign(hand)
	table._refresh()
	t.expect(not view._restore_button.visible and view._local_arrangement.is_empty(), "Restore returns to default sorting")
	# Reported-ready players may inspect splits, never hypothetical exchanges.
	player.ready = true
	player.passed_win_until_draw = true
	table._refresh()
	view._sort_own_hand()
	deadline = Time.get_ticks_msec()+5000
	while view._arrangement_thread != null and Time.get_ticks_msec()<deadline:
		await process_frame
	t.expect(view._arrangement_choices.all(func(choice): return not choice.has("change_from")), "ready locks reject even an old background exchange result")
	t.expect(view._arrangement_caption.text.contains("本局只能自摸"), "ready pass-win restriction is visible")
	await _capture("sorting-ready-passed-win")
	view._restore_own_hand()
	player.ready = false
	player.passed_win_until_draw = false
	# All four viewers share the same local sorting and authoritative indices.
	var fixed: Array = []
	var original_seat: int = table.human_seat
	for count in range(1, 5):
		fixed.append({"kind": "pung", "tile": "tiao" + str(count)})
		player.melds.assign(fixed)
		player.concealed.assign(hand.slice(3 * count))
		for viewer in 4:
			table.human_seat = viewer
			view.human_seat = viewer
			var current = table.round.players[viewer]
			current.concealed.assign(hand.slice(3 * count))
			current.melds.assign(fixed)
			current.just_drew = ""
			current.ready = true
			view._local_arrangement = {}
			view.refresh()
			view._sort_own_hand()
			t.expect(view._sort_button.visible and not view._sort_button.disabled and not view._local_arrangement.is_empty(), "every seat can sort 10/7/4/1 concealed tiles")
			for tile in view.hand_boxes[viewer].get_children():
				t.expect(tile.tile == current.concealed[int(tile.get_meta("concealed_index"))], "melded sorting retains authoritative touch indices")
			current.concealed.append("tong9")
			current.just_drew = "tong9"
			view.refresh()
			view._sort_own_hand()
			t.expect(view._sort_button.visible and view.draw_boxes[viewer].get_child_count() == 0
				and view.hand_boxes[viewer].get_child_count() == current.concealed.size(), "draw after a meld can merge into the arranged hand")
			t.expect(view.hand_boxes[viewer].get_children().filter(func(tile): return tile.get_meta("drawn", false)).size() == 1, "merged ready hand still identifies only the new tile as discardable")
			if viewer == original_seat: await _capture("sorting-%d-melds-with-draw" % count)
			view._restore_own_hand()
			current.concealed.pop_back()
			current.just_drew = ""
			current.ready = false
	table.human_seat = original_seat
	view.human_seat = original_seat
	player.melds.clear()
	player.concealed.assign(hand)
	table._refresh()
	var action_id: int = view._begin_visual_action()
	view._refresh_hand_arrangement()
	t.expect(view._sort_button.visible and view._sort_button.disabled, "animation disables Sort without hiding it")
	view._complete_visual_action(action_id, Callable())
	table._refresh()
	for ready in [false, true]:
		view._restore_own_hand()
		player.concealed.assign(_wan("11122233344455"))
		player.just_drew = "wan5"
		player.ready = ready
		player.passed_self_draw = false
		table.round.current_turn = table.human_seat
		table.round.awaiting = true
		table._table_actions.auto_ready_enabled = false
		table._table_actions._selecting = true
		table._refresh()
		view._sort_own_hand()
		t.expect(player.passed_self_draw and not table.round.legal_turn_options(table.human_seat).self_win, "Sort passes this self-win through the authoritative turn action")
		t.expect(not player.passed_win_until_draw, "passing own draw does not impose the ready discard-win lock")
		t.expect(view.hand_boxes[table.human_seat].get_child_count() == 14 and view.draw_boxes[table.human_seat].get_child_count() == 0, "winning draw is merged after sorting")
		await _capture("sorting-passed-self-win-%s" % str(ready))
		view._restore_own_hand()
		t.expect(not table.round.legal_turn_options(table.human_seat).self_win, "Restore does not restore a passed self-win")
	player.ready = false
	player.passed_self_draw = false
	player.concealed.assign(hand)
	player.just_drew = ""
	table.round.awaiting = false
	table._table_actions._selecting = false
	table._refresh()

	view.animate_dice(6, 6)
	controller._dice_pending = true
	controller._process(0.0)
	t.expect(is_instance_valid(view._dice_red), "dealer has all dealt tiles and dice remain visible")

	if DisplayServer.get_name() != "headless":
		view._sort_own_hand()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/feedback-next")
		t.expect(root.get_texture().get_image().save_png("res://build/feedback-next/hand-arrangement.png") == OK, "capture sort and restore controls")
		deadline = Time.get_ticks_msec()+5000
		while view._arrangement_thread != null and Time.get_ticks_msec()<deadline:
			await process_frame
		for i in view._arrangement_choices.size():
			view._sort_own_hand()
			if view._local_arrangement.has("change_from"):break
		t.expect(view._arrangement_caption.text.contains("若摸到") and view._arrangement_caption.text.contains("再打"), "hypothetical upgrade clearly distinguishes a future draw from the current hand")
		await RenderingServer.frame_post_draw
		t.expect(root.get_texture().get_image().save_png("res://build/feedback-next/hand-upgrade.png")==OK,"capture one-tile upgrade without changing real hand")
		table._sound_settings.open()
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		t.expect(root.get_texture().get_image().save_png("res://build/feedback-next/settings.png") == OK, "capture personal sorting preference")
		table._sound_settings.close(false)
	controller._dispatch_visual_event({"type": "discard", "seat": table.round.dealer_seat, "tile": "wan1"})
	t.expect(view._dice_red == null, "dice are removed before the dealer's first discard")
	table.queue_free()
	await H.quit_cleanly(self, t.finish("table_v2_hand_arrangement"))

func _wan(digits: String) -> Array:
	var hand: Array = []
	for digit in digits: hand.append("wan" + digit)
	return hand

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/feedback-next")
	t.expect(root.get_texture().get_image().save_png("res://build/feedback-next/%s.png" % label) == OK, "capture arrangement " + label)
