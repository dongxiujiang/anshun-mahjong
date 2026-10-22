extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var net := NetGameNode.new()
	var old := {"a": [1, 2], "d": {"x": 1, "y": 2}, "arr": [{"x": 1}], "gone": 1}
	var new := {"a": [1, 3], "d": {"x": 1, "z": 3}, "arr": [{"x": 1}, {"x": 2}], "added": true}
	var ops: Array = []
	net._build_state_delta(old, new, [], ops)
	var copy: Dictionary = old.duplicate(true)
	t.expect(net._apply_state_delta(copy, ops), "state delta applies cleanly")
	t.expect(copy == new, "state delta reproduces the full snapshot")
	t.expect(NetGameNode.HEARTBEAT_TIMEOUT_MS > NetGameNode.HEARTBEAT_INTERVAL_MS, "heartbeat timeout is longer than its interval")
	t.expect(net.has_method("heartbeat_ping") and net.has_method("heartbeat_pong"), "heartbeat RPCs exist")
	t.expect(net.has_method("sync_delta") and net.has_method("sync_delta_packed"), "delta RPCs exist")
	net.free()
	await H.quit_cleanly(self, t.finish("protocol_optimizations"))
