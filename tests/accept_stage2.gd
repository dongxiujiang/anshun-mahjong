extends SceneTree
const H := preload("res://tests/test_harness.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.opening_delay_seconds = 0.0
	for _i in 120: await process_frame
	table.round.cancel_opening()
	table.round.phase = RoundState.Phase.PLAYING
	table.round.current_turn = table.human_seat
	table.round.awaiting = false
	table._refresh()
	await create_timer(0.2).timeout
	var v2 = table._new_areas
	# 按钮层归属和位置。
	table._add_action("测试动作", Callable(table, "_refresh"))
	table._table_actions._layout_actions()
	await process_frame
	var bar = table._table_actions.action_bar
	print("[stage2] bar_parent=", bar.get_parent().name, " count=", bar.get_child_count(),
		" visible=", bar.visible, " pos=", bar.position)
	t.expect(bar.get_parent() == v2._action_layer, "按钮在 V2 层")
	t.expect(bar.visible and bar.get_child_count() >= 1, "按钮可见")
	# 真实响应动作：胡/碰/杠按钮生成。
	table._clear_actions()
	table._on_require_response(1, 0, "wan3",
		{"can_win": true, "can_pong": true, "can_kong": true})
	table._table_actions._layout_actions()
	await process_frame
	var action_texts: Array = []
	for child in bar.get_children(): action_texts.append(str(child.text))
	print("[stage2] actions=", action_texts, " visible=", bar.visible)
	t.expect(bar.visible and action_texts.size() >= 3, "胡碰杠按钮生成")
	t.expect("胡" in action_texts and "碰" in action_texts, "胡碰按钮存在")
	# 幺鸡/八筒必须进红牌层，不进普通弃牌层。
	for card in ["tiao1", "tong8"]:
		var before_red: int = v2._red_layer.get_child_count()
		var before_ord: int = v2._discard_layer.get_child_count()
		var p = table.round.players[table.human_seat]
		p.discards.append(card)
		p.discard_ids.append(p.discard_count)
		p.discard_count += 1
		var node: TileView = v2._tile(v2.hand_boxes[table.human_seat], card, true,
			Vector2(900, 800), 1.6, 0.0)
		v2._fly_discard(node, table.human_seat, card, Callable(v2, "_noop"))
		await create_timer(0.5).timeout
		var red_added: int = v2._red_layer.get_child_count() - before_red
		var ord_added: int = v2._discard_layer.get_child_count() - before_ord
		print("[stage2] ", card, " red+=", red_added, " ordinary+=", ord_added)
		t.expect(red_added == 1 and ord_added == 0, "%s 进红牌区" % card)
	# 结算阶段 V2 仍然是牌桌画面。
	table._table_animation_controller.cancel()
	table.round.phase = RoundState.Phase.SETTLED
	table._settlement_immediate = true
	table._refresh()
	await process_frame
	t.expect(v2.visible, "结算时 V2 仍显示")
	var settlement = table._settlement_animation_controller
	if DisplayServer.get_name() == "headless":
		t.expect(settlement.layer.visible, "旧版结算动画层显示")
		t.expect(settlement.boards.size() == 4, "结算显示四家相对分卡片")
		t.expect(settlement.payment_labels.size() == 4, "结算显示四家相对付款")
	else:
		t.expect(not settlement.has_started() and settlement.boards.is_empty(), "图形模式没有旧版结算卡")
		t.expect(v2._native_settlement is Panel and v2._native_settlement.visible, "V2显示个人结算面板")
		t.expect(v2._settlement_score_rows.size() == 3, "面板有我的分数、对方分数及差值")
		t.expect(not v2._discard_layer.visible, "结算面板替换弃牌区")
		t.expect(not root.get_node("FpsOverlay")._label.visible, "结算时帧率文字避让下一局按钮")
	await create_timer(0.55).timeout
	if DisplayServer.get_name() != "headless":
		var image := root.get_texture().get_image()
		if image != null:
			image.save_png("res://build/v2_personal_settlement.png")
	await process_frame
	t.expect(table._settlement_card._post_controls.visible, "结算按钮层显示")
	t.expect(table._settlement_card._next_round_button.visible, "下一局按钮显示")
	if DisplayServer.get_name() != "headless":
		t.expect(table._settlement_card._post_controls.position.y > TableV2Geometry.HAND_BOTTOM, "下一局在手牌下方")
	print("[stage2] settled v2_visible=", v2.visible,
		" post=", table._settlement_card._post_controls.visible,
		" next=", table._settlement_card._next_round_button.visible)
	table._refresh_next_round_controls()
	await process_frame
	var next_button = table._settlement_card._next_round_button
	print("[stage2] next_disabled=", next_button.disabled)
	t.expect(not next_button.disabled, "结算完成后下一局可点")
	next_button.pressed.emit()
	await create_timer(0.5).timeout
	print("[stage2] phase_after_next=", table.round.phase)
	t.expect(table.round.phase != RoundState.Phase.SETTLED, "点击下一局开新局")
	if DisplayServer.get_name() != "headless":
		t.expect(v2._discard_layer.visible and root.get_node("FpsOverlay")._label.visible, "新局恢复弃牌区和帧率")
	table.queue_free(); await H.quit_cleanly(self, t.finish("accept_stage2"))
