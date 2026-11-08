extends SceneTree
const H := preload("res://tests/test_harness.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.new_game(true)
	await process_frame
	t.expect(table.round.dealer_seat == table.human_seat, "单机第一局南方玩家坐庄")
	t.expect(table.round.dealer_seat == 1, "南方座位为1")
	table.queue_free()
	await process_frame
	quit(t.finish("single_dealer_check"))
