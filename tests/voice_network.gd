extends SceneTree
## Real ENet voice bursts at low FPS; samples are deterministic test audio.
const H := preload("res://tests/test_harness.gd")
const PCM := preload("res://scripts/online/OnlineVoiceChat.gd")
var t := H.new()

class Receiver extends GMEVoiceChat:
	var received := {}
	var samples_valid := true
	var seats := {}
	func play_packet(packet: PackedByteArray) -> void:
		received[PCM.packet_sequence(packet)] = true
		seats[PCM.packet_seat(packet)] = true
		samples_valid = samples_valid and packet.decode_s16(PCM.HEADER_BYTES) == 4096
		super.play_packet(packet)

func _initialize() -> void: call_deferred("_run")

func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(predicate.call())

func _send_frames(net: NetGameNode, first: int = 0, batches: int = 20) -> void:
	for batch in batches:
		for index in 5:
			var packet := PackedByteArray()
			packet.resize(PCM.PACKET_BYTES)
			packet[0] = 1
			packet[1] = 3
			packet.encode_u32(2, first + batch * 5 + index)
			for sample in PCM.FRAME_COUNT: packet.encode_s16(PCM.HEADER_BYTES + sample * 2, 4096)
			net.send_local_voice(packet)
		await create_timer(0.1).timeout

func _run() -> void:
	Engine.max_fps = 15
	var network := root.get_node("Network")
	network.reset()
	var host := OS.get_cmdline_user_args().has("--voice-host")
	var net: NetGameNode = network.net_node
	if host:
		t.expect(network.start_host(false, true, 7538, "86751234", "语音回归测试"), "voice test host opens")
	else:
		t.expect(network.start_client("127.0.0.1", 7538, "86751234"), "voice test client connects")
	if not t.expect(await _wait_until(func(): return net.lobby.get("seats", []).filter(func(s): return int(s.peer) > 0).size() == 2), "both human seats join"):
		quit(1)
		return
	var old_voice: Node = net.voice_chat
	old_voice.shutdown()
	old_voice.queue_free()
	var receiver := Receiver.new()
	net.add_child(receiver)
	net.voice_chat = receiver
	receiver.setup(net, true)
	receiver.status_changed.connect(net._on_microphone_status)
	net.set_ready(true)
	if not t.expect(await _wait_until(func(): return net.game.phase != RoundState.Phase.IDLE), "real game starts before voice relay"):
		quit(1)
		return
	if host:
		t.expect(await _wait_until(func(): return net.ack_text == "voice-client-sent"), "client burst finishes")
		# A reliable ACK can arrive before the final unreliable PCM packet.
		var received_all := await _wait_until(func(): return receiver.received.size() == 100)
		var missing: Array = range(100).filter(func(sequence): return not receiver.received.has(sequence))
		t.expect(received_all and receiver.samples_valid, "host receives all 100 PCM frames without corruption at 15 FPS (received=%d/100 valid=%s missing=%s)" % [receiver.received.size(), receiver.samples_valid, missing])
		t.expect(receiver.seats.keys() == [0], "host associates speech with the authenticated client seat")
		await _send_frames(net)
		t.expect(await _wait_until(func(): return net.ack_text == "voice-client-checked"), "client checks host playback")
		await _send_frames(net, 100, 2)
		t.expect(await _wait_until(func(): return net.ack_text == "voice-muted"), "client checks mute while receiving live packets")
		var previous := int(net._seat_peer[0])
		net.multiplayer.multiplayer_peer.disconnect_peer(previous)
		t.expect(await _wait_until(func(): return net.ack_text == "voice-rejoined" and int(net._seat_peer[0]) != previous), "guest reconnects to the same voice seat")
		await _send_frames(net, 110, 2)
		t.expect(await _wait_until(func(): return receiver.received.has(100)), "host receives the guest's fresh speech after reconnect")
		t.expect(await _wait_until(func(): return net.ack_text == "voice-restored"), "both peers check voice after reconnect")
	else:
		await _send_frames(net)
		net.rpc_id(1, "ack", "voice-client-sent")
		t.expect(await _wait_until(func(): return receiver.received.size() == 100), "client receives all 100 host PCM frames at 15 FPS")
		t.expect(receiver.samples_valid and receiver.seats.keys() == [1], "client receives intact audio tagged with host seat")
		receiver.set_speaker_enabled(1, false)
		net.rpc_id(1, "ack", "voice-client-checked")
		t.expect(await _wait_until(func(): return receiver.received.has(109)), "muted client still receives the host packets")
		t.expect(not receiver._fallback._playbacks.has(1), "live packets from the muted seat do not make sound")
		var original_peer := net.multiplayer.get_unique_id()
		net.rpc_id(1, "ack", "voice-muted")
		t.expect(await _wait_until(func(): return net._client_joined and not net._resume_sync_pending and net.multiplayer.get_unique_id() != original_peer),
			"client receives a fresh game snapshot before restoring voice")
		t.expect(not receiver.speaker_enabled(1), "seat mute survives reconnect")
		receiver.set_speaker_enabled(1, true)
		net.rpc_id(1, "ack", "voice-rejoined")
		await _send_frames(net, 100, 2)
		t.expect(await _wait_until(func(): return receiver._fallback._last_rx.get(1, -1) >= 110), "client plays newly received speech after reconnect and unmute")
		net.rpc_id(1, "ack", "voice-restored")
		await create_timer(0.3).timeout
	network.reset()
	await H.quit_cleanly(self, t.finish("voice_network"))
