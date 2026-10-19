extends SceneTree
## Manual two-participant media probe. Requires test room 9999 to exist.

func _token(identity: String) -> String:
	var http := HTTPRequest.new()
	root.add_child(http)
	var err := http.request("https://mj.dongxiu.fun/livekit-token?room=9999&identity=%s&name=%s" % [identity, identity])
	if err != OK:
		return ""
	var r = await http.request_completed
	http.queue_free()
	if r[1] != 200:
		return ""
	return JSON.parse_string(r[3].get_string_from_utf8()).get("token", "")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var t0 = await _token("seat0")
	var t1 = await _token("seat1")
	if t0 == "" or t1 == "":
		print("TOKEN_FAILED")
		quit(2)
		return
	var a := LiveKitRoom.new()
	var b := LiveKitRoom.new()
	var a_ok := [false]
	var b_ok := [false]
	var subscribed := [false]
	a.connected.connect(func(): a_ok[0] = true)
	b.connected.connect(func(): b_ok[0] = true)
	b.track_subscribed.connect(func(track, _pub, _participant):
		if track.get_kind() == LiveKitTrack.KIND_AUDIO:
			subscribed[0] = true)
	a.connect_to_room("wss://mj.dongxiu.fun/livekit", t0, {})
	b.connect_to_room("wss://mj.dongxiu.fun/livekit", t1, {})
	for i in 100:
		await create_timer(0.1).timeout
		if a_ok[0] and b_ok[0]:
			break
	print("rooms=", a_ok[0], "/", b_ok[0])
	if not (a_ok[0] and b_ok[0]):
		quit(3)
		return
	var source := LiveKitAudioSource.create(48000, 1, 200)
	var track := LiveKitLocalAudioTrack.create("microphone", source)
	a.get_local_participant().publish_track(track, {})
	var frame := PackedFloat32Array()
	frame.resize(480)
	for i in 480:
		frame[i] = sin(i * 0.05) * 0.08
	for i in 20:
		source.capture_frame(frame, 48000, 1, 480)
		await create_timer(0.01).timeout
	for i in 30:
		await create_timer(0.1).timeout
		if subscribed[0]:
			break
	print("subscribed=", subscribed[0])
	track.mute()
	a.disconnect_from_room()
	b.disconnect_from_room()
	a = null
	b = null
	await create_timer(1.0).timeout
	quit(0 if subscribed[0] else 4)
