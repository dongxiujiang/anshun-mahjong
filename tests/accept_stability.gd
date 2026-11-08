extends SceneTree
const H := preload("res://tests/test_harness.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	await create_timer(16.0).timeout
	t.expect(table.round != null and table.round.players.size() == 4, "16秒后牌局状态完整")
	t.expect(table._new_areas != null and table._new_areas.is_visible_in_tree(), "16秒后V2牌桌仍可见")
	print("[stability] done")
	table.queue_free()
	await H.quit_cleanly(self, t.finish("accept_stability"))
