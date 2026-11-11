extends "res://tests/table_v2_layout_guards.gd"

func _run() -> void:
	var deck = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(deck)
	deck.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	deck.size = G.DESIGN_SIZE
	await process_frame
	await _test_voice_hud_bounds(deck)
	deck.queue_free()
	await H.quit_cleanly(self, t.finish("table_v2_voice_names"))
