extends SceneTree
## Fixed-seed normal-pace baseline (0.8s AI turn, 0.18s claim beat, full
## opening and settlement). Run serially; do not run beside other tests.

const H := preload("res://tests/test_harness.gd")
const SEED := 20261019
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _stats(label: String, frames: Array[float]) -> void:
	if frames.is_empty():
		print("[baseline] %s no frames" % label)
		return
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	var over16 := 0
	var over33 := 0
	var over50 := 0
	var over100 := 0
	for value in frames:
		total += value
		if value > 16.7: over16 += 1
		if value > 33.3: over33 += 1
		if value > 50.0: over50 += 1
		if value > 100.0: over100 += 1
	print("[baseline] %-14s frames=%d avg=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.2f >16.7=%d >33=%d >50=%d >100=%d" % [
		label, frames.size(), total / frames.size(), sorted[int(sorted.size() * 0.5)],
		sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)],
		sorted[-1], over16, over33, over50, over100])

func _run() -> void:
	var round := RoundState.new()
	round.set_rng_seed(SEED)
	round.build_players(0)
	var ai: Array = []
	for seat in 4: ai.append(AiPlayer.new("BaselineAI%d" % seat))
	round.controllers = ai
	round.ai_delay_seconds = 0.8
	round.ai_response_delay_seconds = 0.18
	round.opening_delay_seconds = 1.0
	round.start_round(0)

	var opening: Array[float] = []
	var playing: Array[float] = []
	var settlement: Array[float] = []
	var current := opening
	var last := Time.get_ticks_usec()
	var started := Time.get_ticks_msec()
	var saw_playing := false
	while Time.get_ticks_msec() - started < 120000:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := float(now - last) / 1000.0
		last = now
		current.append(delta)
		if round.phase == RoundState.Phase.PLAYING and not saw_playing:
			saw_playing = true
			current = playing
		if round.phase == RoundState.Phase.SETTLED:
			if current != settlement:
				settlement.append(delta)
				current = settlement
				# Give the settlement presentation one second of samples.
				await create_timer(1.0).timeout
				break
	_stats("opening", opening)
	_stats("playing", playing)
	_stats("settlement", settlement)
	print("[baseline] settled=%s phase=%d seed=%d" % [str(round.phase == RoundState.Phase.SETTLED), int(round.phase), SEED])
	quit(t.finish("perf_baseline"))
