extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.wall_remain = {0: 20}
	r.players[0].concealed = ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9", "wan9"]
	r.players[0].melds = [{"kind": "kong", "tile": "tiao1", "concealed": true}]
	r.players[0].discards = ["tong2"]
	r.players[0].discard_ids = [0]
	r.players[0].ready = false
	const WAIT := ["wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "tiao5", "tiao6", "tiao7", "tong4", "tong5", "tong6", "tong9"]
	for seat in range(1, 4):
		if seat != 2: r.players[seat].concealed = WAIT.duplicate()
		r.players[seat].discards = ["tiao1", "tong8"]
		r.players[seat].discard_ids = [0, 1]
		r.players[seat].ready = false
	r.players[3].ready = true
	r.round_meta.merge({"winner": 0, "self_draw": false, "discard_seat": 1, "flip_tile": "tiao1", "chicken_multiplier": 1}, true)
	
	var result := ScoringEngine.settle(r)
	print("deltas[0]: ", result.deltas[0])
	print("Items for seat 0:")
	for item in result.items[0]:
		print("  ", item.kind, " ", item.label, " ", item.amount)
	
	quit()
