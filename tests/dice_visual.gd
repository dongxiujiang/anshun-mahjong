extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	for _i in 500:
		await process_frame
		if table._new_areas._dice_layer.get_child_count() >= 2: break
	await create_timer(0.12).timeout
	table._table_layout._hide_legacy_table(table._player_tile_areas)
	root.get_texture().get_image().save_png("res://build/dice_restored.png")
	print("[dice] v2_children=", table._new_areas._dice_layer.get_child_count(),
		" red=", table._new_areas._dice_red != null,
		" white=", table._new_areas._dice_white != null)
	table.queue_free(); await process_frame; quit(0)
