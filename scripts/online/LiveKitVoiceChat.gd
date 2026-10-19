class_name LiveKitVoiceChat
extends Node
## LiveKit room voice.
##
## The game server only issues short-lived LiveKit tokens; microphone audio,
## Opus, echo cancellation and playback are handled by the native LiveKit SDK.
## This replaces the bandwidth-heavy raw PCM relay used by 1.2.x.

signal status_changed(enabled: bool, message: String)
signal speaker_changed(seat: int, enabled: bool)

const FRAME_SAMPLES := 480          # 10 ms at 48 kHz
const CAPTURE_BUS := "VoiceCapture"
const OUTPUT_BUS := "Voice"
const TOKEN_URL_DEFAULT := "https://mj.dongxiu.fun/livekit-token"

var owner_node: Node
var _config: Node
var enabled := false
var audio_available := false
var permission_pending := false
var _last_permission_request := 0
var _status := ""
var _mic_gain := 1.0
var _remote_volume := 0.8
var _speaker_enabled := {0: true, 1: true, 2: true, 3: true}

var _room: LiveKitRoom
var _room_key := ""
var _identity := ""
var _connecting := false
var _connected := false
var _want_mic := false
var _token_http: HTTPRequest
var _capture: AudioEffectCapture
var _master_capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _source: LiveKitAudioSource
var _track: LiveKitLocalAudioTrack
var _apm = null
var _mic_buffer := PackedFloat32Array()
var _remote := {}
var _output_bus := "Master"

func setup(owner: Node, allow_audio: bool) -> void:
	owner_node = owner
	audio_available = allow_audio
	_config = get_node_or_null("/root/GameConfig")
	_output_bus = OUTPUT_BUS if AudioServer.get_bus_index(OUTPUT_BUS) >= 0 else "Master"
	if _config != null:
		_mic_gain = clampf(float(_config.voice_chat_mic_gain), 0.0, 2.0)
		_remote_volume = clampf(float(_config.voice_chat_remote_volume), 0.0, 1.0)
		if audio_available and not _config.voice_chat_settings_changed.is_connected(_on_settings_changed):
			_config.voice_chat_settings_changed.connect(_on_settings_changed)
	if audio_available:
		_ensure_buses()
		set_process(true)
	else:
		set_process(false)

func _ensure_buses() -> void:
	var bus := AudioServer.get_bus_index(CAPTURE_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, CAPTURE_BUS)
		AudioServer.set_bus_send(bus, "Master")
		AudioServer.set_bus_volume_db(bus, -80.0)
	_capture = null
	for index in AudioServer.get_bus_effect_count(bus):
		var effect := AudioServer.get_bus_effect(bus, index)
		if effect is AudioEffectCapture:
			_capture = effect
			break
	if _capture == null:
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 1.0
		AudioServer.add_bus_effect(bus, _capture, 0)
	AudioServer.set_bus_volume_db(bus, -80.0)
	# AEC needs the actual speaker mix as its far-end reference.
	_master_capture = null
	var master := AudioServer.get_bus_index("Master")
	for index in AudioServer.get_bus_effect_count(master):
		var effect := AudioServer.get_bus_effect(master, index)
		if effect is AudioEffectCapture:
			_master_capture = effect
			break
	if _master_capture == null:
		_master_capture = AudioEffectCapture.new()
		_master_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(master, _master_capture)

func can_toggle() -> bool:
	return audio_available and owner_node != null and owner_node.has_method("voice_chat_allowed") and owner_node.voice_chat_allowed()

func connect_room(room_number: String, seat: int, player_name: String) -> void:
	if not audio_available or seat < 0 or room_number.length() < 4:
		return
	var key := "%s/%d" % [room_number, seat]
	if key == _room_key and (_connecting or _connected):
		return
	_room_key = key
	_identity = "seat%d" % seat
	_request_token(room_number, player_name)

func _request_token(room_number: String, player_name: String) -> void:
	if _connecting or _connected:
		return
	_connecting = true
	_status = "正在连接语音…"
	status_changed.emit(enabled, _status)
	if _token_http != null:
		_token_http.queue_free()
	_token_http = HTTPRequest.new()
	_token_http.name = "LiveKitTokenRequest"
	add_child(_token_http)
	_token_http.request_completed.connect(_on_token_completed.bind(room_number))
	var base := str(ProjectSettings.get_setting("network/livekit_token_url", TOKEN_URL_DEFAULT))
	var query := "?room=%s&identity=%s&name=%s" % [
		room_number.uri_encode(), _identity.uri_encode(), player_name.uri_encode()]
	var error := _token_http.request(base + query)
	if error != OK:
		_fail("语音令牌请求失败")

func _on_token_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, _room_number: String) -> void:
	if _token_http != null:
		_token_http.queue_free()
		_token_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("语音服务连接失败（%d）" % code)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or str(parsed.get("token", "")) == "":
		_fail("语音令牌无效")
		return
	_join_room(str(parsed.get("url", "")), str(parsed.get("token", "")))

func _join_room(url: String, token: String) -> void:
	_leave_room()
	_room = LiveKitRoom.new()
	_room.connected.connect(_on_connected)
	_room.disconnected.connect(_on_disconnected)
	_room.connection_failed.connect(_on_connection_failed)
	_room.track_subscribed.connect(_on_track_subscribed)
	_room.participant_disconnected.connect(_on_participant_disconnected)
	_room.connect_to_room(url, token, {"auto_subscribe": true, "auto_reconnect": true, "connect_timeout": 15.0})

func _on_connected() -> void:
	_connecting = false
	_connected = true
	_status = "语音已连接"
	status_changed.emit(enabled, _status)
	if _want_mic or enabled:
		_start_mic()

func _on_disconnected() -> void:
	_connected = false
	_connecting = false
	_stop_mic()
	_track = null
	_source = null
	_clear_remote()
	_status = "语音已断开"
	status_changed.emit(false, _status)

func _on_connection_failed(error: String) -> void:
	_connecting = false
	_connected = false
	_fail("语音连接失败：%s" % error)

func _fail(message: String) -> void:
	_connecting = false
	_connected = false
	_status = message
	status_changed.emit(false, _status)

func _process(_delta: float) -> void:
	if not audio_available:
		return
	poll_permission()
	if _connected:
		_poll_remote()
		_pump_mic()
	elif not _connecting and can_toggle() and _room_key != "":
		# The token endpoint may have been temporarily unavailable when the
		# table opened. Retry without blocking the game.
		if int(Time.get_ticks_msec() / 1000) % 5 == 0 and _status.begins_with("语音连接失败"):
			_room_key = ""
			_status = ""

func _on_settings_changed() -> void:
	if _config == null:
		return
	_mic_gain = clampf(float(_config.voice_chat_mic_gain), 0.0, 2.0)
	set_remote_volume(float(_config.voice_chat_remote_volume))

func set_mic_gain(value: float) -> void:
	_mic_gain = clampf(value, 0.0, 2.0)

func set_remote_volume(value: float) -> void:
	_remote_volume = clampf(value, 0.0, 1.0)
	for seat in 4:
		_apply_speaker_volume(seat)

func set_speaker_enabled(seat: int, value: bool) -> void:
	if seat < 0 or seat > 3:
		return
	_speaker_enabled[seat] = value
	_apply_speaker_volume(seat)
	speaker_changed.emit(seat, value)

func speaker_enabled(seat: int) -> bool:
	return bool(_speaker_enabled.get(seat, false))

func _apply_speaker_volume(seat: int) -> void:
	var entry = _remote.get(seat, {})
	var player: AudioStreamPlayer = entry.get("player")
	if player == null:
		return
	var value := _remote_volume if speaker_enabled(seat) else 0.0
	player.volume_db = linear_to_db(maxf(value, 0.001))
	player.stream_paused = value <= 0.0

func set_enabled(want: bool) -> bool:
	if not want:
		_stop_mic()
		_want_mic = false
		return false
	if not can_toggle():
		_status = "当前模式不支持麦克风"
		status_changed.emit(false, _status)
		return false
	if enabled:
		return true
	_want_mic = true
	if OS.has_feature("android") and not _has_record_permission():
		permission_pending = true
		_last_permission_request = Time.get_ticks_msec()
		if OS.request_permission("android.permission.RECORD_AUDIO"):
			permission_pending = false
		else:
			_status = "等待麦克风权限"
			status_changed.emit(false, _status)
			return false
	if not _connected:
		_status = "正在连接语音…"
		status_changed.emit(false, _status)
		return false
	_start_mic()
	return enabled

func poll_permission() -> void:
	if not permission_pending:
		return
	if _has_record_permission():
		permission_pending = false
		if _connected:
			_start_mic()
	elif Time.get_ticks_msec() - _last_permission_request > 20000:
		permission_pending = false
		_status = "麦克风权限未授予"
		status_changed.emit(false, _status)

func _has_record_permission() -> bool:
	var granted := OS.get_granted_permissions()
	return granted.has("RECORD_AUDIO") or granted.has("android.permission.RECORD_AUDIO")

func _start_mic() -> void:
	if not _connected or _room == null or (not _want_mic and not enabled):
		return
	if _track == null:
		_source = LiveKitAudioSource.create(48000, 1, 200)
		if _source == null:
			_fail("无法创建语音采集")
			return
		_track = LiveKitLocalAudioTrack.create("microphone", _source)
		if _track == null:
			_fail("无法创建语音轨道")
			return
		_room.get_local_participant().publish_track(_track, {})
	else:
		_track.unmute()
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.name = "LiveKitMicrophone"
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = CAPTURE_BUS
		add_child(_mic_player)
		_capture.clear_buffer()
		_mic_player.play()
	_apm = _make_apm()
	enabled = true
	_want_mic = false
	_status = "麦克风已开启"
	status_changed.emit(true, _status)

func _make_apm():
	if not ClassDB.class_exists("LiveKitAudioProcessingModule"):
		return null
	var instance = ClassDB.instantiate("LiveKitAudioProcessingModule")
	if instance == null:
		return null
	var module = instance.call("create", {
		"echo_cancellation": true,
		"noise_suppression": true,
		"high_pass_filter": true,
		"auto_gain_control": true,
	})
	if module == null:
		return null
	if module.has_method("set_stream_delay_ms"):
		module.call("set_stream_delay_ms", 80)
	return module

func _stop_mic() -> void:
	enabled = false
	_want_mic = false
	if _track != null:
		_track.mute()
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	if _capture != null:
		_capture.clear_buffer()
	_mic_buffer.clear()
	if _status != "":
		_status = "麦克风已关闭"
		status_changed.emit(false, _status)

func _pump_mic() -> void:
	if not enabled or _capture == null or _source == null:
		return
	var available := _capture.get_frames_available()
	if available > 0:
		for sample in _capture.get_buffer(available):
			_mic_buffer.append((sample.x + sample.y) * 0.5)
	var reverse := _master_capture.get_frames_available() if _master_capture != null else 0
	if reverse > 0:
		var far = _master_capture.get_buffer(reverse)
		if _apm != null and far.size() >= FRAME_SAMPLES:
			var far_mono := PackedFloat32Array()
			far_mono.resize(far.size())
			for index in far.size():
				far_mono[index] = (far[index].x + far[index].y) * 0.5
			var offset := 0
			while offset + FRAME_SAMPLES <= far_mono.size():
				_apm.call("process_reverse_stream", far_mono.slice(offset, offset + FRAME_SAMPLES), 48000, 1)
				offset += FRAME_SAMPLES
	while _mic_buffer.size() >= FRAME_SAMPLES:
		var frame := _mic_buffer.slice(0, FRAME_SAMPLES)
		_mic_buffer = _mic_buffer.slice(FRAME_SAMPLES)
		for index in frame.size():
			var value := frame[index] * _mic_gain
			frame[index] = clampf(value, -1.0, 1.0)
		if _apm != null:
			var processed = _apm.call("process_stream", frame, 48000, 1)
			if processed is PackedFloat32Array and processed.size() == FRAME_SAMPLES:
				frame = processed
		if _source.get_queued_duration() < 0.18:
			_source.capture_frame(frame, 48000, 1, FRAME_SAMPLES)

func _on_track_subscribed(track: LiveKitTrack, _publication, participant: LiveKitRemoteParticipant) -> void:
	if track == null or track.get_kind() != LiveKitTrack.KIND_AUDIO:
		return
	var remote_seat := _seat_from_identity(participant.get_identity())
	if remote_seat < 0 or remote_seat == int(owner_node.my_seat):
		return
	_remove_remote(remote_seat)
	var stream := LiveKitAudioStream.from_track(track)
	if stream == null:
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 48000
	generator.buffer_length = 0.3
	var player := AudioStreamPlayer.new()
	player.name = "LiveKitRemote%d" % remote_seat
	player.stream = generator
	player.bus = _output_bus
	add_child(player)
	player.play()
	_remote[remote_seat] = {
		"stream": stream,
		"player": player,
		"playback": player.get_stream_playback(),
		"identity": participant.get_identity(),
	}
	_apply_speaker_volume(remote_seat)

func _on_participant_disconnected(participant: LiveKitRemoteParticipant) -> void:
	for seat in _remote.keys():
		if str(_remote[seat].get("identity", "")) == participant.get_identity():
			_remove_remote(int(seat))

func _remove_remote(seat: int) -> void:
	var entry = _remote.get(seat, {})
	if entry.is_empty():
		return
	if entry.get("stream") != null:
		entry.stream.close()
	if entry.get("player") != null:
		entry.player.queue_free()
	_remote.erase(seat)

func _clear_remote() -> void:
	for seat in _remote.keys():
		_remove_remote(int(seat))
	_remote.clear()

func _poll_remote() -> void:
	for seat in _remote.keys():
		if not speaker_enabled(int(seat)):
			continue
		var entry = _remote[seat]
		var stream: LiveKitAudioStream = entry.get("stream")
		var playback: AudioStreamGeneratorPlayback = entry.get("playback")
		if stream != null and playback != null:
			stream.poll(playback)

func _seat_from_identity(identity: String) -> int:
	if identity.begins_with("seat"):
		return int(identity.substr(4))
	return -1

func _leave_room() -> void:
	if _room != null:
		_room.disconnect_from_room()
	_room = null
	_track = null
	_source = null
	_connected = false
	_connecting = false

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	set_process(false)
	_stop_mic()
	_leave_room()
	_clear_remote()
	if _token_http != null:
		_token_http.queue_free()
		_token_http = null
