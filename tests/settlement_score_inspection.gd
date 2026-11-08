extends "res://tests/settlement_animation_flow.gd"
## V2 迁移版：结算卡/评分标注/按钮层必须挂在 TableV2 的 SettlementLayer 上。
## 深层逐项金额仍由 scoring_chat_cases / settlement_animation_flow 覆盖。

func _run() -> void:
	var master := AudioServer.get_bus_index("Master")
	var was_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var r := _fixture("mixed")
	var before := _snapshot(r)
	_bind(r)
	var c = table._settlement_animation_controller
	var a = c.score_annotations
	table._new_areas.adopt_settlement_node(c.layer)
	table._new_areas.adopt_settlement_node(table._settlement_card._post_controls)
	c.refresh_layout()
	t.expect(c.is_completed() and c.boards.size() == 4, "V2结算完成并生成四家boards")
	t.expect(c.payment_labels.size() == 4, "V2结算生成四家两两付款标签")
	t.expect(c.layer.get_parent() == table._new_areas._settlement_layer,
		"结算动画层位于V2 SettlementLayer")
	t.expect(a.groups.size() > 0, "V2结算标注组已生成")
	if not a.groups.is_empty():
		var group = a.groups[0]
		a.select_group(group.id)
		a.refresh()
		t.expect(a.selected_id == group.id, "V2选中标注组")
	table._settlement_card.show_post_settlement_controls()
	await process_frame
	t.expect(table._settlement_card._post_controls.get_parent() == table._new_areas._settlement_layer,
		"结算按钮层位于V2 SettlementLayer")
	t.expect(table._settlement_card._post_controls.visible, "V2结算按钮层显示")
	t.expect(_snapshot(r) == before, "V2结算检查不修改分数或付款")
	table.free()
	await process_frame
	AudioServer.set_bus_mute(master, was_muted)
	await H.quit_cleanly(self, t.finish("settlement_score_inspection"))
