extends SceneTree

func _initialize() -> void:
	var instance = ClassDB.instantiate("LiveKitAudioProcessingModule")
	print("apm instance=", instance)
	var module = instance.call("create", {"echo_cancellation": true, "noise_suppression": true, "high_pass_filter": true, "auto_gain_control": true})
	print("apm module=", module)
	var frame := PackedFloat32Array()
	frame.resize(480)
	for i in 480:
		frame[i] = sin(float(i) * 0.1) * 0.1
	print("reverse=", module.call("process_reverse_stream", frame, 48000, 1))
	var out = module.call("process_stream", frame, 48000, 1)
	print("processed_size=", out.size())
	quit(0 if out.size() == 480 else 1)
