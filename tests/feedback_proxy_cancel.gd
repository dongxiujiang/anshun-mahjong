extends SceneTree
const H = preload("res://tests/test_harness.gd")
var t = H.new()
class ControlledWorker extends "res://scripts/core/AiTurnWorker.gd":
	var started := Semaphore.new()
	var release := Semaphore.new()
	func _compute(_job: Dictionary) -> Dictionary:
		started.post()
		release.wait()
		return {"discard": "wan1"}
func _initialize(): call_deferred("run")
func run():
	var worker = ControlledWorker.new()
	worker._start()
	var token: int = worker._submit({})
	worker.started.wait()
	worker.cancel(token)
	worker.release.post()
	await create_timer(0.1).timeout
	t.expect(worker.take_result(token).is_empty(), "cancelled token cannot publish a late decision")
	worker.stop()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null,null,null,null]
	table.round.cancel_opening()
	table._table_animation_controller.cancel()
	table._table_animation_controller._dealt = [13,13,13,13]
	table.round.phase = RoundState.Phase.PLAYING
	table.round.current_turn = table.human_seat
	table.round.awaiting = true
	var view = table._new_areas
	view.auto_sort_hands = false
	view._sort_started = true
	root.get_node("Network").mode = "host"
	table.set_process(false)
	var sent := {"count":0}
	table.enable_net(func(_decision): sent.count+=1, func(_tile,_decision): sent.count+=1)
	table.toggle_ai_proxy()
	view.animate_draw(table.human_seat,"wan2",53,func():pass)
	table._auto_test_poll_online()
	t.expect(table._ai_proxy_task == 0, "proxy waits for drawing animation")
	var pending = ControlledWorker.new()
	pending._start()
	table._ai_proxy_worker = pending
	table._ai_proxy_task = pending._submit({})
	pending.started.wait()
	table.toggle_ai_proxy()
	t.expect(not table._ai_proxy_active and table._ai_proxy_task == 0, "cancel clears proxy immediately")
	pending.release.post()
	await create_timer(0.5).timeout
	table._poll_ai_proxy()
	t.expect(sent.count == 0, "no stale auto action after cancellation")
	t.expect(not view.native_actions_pending(), "cancelling proxy lets active animation finish")
	t.expect(table._table_actions._selecting, "manual turn is restored")
	root.get_node("Network").mode = ""
	table.queue_free()
	await H.quit_cleanly(self,t.finish("feedback_proxy_cancel"))
