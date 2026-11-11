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
	t.expect(wide[0].width > pattern[0].width and pattern[0].score > wide[0].score,
		"wide waits and high scoring patterns select different first layouts")
	var all_waits := {}
	for layout in wide:
		t.expect(Tiles.sort_hand(layout.cards) == hand, "every layout contains exactly the original tiles")
		all_waits.merge(layout.waits)
	t.expect(all_waits.size() == RuleEngine.waiting_tiles(hand, []).size(), "layouts cover all legal waits")
	var pairs := _wan("1122334455667")
	t.expect(ARRANGE.build(pairs, true)[0].lengths == [2, 2, 2, 2, 2, 2], "seven pairs keep six pairs and one single")
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
	t.expect(player.concealed == hand, "view sort leaves authoritative indices unchanged")
	var arranged: Array = view._local_arrangement.cards
	player.concealed.append("wan9")
	player.just_drew = "wan9"
	table._refresh()
	t.expect(not view._sort_button.visible and view._local_arrangement.cards == arranged, "separate draw keeps the arranged row")
	player.concealed.pop_back()
	player.just_drew = ""
	table._refresh()
	t.expect(view._local_arrangement.cards == arranged, "discarding the drawn tile does not reorder")
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
	t.expect(ARRANGE.retained_groups(before_insert, view._local_arrangement) >= 9, "insertion keeps existing complete groups")
	for tile in view.hand_boxes[table.human_seat].get_children():
		t.expect(tile.tile == player.concealed[int(tile.get_meta("concealed_index"))], "inserted tile and each touch target retain their real indices")
	view._restore_own_hand()
	t.expect(not view._restore_button.visible and view._local_arrangement.is_empty(), "Restore returns to default sorting")

	view.animate_dice(6, 6)
	controller._dice_pending = true
	controller._process(0.0)
	t.expect(is_instance_valid(view._dice_red), "dealer has all dealt tiles and dice remain visible")

	if DisplayServer.get_name() != "headless":
		view._sort_own_hand()
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build/feedback-next")
		t.expect(root.get_texture().get_image().save_png("res://build/feedback-next/hand-arrangement.png") == OK, "capture sort and restore controls")
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
