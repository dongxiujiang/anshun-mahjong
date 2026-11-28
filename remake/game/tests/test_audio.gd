extends SceneTree

const Pcm = preload("res://src/audio/OnlineVoiceChat.gd")
const Gme = preload("res://src/audio/GMEVoiceChat.gd")
const Voice = preload("res://src/audio/VoiceController.gd")
const Stage = preload("res://src/audio/SoundStage.gd")
const RoundCore = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Clock = preload("res://src/session/TurnClock.gd")

class Client extends Node:
	signal view_changed(view: Dictionary)
	signal session_ended(reason: String)
	signal voice_connection_ended()
	signal voice_packet_received(packet: PackedByteArray)
	signal voice_stream_reset(seat: int)
	var view := {}
	var ticket := {}
	var sent := []
	var microphone_reports := []
	func send_local_voice(packet): sent.append(packet)
	func waiting_for_foreground_view(): return false
	func report_mic_active(instance: String, seat: int, active: bool):
		microphone_reports.append([instance, seat, active])

class Native extends RefCounted:
	var mic := false
	var speaker := false
	var fail_mic := false
	var ignore_enable := false
	var muted := {}
	func EnableMic(value): mic = value and not fail_mic and not ignore_enable; return 1 if fail_mic and value else 0
	func GetMicState(): return int(mic)
	func EnableSpeaker(value): speaker = value; return 0
	func SetMicVolume(_value): return 0
	func SetSpeakerVolume(_value): return 0
	func SetSpeakerVolumeByOpenID(_id, _value): return 0
	func RemoveAudioBlackList(id): muted.erase(id)
	func AddAudioBlackList(id): muted[id] = true
	func GetMicLevel(): return 8 if mic else 0
	func GetSpeakerLevel(): return 0

class Context extends RefCounted:
	var audio := Native.new()
	var entered := true
	func Poll(): pass
	func IsRoomEntered(): return entered
	func GetAudioCtrl(): return audio
	func Pause(): return 0
	func Resume(): return 0
	func ExitRoom(): entered = false
	func Uninit(): pass

var failures := 0
var checks := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(text)

func packet(seat: int, sequence: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(Pcm.PACKET_BYTES)
	data[0] = 1
	data[1] = seat
	data.encode_u32(2, sequence & 0xffffffff)
	data.encode_s16(6, 8000)
	return data

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var buses := AudioServer.bus_count
	var client := Client.new()
	var mute_path := "user://test-audio-mutes-%d.cfg" % Time.get_ticks_usec()
	var voice := Voice.new(mute_path)
	var stage := Stage.new()
	for node in [client, voice, stage]:
		root.add_child(node)
	voice.bind_client(client)
	stage.bind_client(client, voice)
	check(not voice.recording and not stage._music.playing, "mic and music default off")
	check(not voice.set_directory_url("http://example.com") and not voice.set_directory_url("https://a.com@b.com") and voice.set_directory_url("https://example.com/service"), "GME auth only uses the chosen HTTPS directory")
	var rows := []
	for i in 4:
		rows.append({"connected": true, "player_id": "player" + str(i), "voice_pack": ["huaqiang", "wangye", "nvyou", "wenrou"][i]})
	var room := {"mode": "online", "room_number": "2501", "room_instance_id": "fixed", "round_number": 1, "seats": rows}
	var state := {"room": room, "seat": 0, "round": {"phase": "turn", "turn": 0, "audio_events": [{"id": 3, "seat": 0, "clip": "wan1"}]}}
	client.view = state
	client.view_changed.emit(state)
	check(voice.available() and not voice.microphone_requested() and stage._last_event == 3 and not stage._speech.playing, "join restores event cursor and starts silent")
	client.voice_packet_received.emit(packet(0, 1))
	var pcm = voice._backend
	check(pcm._rx.is_empty(), "local echo ignored")
	client.voice_packet_received.emit(packet(1, 0xffffffff))
	client.voice_packet_received.emit(packet(1, 1))
	client.voice_packet_received.emit(packet(1, 0))
	client.voice_packet_received.emit(packet(1, 1))
	check(pcm._rx[1].packets.size() == 3 and pcm._rx[1].packets.has(0x100000001), "jitter queue reorders and deduplicates across uint32 wrap")
	pcm._rx[1].started -= 100
	pcm._drain_playback()
	check(pcm._rx[1].next == 0x100000002 and pcm._rx[1].packets.is_empty(), "three frames actually pushed through the generator")
	client.voice_packet_received.emit(packet(1, 1))
	check(pcm._rx[1].packets.is_empty(), "old frame cannot replay")
	client.voice_packet_received.emit(packet(1, 3))
	pcm._drain_playback()
	check(not pcm._rx[1].packets.is_empty(), "missing sequence allows a bounded reorder delay")
	pcm._rx[1].gap_since -= 100
	pcm._drain_playback()
	check(pcm._rx[1].next == 0x100000004, "ongoing arrivals cannot hold a missing frame forever")
	for n in 20:
		client.voice_packet_received.emit(packet(2, n))
	check(pcm._rx[2].packets.size() <= Pcm.MAX_QUEUED_PACKETS, "bounded backlog")
	client.voice_stream_reset.emit(1)
	check(not pcm._rx.has(1), "new transport epoch flushes old sound")
	voice.set_speaker_enabled(2, false)
	client.voice_packet_received.emit(packet(2, 21))
	check(not voice.speaker_enabled(2) and not pcm._rx.has(2), "mute stops generator and queued speech")
	rows[2].player_id = "replacement"
	client.view_changed.emit(state)
	check(voice.speaker_enabled(2), "seat replacement does not inherit former player's mute")
	var bad_packet := packet(1, 4)
	bad_packet.resize(12)
	client.voice_packet_received.emit(bad_packet)
	check(not pcm._rx.has(1), "invalid PCM lengths ignored")
	pcm.permission_pending = true
	voice._permission_result("android.permission.RECORD_AUDIO", false)
	check(not voice.recording and not pcm.permission_pending and voice.message.contains("未授予"), "denial immediately clears pending microphone status")
	voice._permission_result("android.permission.RECORD_AUDIO", true)
	check(not voice.recording, "late grant cannot turn on cancelled microphone")
	pcm.permission_pending = true
	voice._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	voice._permission_result("RECORD_AUDIO", false)
	voice._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not voice.recording and not voice.microphone_requested(), "denial while Android permission dialog backgrounds app stays denied after resume")
	pcm.permission_pending = true
	pcm.status_changed.emit(false, "等待麦克风权限")
	check(voice.microphone_requested() and not voice.name_mic_active(0) and client.microphone_reports.is_empty(), "waiting permission is a cancellable request and never an active microphone")
	voice.set_microphone(false)
	voice._permission_result("RECORD_AUDIO", true)
	check(not voice.microphone_requested() and not voice.name_mic_active(0), "cancelling a pending request excludes late permission grants")
	check(voice.set_microphone(true) and voice.recording, "explicit toggle creates a microphone stream with the dummy driver")
	pcm.status_changed.emit(true, "麦克风已开启")
	check(voice.name_mic_active(0) and client.microphone_reports == [["fixed", 0, true]], "only a backend state transition publishes capture, exactly once")
	pcm._mic_player.stop()
	pcm._process(0)
	check(not voice.name_mic_active(0) and client.microphone_reports.back() == ["fixed", 0, false], "stopped capture turns the public status off without waiting for another click")
	voice.set_microphone(true)
	voice._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(not voice.recording and voice.microphone_requested() and pcm._rx.is_empty(), "background stops PCM capture and audio queue")
	voice._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(voice.recording, "foreground restores user's explicit setting")
	voice.set_microphone(false)
	stage.configure({"music": true, "music_volume": 0.4, "effects_volume": 0.7, "voice_pack": "weilong"})
	check(stage._music.playing and stage._music.stream.get_length() > 100 and stage._music.stream.loop, "licensed recording actually loads and loops")
	state.round.audio_events.append({"id": 4, "seat": 0, "clip": "tong2"})
	client.view_changed.emit(state)
	check(stage._speech.playing and stage._effects.playing and stage._speech.stream.get_length() > 0.1, "new discard starts recorded announcement and tile sound")
	check(stage._speech.stream == stage._stream("voice_packs/huaqiang/tong2.wav"), "own announcements use the authoritative seat pack")
	rows[0].voice_pack = "wenrounv"
	client.view_changed.emit(state)
	check(stage._queue.is_empty() and stage._last_event == 4, "profile update does not enqueue the old announcement")
	state.round.audio_events.append({"id": 5, "seat": 1, "clip": "tong2"})
	state.round.audio_events.append({"id": 6, "seat": 0, "clip": "tong2"})
	rows[2].voice_pack = "../invalid"
	state.round.audio_events.append({"id": 7, "seat": 2, "clip": "tong2"})
	client.view_changed.emit(state)
	check(stage._queue.map(func(item): return item.pack) == ["wangye", "wenrounv", "luoxiaohei"], "future announcements use the remote pack, updated self pack, and safe fallback")
	stage._process(0)
	check(is_equal_approx(stage._effects.volume_db, linear_to_db(0.7) + Stage.DUCK_DB), "speaking lowers table effects")
	pcm._active_until = Time.get_ticks_msec() + 50
	stage._process(0)
	check(is_equal_approx(stage._speech.volume_db, linear_to_db(0.8) + Stage.DUCK_DB), "live chat takes precedence over recorded announcements")
	pcm._active_until = 0
	stage._process(0)
	check(is_equal_approx(stage._speech.volume_db, linear_to_db(0.8)), "shout volume returns after live speech")
	var clock := Clock.new("fixed")
	clock.begin_prompt(1, 8, Clock.Kind.DISCARD, [0], 10000)
	clock.animation_finished(1, 8, 0, 2000)
	for now in [8999, 9000, 11999, 12000, 16999, 17000, 18000]:
		state.clock = clock.timing_for(1, 8, 0, now)
		client.view_changed.emit(state)
		check(stage._ringing == (now >= 9000), "discard bell holds through grace and overdue worker " + str(now))
	stage._process(0)
	check(stage._bell.playing and stage._bell.stream.get_length() > 0.1, "reminder has playable samples")
	clock.action_accepted(1, 8, 0)
	state.clock = clock.timing_for(1, 8, 0, 18001)
	client.view_changed.emit(state)
	check(not stage._ringing and not stage._bell.playing, "actual accepted action stops ringing")
	clock.begin_prompt(1, 9, Clock.Kind.RESPONSE, [0], 5000)
	clock.animation_finished(1, 9, 0, 20000)
	for now in [21999, 22000, 24999, 25000]:
		state.clock = clock.timing_for(1, 9, 0, now)
		client.view_changed.emit(state)
		check(stage._ringing == (now >= 22000 and now < 25000), "response bell " + str(now))
	voice.set_speaker_enabled(1, false)
	client.session_ended.emit("disconnected")
	check(not voice.recording and not stage._speech.playing and not stage._music.playing and not stage._ringing, "disconnect stops all game sounds and capture")
	client.view_changed.emit(state)
	check(not stage._speech.playing and stage._last_event == 7 and not voice.recording, "rejoin skips history and keeps microphone off")
	check(not voice.speaker_enabled(1), "personal mute follows the same player across a reconnect")
	var model := RoundCore.new()
	model.start(0, 1, 2, Catalog.values(44))
	model.begin_dealer_turn()
	check(model.snapshot_for(2).audio_events.is_empty(), "private dealer draw creates no public audio event")
	var id: int = model.players[0].draw_id
	model.submit(0, model.prompt_id, "discard", id)
	var event: Dictionary = model.snapshot_for(2).audio_events[0]
	check(event == {"id": 1, "seat": 0, "clip": model.wall.value(id)}, "authoritative public event is limited to discard voice")
	_test_native(voice)
	var playback: WeakRef = weakref(stage._music.get_stream_playback())
	client.session_ended.emit("left")
	for node in [stage, voice, client]:
		node.queue_free()
	# AudioServer retires stopped playbacks on real mixer callbacks, independently
	# of the accelerated SceneTree used by the headless whole-project runner.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 250 or (playback.get_ref() != null and Time.get_ticks_msec() - start < 2000):
		OS.delay_msec(5)
		await process_frame
	check(playback.get_ref() == null, "audio mixer releases the stopped music playback")
	check(AudioServer.bus_count == buses, "exit removes private capture bus")
	DirAccess.remove_absolute(mute_path)
	print("Audio: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_native(owner: Node) -> void:
	var gme := Gme.new()
	root.add_child(gme)
	gme.owner_node = owner
	gme._use_gme = true
	gme._room_number = "2501"
	gme._context = Context.new()
	var native = gme._context.audio
	gme.set_speaker_enabled(1, false)
	gme._process(0)
	check(native.speaker and native.muted.has("25011") and not native.mic, "native entry listens and applies mute before mic consent")
	native.fail_mic = true
	check(not gme.set_enabled(true) and not gme.enabled, "native failure never displays recording")
	native.fail_mic = false
	native.ignore_enable = true
	check(not gme.set_enabled(true) and not gme.enabled, "SDK acceptance without active capture never reports a live microphone")
	native.ignore_enable = false
	check(gme.set_enabled(true) and native.mic and gme.speech_active(), "native SDK confirmed microphone and speech level")
	gme.set_suspended(true)
	check(not native.mic and not native.speaker and gme.microphone_requested(), "native background disables capture and output")
	gme.set_suspended(false)
	gme._process(0)
	check(native.mic and native.speaker, "native foreground restores consent")
	gme.permission_pending = true
	gme.set_enabled(false)
	gme.permission_result(true)
	check(not native.mic and not gme.microphone_requested(), "cancelled permission cannot revive native mic")
	gme._want_mic = true
	gme.permission_pending = true
	gme.set_suspended(true)
	gme.permission_result(false)
	gme.set_suspended(false)
	gme._process(0)
	check(not native.mic and not gme.microphone_requested(), "native permission denial in background cancels consent before re-entry")
	gme._want_mic = true
	gme._fail("语音连接失败，请点击名字重试")
	check(not gme.enabled and not gme.microphone_requested(), "reported SDK failure makes the next click a retry while listening may reconnect")
	check(Gme.valid_auth({"auth":"AQI=", "app_id":"1234", "protocol":Gme.Protocol.PROTOCOL_VERSION, "variant":"anshun_zhuoji", "voice_room":"dx-123"}), "directory auth schema accepted")
	check(not Gme.valid_auth({"auth":"AQI=", "app_id":"1234", "voice_room":"123"}), "legacy unbound auth schema rejected")
	gme.shutdown()
	check(not native.mic and not native.speaker and gme._context == null, "native exit uninitializes SDK")
	gme.queue_free()
