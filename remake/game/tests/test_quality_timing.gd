extends SceneTree
const Motion = preload("res://src/presentation/MotionConfig.gd")
const Reveal = preload("res://src/app/FlipChickenReveal.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Transition = preload("res://src/presentation/TableTransition.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL quality timing: ", message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for category in Motion.PRESETS.smooth:
		var smooth: Dictionary = Motion.section(category, "smooth")
		var detail: Dictionary = Motion.section(category, "detail")
		for key in smooth:
			if "duration" in key or "stagger" in key or key.ends_with("_in") or key.ends_with("_out") or key == "warmup_frames":
				check(smooth[key] == detail[key], "%s.%s has one timeline for all quality modes" % [category, key])
	for quality in ["smooth", "detail"]:
		Motion.set_quality(quality)
		var reveal := Reveal.new()
		root.add_child(reveal)
		var finished := []
		reveal.finished.connect(func(key): finished.append(key))
		check(reveal.present(quality, {"flip_tile": "tiao2", "winners": [1], "self_draw": true}, []), "start legal flip reveal")
		reveal._tween.pause()
		reveal._tween.custom_step(0.49)
		check(reveal._flip_tile_box.visible, "same face reveal time in " + quality)
		reveal._tween.custom_step(1.50)
		check(reveal.visible and finished.is_empty(), "no early settlement before two seconds in " + quality)
		reveal._tween.custom_step(0.02)
		check(not reveal.visible and finished == [quality], "automatic settlement at two seconds in " + quality)
		reveal.queue_free()
		var table := Table.new(false)
		var transition := Transition.new()
		root.add_child(table)
		root.add_child(transition)
		transition.begin(table, [], 1)
		transition._rendered = true
		transition._warmup_left = 0
		transition._process(0.30)
		check(not transition.active, "a slow rendered frame catches up without stretching the shared transition duration")
		transition.queue_free()
		table.queue_free()
		await process_frame
	Motion.set_quality("detail")
	print("Quality timing: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
