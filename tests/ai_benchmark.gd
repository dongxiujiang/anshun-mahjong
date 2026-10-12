extends SceneTree
## Paired seeds, one upgraded AI against three frozen previous AIs, rotating
## the upgraded seat. Small diagnostic sample; not a statistical strength rank.
const H := preload("res://tests/test_harness.gd")
const BEFORE := preload("res://tests/fixtures/ai_before_value_model.gd")
const DEFAULT_SEEDS := [20117, 31033, 47051, 59063]
var seeds: Array = DEFAULT_SEEDS.duplicate()
var report_name := "ai_benchmark"
var t := H.new()
var results: Array = []
var timings: Array = []
var slow_actions: Array = []

class MeasuredAi extends AiPlayer:
	var times: Array = []
	var slow_actions: Array = []
	func decide_turn(round, seat: int) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result := super.decide_turn(round, seat)
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		times.append(elapsed)
		if elapsed > 250.0:
			slow_actions.append({"ms": elapsed, "seat": seat, "hand": round.players[seat].concealed.duplicate(),
				"melds": round.players[seat].melds.duplicate(true), "candidates": last_analysis.size(), "action": result})
		return result
	func decide_response(round, seat: int, source: int, tile: String, options: Dictionary) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result := super.decide_response(round, seat, source, tile, options)
		times.append((Time.get_ticks_usec() - started) / 1000.0)
		return result

func _initialize() -> void: call_deferred("_run")

func _play(seed_value: int, upgraded_seat: int) -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(seed_value)
	for seat in 4: r.controllers.append(MeasuredAi.new() if seat == upgraded_seat else BEFORE.new())
	r.start_round(0)
	t.expect(r.phase == "settled" and is_zero_approx(r.last_result.total_delta), "Benchmark round settles with zero-sum payments")
	var counts := {}
	for player in r.players:
		for tile in player.concealed + player.discards:
			counts[tile] = int(counts.get(tile, 0)) + 1
		for meld in player.melds:
			counts[meld.tile] = int(counts.get(meld.tile, 0)) + (3 if meld.kind == "pung" else 4)
	var tiles := 0
	for count in counts.values():
		tiles += int(count)
		t.expect(int(count) <= 4, "Benchmark never creates a fifth physical tile")
	t.expect(tiles + r.wall.remaining == 108, "Benchmark conserves all 108 tiles")
	if upgraded_seat >= 0:
		timings.append_array(r.controllers[upgraded_seat].times)
		slow_actions.append_array(r.controllers[upgraded_seat].slow_actions)
	return r

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds.clear()
			for value in argument.trim_prefix("--seeds=").split(","): seeds.append(int(value))
		if argument.begins_with("--report="): report_name = argument.trim_prefix("--report=").get_file().get_basename()
	var wins := 0
	var deal_ins := 0
	var draws := 0
	var net := 0.0
	var paired_gain := 0.0
	for seed_value in seeds:
		var baseline := _play(seed_value, -1)
		for seat in 4:
			var r := _play(seed_value, seat)
			var delta := float(r.last_result.deltas[seat])
			var winner := int(r.round_meta.winner)
			var deal_in: bool = winner >= 0 and not r.round_meta.self_draw and int(r.round_meta.discard_seat) == seat
			if winner == seat: wins += 1
			if winner < 0: draws += 1
			if deal_in: deal_ins += 1
			net += delta
			paired_gain += delta - float(baseline.last_result.deltas[seat])
			results.append({"seed": seed_value, "seat": seat, "net": delta, "previous_net_same_seat": baseline.last_result.deltas[seat], "winner": winner, "deal_in": deal_in})
			print("[ai_benchmark] seed %d seat %d: net %.0f, baseline %.0f, winner %d" % [seed_value, seat, delta, baseline.last_result.deltas[seat], winner])
	timings.sort()
	var report := {"games": results.size(), "baseline_games": seeds.size(), "wins": wins, "deal_ins": deal_ins, "draws": draws,
		"mean_net": net / results.size(), "mean_paired_gain": paired_gain / results.size(), "decisions": timings.size(),
		"mean_ms": timings.reduce(func(a, b): return a + b, 0.0) / maxi(1, timings.size()),
		"p95_ms": timings[int(0.95 * (timings.size() - 1))], "max_ms": timings[-1], "results": results, "slow_actions": slow_actions}
	var file := FileAccess.open("res://build/test_results/%s.json" % report_name, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[ai_benchmark] games=%d wins=%d deal_ins=%d mean_net=%.2f mean_ms=%.1f p95_ms=%.1f max_ms=%.1f" % [results.size(), wins, deal_ins, report.mean_net, report.mean_ms, report.p95_ms, report.max_ms])
	t.expect(not timings.is_empty(), "Upgraded AI made real decisions")
	quit(t.finish("ai_benchmark"))
