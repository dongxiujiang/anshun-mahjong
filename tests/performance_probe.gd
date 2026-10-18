extends SceneTree
## Diagnostic-only probe. It measures CPU-side frame spikes and individual
## table/network operations. Rendering/GPU cost is not measurable headless.

const H := preload("res://tests/test_harness.gd")
var t := H.new()
var _samples: Array[float] = []

func _initialize() -> void:
	call_deferred("_run")

func _measure(label: String, count: int, callable: Callable) -> void:
	var times: Array[float] = []
	for i in count:
		var start := Time.get_ticks_usec()
		callable.call()
		times.append(float(Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	var total := 0.0
	for value in times: total += value
	print("[perf] %-32s n=%d avg=%.2fms p50=%.2f p95=%.2f max=%.2f" % [
		label, count, total / maxf(1.0, float(count)), times[int(times.size() * 0.5)],
		times[int(times.size() * 0.95)], times[-1]])

func _frame_stats(label: String, frames: Array[float]) -> void:
	if frames.is_empty():
		print("[perf] %s: no frames" % label)
		return
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	for value in frames: total += value
	var over33 := 0
	var over50 := 0
	var over100 := 0
	for value in frames:
		if value > 33.3: over33 += 1
		if value > 50.0: over50 += 1
		if value > 100.0: over100 += 1
	print("[perf] %-28s frames=%d avg=%.2fms p50=%.2f p95=%.2f p99=%.2f max=%.2f >33ms=%d >50ms=%d >100ms=%d" % [
		label, frames.size(), total / frames.size(), sorted[int(sorted.size() * 0.5)],
		sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)],
		sorted[-1], over33, over50, over100])

func _monitor_stats(label: String, values: Array[int]) -> void:
	if values.is_empty(): return
	var total := 0
	for value in values: total += value
	print("[perf] %-28s avg=%.1f max=%d" % [label, float(total) / values.size(), values.max()])

func _run() -> void:
	var started := Time.get_ticks_usec()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	print("[perf] table scene ready in %.1fms nodes=%d" % [
		float(Time.get_ticks_usec() - started) / 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	table.new_game()
	for _wait in 600:
		if table.round.phase == RoundState.Phase.PLAYING:
			break
		await process_frame

	_measure("table._refresh (unchanged)", 30, func(): table._refresh())
	_measure("prepare exposed layouts", 30, func(): table._prepare_exposed_layouts())
	_measure("refresh identity x4", 30, func():
		for seat in 4: table._player_tile_areas._refresh_identity(seat))

	var state: Dictionary = table.round.serialize_for_seat(1)
	_measure("serialize_for_seat", 20, func(): table.round.serialize_for_seat(1))

	var ai = AiPlayer.new("probe")
	var ai_seat: int = int(table.round.current_turn)
	if table.round.players.size() == 4 and table.round.phase == RoundState.Phase.PLAYING:
		_measure("AI decide_turn", 8, func(): ai.decide_turn(table.round, ai_seat))

	# Full table frame samples while AI turns run. This catches main-thread
	# stalls from refresh, animation setup, AI and serialization together.
	_samples.clear()
	var draw_calls: Array[int] = []
	var primitives: Array[int] = []
	var last := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		_samples.append(float(now - last) / 1000.0)
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		last = now
		if _samples.size() >= 900: break
	_frame_stats("table frame sample", _samples)
	_monitor_stats("draw calls", draw_calls)
	_monitor_stats("draw primitives", primitives)

	# Same frame sampler with four AI controllers and no UI animation. This
	# isolates synchronous AI/state work from rendering and table animations.
	var ai_round := RoundState.new()
	var ai_controllers: Array = []
	for seat in 4: ai_controllers.append(AiPlayer.new("AI%d" % seat))
	ai_round.controllers = ai_controllers
	ai_round.ai_delay_seconds = 0.0
	ai_round.ai_response_delay_seconds = 0.0
	ai_round.opening_delay_seconds = 0.0
	ai_round.randomize_seed()
	ai_round.start_round(0)
	await process_frame
	if ai_round.players.size() == 4 and ai_round.phase == RoundState.Phase.PLAYING:
		var mid_seat: int = int(ai_round.current_turn)
		_measure("AI decide_turn (midgame)", 12, func():
			ai_controllers[mid_seat].decide_turn(ai_round, mid_seat))
	_samples.clear()
	last = Time.get_ticks_usec()
	var ai_deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < ai_deadline:
		await process_frame
		var ai_now := Time.get_ticks_usec()
		_samples.append(float(ai_now - last) / 1000.0)
		last = ai_now
		if _samples.size() >= 900: break
	_frame_stats("all-AI logic", _samples)

	print("[perf] final nodes=%d objects=%d static_mb=%.1f video_mb=%.1f state_bytes=%d" % [
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0),
		var_to_bytes(state).size()])
	table.queue_free()
	await process_frame
	quit(0)
