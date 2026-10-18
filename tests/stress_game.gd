extends SceneTree
## Diagnostic stress harness: runs real table/AI rounds and records frame spikes.
## Run with a display for draw-call data; headless still measures CPU frame time.

const H := preload("res://tests/test_harness.gd")
const ROUNDS := 5
var t := H.new()

class TimedAi extends AiPlayer:
	var max_turn_ms := 0.0
	var max_response_ms := 0.0
	var slow_turns := 0
	var slow_responses := 0

	func decide_turn(round, seat: int) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result: Dictionary = super.decide_turn(round, seat)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		max_turn_ms = maxf(max_turn_ms, elapsed)
		if elapsed > 50.0: slow_turns += 1
		return result

	func decide_response(round, seat: int, source: int, tile: String, options: Dictionary) -> Dictionary:
		var started := Time.get_ticks_usec()
		var result: Dictionary = super.decide_response(round, seat, source, tile, options)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		max_response_ms = maxf(max_response_ms, elapsed)
		if elapsed > 50.0: slow_responses += 1
		return result

func _initialize() -> void:
	call_deferred("_run")

func _stats(label: String, frames: Array[float]) -> void:
	if frames.is_empty():
		print("[stress] %s: no frames" % label)
		return
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	var over16 := 0
	var over33 := 0
	var over50 := 0
	for value in frames:
		total += value
		if value > 16.7: over16 += 1
		if value > 33.3: over33 += 1
		if value > 50.0: over50 += 1
	print("[stress] %-20s frames=%d avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f >16.7=%d >33=%d >50=%d" % [
		label, frames.size(), total / frames.size(), sorted[int(sorted.size() * 0.5)],
		sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)],
		sorted[-1], over16, over33, over50])

func _run() -> void:
	# Skip the long opening animation; draw/discard/settlement stay at their
	# normal speed so the stress run still exercises presentation work.
	var config = root.get_node("GameConfig")
	config.animation_speed = "instant"
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame

	var all_frames: Array[float] = []
	var all_draws: Array[int] = []
	var rounds := 0
	for round_index in ROUNDS:
		table.new_game()
		var ai: Array = []
		for seat in 4: ai.append(TimedAi.new("StressAI%d" % seat))
		table.round.controllers = ai
		# Keep each action on its own frame; zero would run the whole round in
		# one synchronous chain and produce a meaningless first-frame spike.
		table.round.ai_delay_seconds = 0.01
		table.round.ai_response_delay_seconds = 0.01
		table.round.opening_delay_seconds = 0.0
		await process_frame
		table.round._ask_turn_actor()
		var frames: Array[float] = []
		var draws: Array[int] = []
		var last := Time.get_ticks_usec()
		var started := Time.get_ticks_msec()
		var settled_at := -1
		while Time.get_ticks_msec() - started < 12000:
			await process_frame
			var now := Time.get_ticks_usec()
			var delta := float(now - last) / 1000.0
			last = now
			frames.append(delta)
			all_frames.append(delta)
			if delta > 33.0:
				print("[stress] spike round=%d frame=%d delta=%.1f phase=%d settle_active=%s nodes=%d" % [
					round_index + 1, frames.size(), delta, int(table.round.phase),
					str(table._settlement_animation_controller.is_active()),
					int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
			var draw := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			draws.append(draw)
			all_draws.append(draw)
			if table.round.phase == RoundState.Phase.SETTLED:
				if settled_at < 0:
					settled_at = Time.get_ticks_msec()
				elif Time.get_ticks_msec() - settled_at > 900:
					break
			if frames.size() >= 2500:
				break
		rounds += 1
		_stats("round %d" % (round_index + 1), frames)
		var draw_total := 0
		var draw_max := 0
		for value in draws:
			draw_total += value
			draw_max = maxi(draw_max, value)
		var max_turn := 0.0
		var max_response := 0.0
		var slow_turns := 0
		var slow_responses := 0
		for controller in ai:
			max_turn = maxf(max_turn, controller.max_turn_ms)
			max_response = maxf(max_response, controller.max_response_ms)
			slow_turns += controller.slow_turns
			slow_responses += controller.slow_responses
		print("[stress] round %d nodes=%d draws_avg=%.1f draws_max=%d phase=%d sync_turn_max=%.1fms slow_turns=%d sync_resp_max=%.1fms slow_resp=%d tasks=%d results=%d cancelled=%d timeouts=%d fallbacks=%d snapshot_max=%.1fms compute_max=%.1fms apply_max=%.1fms" % [
			round_index + 1, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			float(draw_total) / maxf(1.0, float(draws.size())), draw_max, int(table.round.phase),
			max_turn, slow_turns, max_response, slow_responses,
			table.round.ai_tasks, table.round.ai_results, table.round.ai_cancelled,
			table.round.ai_timeouts, table.round.ai_fallbacks,
			table.round.ai_snapshot_max_ms, table.round.ai_compute_max_ms, table.round.ai_apply_max_ms])
		if table.round.phase != RoundState.Phase.SETTLED:
			print("[stress] round %d did not settle within budget pending=%s awaiting=%s current=%d controller=%s phase=%d tasks=%d results=%d timeouts=%d fallbacks=%d" % [
				round_index + 1, str(table.round._ai_pending), str(table.round.awaiting),
				table.round.current_turn, str(table.round.controllers[table.round.current_turn]),
				int(table.round.phase), table.round.ai_tasks, table.round.ai_results,
				table.round.ai_timeouts, table.round.ai_fallbacks])
			print("[stress] round %d response_stage=%d responders=%s awaiting_response=%s players=%s" % [
				round_index + 1, int(table.round._response_stage), str(table.round._pending_responders),
				str(table.round._awaiting_response), str(table.round.players.map(func(p): return [p.discards.size(), p.melds.size(), p.ready]))])

	_stats("all rounds", all_frames)
	var draw_total := 0
	var draw_max := 0
	for value in all_draws:
		draw_total += value
		draw_max = maxi(draw_max, value)
	print("[stress] rounds=%d nodes=%d draws_avg=%.1f draws_max=%d static_mb=%.1f video_mb=%.1f" % [
		rounds, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		float(draw_total) / maxf(1.0, float(all_draws.size())), draw_max,
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0)])
	table.queue_free()
	await process_frame
	quit(0)
