extends SceneTree

const SL := preload("res://rl_env/SlPolicyActor.gd")
const H := preload("res://tests/test_harness.gd")

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var raw := FileAccess.get_file_as_string("res://build/parity.json")
	var data = JSON.parse_string(raw)
	t.expect(data is Dictionary, "parity fixture loads")
	var actor = SL.new("res://build/ai_high/oracle_sl_mass/oracle_sl_weights.json", 2)
	var x := PackedFloat32Array()
	for value in data.x:
		x.append(float(value))
	var result: Array = actor._forward(x)
	t.expect(result.size() == 2, "actor forward returns policy/value")
	var policy: PackedFloat32Array = result[0]
	var mask: Array = data.mask
	var best := -1
	var best_score := -INF
	for code in policy.size():
		if int(mask[code]) == 0: continue
		if float(policy[code]) > best_score:
			best_score = float(policy[code])
			best = code
	var expected: Array = data.top
	t.expect(best == int(expected[0]), "GDScript inference argmax matches PyTorch: got=%d expected=%d" % [best, int(expected[0])])
	await H.quit_cleanly(self, t.finish("actor_parity"))
