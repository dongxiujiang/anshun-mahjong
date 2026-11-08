extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	await create_timer(0.9).timeout
	table._table_layout._hide_legacy_table(table._player_tile_areas)
	await process_frame
	root.get_texture().get_image().save_png("res://build/opening_walls.png")
	print("[walls] seated=", table._new_areas._wall_layer.get_child_count())
	table.queue_free(); await process_frame; quit(0)
