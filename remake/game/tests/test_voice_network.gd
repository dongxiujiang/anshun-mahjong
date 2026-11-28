extends SceneTree
const Client = preload("res://src/network/GameClient.gd")
const Voice = preload("res://src/audio/VoiceController.gd")
var checks := 0
var failures := 0
var nodes: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func endpoint(label: String):
	var value := Client.new()
	value.name = label
	root.add_child(value)
	nodes.append(value)
	return value

func frames(count: int = 20) -> void:
	for step in count:
		await process_frame
		OS.delay_msec(1)

func until(predicate: Callable) -> bool:
	for step in 3000:
		if predicate.call(): return true
		await frames(1)
	return false

func audio_packet(sequence: int) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(966)
	packet[0] = 1
	packet[1] = 3 # An untrusted sender claims a different seat.
	packet.encode_u32(2, sequence)
	for i in 480: packet.encode_s16(6 + i * 2, int(sin(TAU * 440.0 * i / 24000.0) * 3000))
	return packet

func _run() -> void:
	var service = endpoint("VoiceAuthority")
	check(service.start_server("678901", 0, {}, "online"), "online authority starts")
	var a = endpoint("VoiceSouth")
	var b = endpoint("VoiceEast")
	var profile_a := {"player_id": "voice-a", "nickname": "甲", "mode": "online", "room_number": "678901"}
	var profile_b := {"player_id": "voice-b", "nickname": "乙", "mode": "online", "room_number": "678901"}
	a.connect_room("127.0.0.1", service.local_port, profile_a)
	check(await until(func(): return not a.view.is_empty()), "first voice endpoint authenticates")
	b.connect_room("127.0.0.1", service.local_port, profile_b)
	check(await until(func(): return not b.view.is_empty()), "second voice endpoint authenticates")
	if a.view.is_empty() or b.view.is_empty():
		await finish()
		return
	var own_received := []
	var received := []
	var resets := []
	a.voice_packet_received.connect(func(packet): own_received.append(packet))
	b.voice_packet_received.connect(func(packet): received.append(packet))
	b.voice_stream_reset.connect(func(seat): resets.append(seat))
	var original := audio_packet(10)
	a.send_local_voice(original)
	check(await until(func(): return not received.is_empty()), "synthetic PCM crosses real dedicated voice channel")
	check(own_received.is_empty(), "no server microphone echo")
	check(received[0][1] == 1 and received[0].slice(6) == original.slice(6), "authority rewrites claimed seat and preserves sound samples")
	check(resets == [1], "receiver initializes new authenticated speaker stream")
	a.send_local_voice(original)
	a.send_local_voice(audio_packet(9))
	a.send_local_voice(PackedByteArray([1, 1]))
	await frames()
	check(received.size() == 1, "duplicates, old sequence and malformed packets dropped")
	for sequence in range(11, 115):
		a.send_local_voice(audio_packet(sequence))
		await frames(1)
	await frames()
	check(received.size() <= 75 and received.size() > 2, "per-member rate cap limits relay without blocking normal speech")
	var ticket: Dictionary = a.ticket.duplicate(true)
	a._reset() # Exercise unannounced disconnect and authenticated recovery.
	await frames()
	a.connect_room("127.0.0.1", service.local_port, profile_a, ticket)
	check(await until(func(): return not a.view.is_empty() and not a.waiting_for_foreground_view()), "same speaker recovers identity and receives the foreground snapshot")
	var before := received.size()
	a.send_local_voice(audio_packet(0))
	check(await until(func(): return received.size() > before), "new authenticated connection can restart sequence at zero")
	check(resets == [1, 1], "recovery clears receiver jitter buffer instead of replaying old audio")
	var public_data: String = JSON.stringify(service.discovery_info())
	check(not public_data.contains(ticket.member_token), "microphone transport never publishes recovery secret")
	var mute_path := "user://test-network-mutes-%d.cfg" % Time.get_ticks_usec()
	var voice := Voice.new(mute_path)
	root.add_child(voice)
	voice.bind_client(b)
	check(voice.set_speaker_enabled(1, false, profile_a.player_id), "the receiver mutes this authenticated LAN player")
	check(a.move_to_empty_seat(2), "muted player requests an empty seat")
	check(await until(func(): return a.view.seat == 2 and b.view.room.seats[2].player_id == profile_a.player_id), "both connections observe the moved player")
	check(not voice._backend.speaker_enabled(2), "the backend mutes the player in the new seat")
	voice.queue_free()
	await frames()
	voice = Voice.new(mute_path)
	root.add_child(voice)
	nodes.append(voice)
	voice.bind_client(b)
	before = received.size()
	a.send_local_voice(audio_packet(1))
	check(await until(func(): return received.size() > before), "speaking after receiver restart still sends real ENet packets")
	check(not voice.speaker_enabled(2) and not voice._backend._rx.has(2), "the reloaded mute drops incoming sound from the chosen player")
	check(voice.set_speaker_enabled(2, true, profile_a.player_id), "this receiver restores that player's audio")
	a.send_local_voice(audio_packet(2))
	check(await until(func(): return voice._backend._rx.has(2)), "unmuting starts a new LAN receive queue")
	await _mic_indicators(service, a, b, voice, profile_a)
	DirAccess.remove_absolute(mute_path)
	await finish()

func _mic_indicators(service, a, b, listener, profile: Dictionary) -> void:
	var source := Voice.new(listener._mute_path + ".sender")
	root.add_child(source)
	nodes.append(source)
	source.bind_client(a)
	var seat: int = a.view.seat
	var ticket: Dictionary = a.ticket.duplicate(true)
	var instance: String = ticket.room_instance_id
	var old_source: int = source._backend.get_instance_id()
	check(not source.microphone_requested() and not listener.name_mic_active(seat), "new room starts with microphone off at both ends")
	check(source.set_microphone(true) and await until(func(): return listener.name_mic_active(seat)), "LAN capture through the dummy driver publishes the authenticated source to a real listener")
	var third = endpoint("SameNameListener")
	third.connect_room("127.0.0.1", service.local_port, {"mode": "online", "room_number": "678901", "player_id": "third", "nickname": profile.nickname})
	check(await until(func(): return not third.view.is_empty() and third.view.room.seats[seat].mic_active), "late join receives existing live-capture state before any audio packets")
	var other: int = third.view.seat
	third.report_mic_active(instance, other, true)
	check(await until(func(): return listener.name_mic_active(other)), "two same-name humans have independent microphone indicators")
	listener.set_speaker_enabled(seat, false, profile.player_id)
	check(listener.name_mic_active(seat) and not listener.speaker_enabled(seat) and listener.name_mic_active(other) and third.view.room.seats[seat].mic_active and source.recording, "personal mute stops listening without hiding the sender's actual microphone state")
	listener.set_speaker_enabled(seat, true, profile.player_id)
	b._command({"kind": "mic_active", "instance": instance, "seat": seat, "active": false})
	var bc: String = service._peer_connections[b._api.get_unique_id()]
	check(await until(func(): return service._last_requests.get(bc) == b._request_id) and listener.name_mic_active(seat), "authenticated peer cannot clear someone else's capture")
	source._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	a.set_application_away(true)
	check(await until(func(): return not listener.name_mic_active(seat)) and source.microphone_requested(), "background clears actual state on both ends and retains local consent")
	a.set_application_away(false)
	source._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not source.recording and a.waiting_for_foreground_view(), "foreground notification alone cannot restart capture before the authenticated snapshot")
	check(await until(func(): return listener.name_mic_active(seat)), "new active capture after foreground returns to other players")
	var capture_retired := []
	var remote_mic_cleared := []
	a.voice_connection_ended.connect(func(): capture_retired.append(not source.recording), CONNECT_ONE_SHOT)
	b.view_changed.connect(func(state):
		if not state.room.seats[seat].get("mic_active", false): remote_mic_cleared.append(true))
	service._peer.disconnect_peer(a._api.get_unique_id())
	check(await until(func(): return not capture_retired.is_empty() and not remote_mic_cleared.is_empty()) and capture_retired[0], "real transport loss immediately retires capture and clears remote microphone state, even with fast same-room recovery")
	source._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	a.set_application_away(true)
	a.connect_room("127.0.0.1", service.local_port, profile, ticket)
	check(await until(func(): return not a.view.is_empty() and b.view.room.seats[seat].connected), "original ticket recovers its stable member")
	source._backend_status(true, "旧回调", old_source)
	check(source.microphone_requested() and not source.recording and not listener.name_mic_active(seat), "recovery restores only intent and rejects a retired backend callback")
	a.set_application_away(false)
	source._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(await until(func(): return source.recording and listener.name_mic_active(seat)), "same-room consent restarts capture and republishes only after confirmation")
	var online = endpoint("OnlineMicAuthority")
	online.start_server("678901", 0)
	var next := profile.duplicate()
	next.mode = "online"
	old_source = source._backend.get_instance_id()
	a.connect_room("127.0.0.1", online.local_port, next)
	check(not source.recording and source._backend == null, "old capture stops as soon as transport closes, including during a new handshake")
	check(await until(func(): return not a.view.is_empty() and a.view.room.room_instance_id != instance), "another authoritative room with the same visible number is distinct")
	source._backend_status(true, "旧回调", old_source)
	check(not source.microphone_requested() and not a.view.room.seats[a.view.seat].mic_active and not source.name_mic_active(a.view.seat), "new room defaults off despite previous consent and a late old signal")
	var observer = endpoint("OnlineMicObserver")
	observer.connect_room("127.0.0.1", online.local_port, {"room_number": "678901", "player_id": "online-listener", "nickname": "旁听"})
	check(await until(func(): return not observer.view.is_empty()), "online observer joins the same real ENet authority")
	var new_instance: String = a.ticket.room_instance_id
	a._command({"kind": "mic_active", "instance": instance, "seat": a.view.seat, "active": true})
	var ac: String = online._peer_connections[a._api.get_unique_id()]
	check(await until(func(): return online._last_requests.get(ac) == a._request_id) and not online._host.public_room().seats[a.view.seat].mic_active, "an old room report cannot light a new room")
	# Desktop has no GME microphone. Exercise its report over real online transport separately from the native SDK fixture.
	a.report_mic_active(new_instance, a.view.seat, true)
	check(await until(func(): return observer.view.room.seats[a.view.seat].mic_active), "simulated GME capture confirmation is delivered by online authority")
	a.report_mic_active(new_instance, a.view.seat, false)
	check(await until(func(): return not observer.view.room.seats[a.view.seat].mic_active), "online capture loss clears the observer")
	a.report_mic_active(new_instance, a.view.seat, true)
	await until(func(): return observer.view.room.seats[a.view.seat].mic_active)
	var replacement = endpoint("ReauthenticatedMic")
	replacement.connect_room("127.0.0.1", online.local_port, next, a.ticket)
	check(await until(func(): return not replacement.view.is_empty() and not observer.view.room.seats[a.view.seat].mic_active), "replacing a live connection with its recovery ticket clears old capture")
	a.report_mic_active(new_instance, a.view.seat, true)
	check(await until(func(): return online._last_requests.get(ac) == a._request_id) and not online._host.public_room().seats[a.view.seat].mic_active, "superseded but still connected peer cannot relight the recovered seat")
	await until(func(): return not replacement.waiting_for_foreground_view())
	a._command({"kind": "presence", "instance": new_instance, "revision": 200, "away": true})
	check(await until(func(): return online._last_requests.get(ac) == a._request_id) and not online._host.public_room().seats[replacement.view.seat].away, "superseded transport cannot mark its replacement away")

func finish() -> void:
	for value in nodes: value.queue_free()
	await process_frame
	# The accelerated test loop can exit before the real mixer releases playback.
	var mixer_deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < mixer_deadline:
		await frames(1)
	print("Voice network: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
