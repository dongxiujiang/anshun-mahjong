class_name OnlineVoiceChat
extends Node
## Room voice chat: local microphone PCM16 is relayed by the authoritative
## host/server, then played through one controllable channel per remote seat.
## Pre-recorded seat voices remain owned by AudioManager and are not mixed here.

signal status_changed(enabled: bool, message: String)
signal speaker_changed(seat: int, enabled: bool)

const SAMPLE_RATE := 24000
const FRAME_COUNT := 480          # 20 ms
const HEADER_BYTES := 6
const PACKET_BYTES := HEADER_BYTES + FRAME_COUNT * 2
const MAX_PACKET_BYTES := 1024
const CAPTURE_BUS := "VoiceCapture"
const OUTPUT_BUS := "Voice"
const SILENCE_PEAK := 0.002
const JITTER_PREBUFFER_MS := 60
const JITTER_GAP_MS := 80
const SILENCE_HOLD_PACKETS := 4

var owner_node: Node
var _config: Node
var enabled := false
var audio_available := false
var permission_pending := false
var _last_permission_request := 0
var _input_rate := 48000.0
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _mono := PackedFloat32Array()
var _resample_pos := 0.0
var _filter_state := 0.0
var _filter_alpha := 0.5
var _silence_hold := 0
var _sequence := 0
var _last_rx := {}
var _rx := {}
var _status := ""
var _mic_gain := 1.0
var _remote_volume := 0.8
var _speaker_enabled := {0: true, 1: true, 2: true, 3: true}
var _playbacks := {}
var _output_players := {}

func setup(owner: Node, allow_audio: bool) -> void:
	owner_node = owner
	audio_available = allow_audio
	_config = get_node_or_null("/root/GameConfig")
	if _config != null:
		_mic_gain = clampf(float(_config.voice_chat_mic_gain), 0.0, 2.0)
		_remote_volume = clampf(float(_config.voice_chat_remote_volume), 0.0, 2.0)
		if audio_available and not _config.voice_chat_settings_changed.is_connected(_on_settings_changed):
			_config.voice_chat_settings_changed.connect(_on_settings_changed)
	if audio_available:
		_setup_audio()
		set_process(true)
	else:
		set_process(false)

func _setup_audio() -> void:
	_input_rate = maxf(8000.0, float(AudioServer.get_mix_rate()))
	# Drop the microphone's upper band before decimating to 16 kHz. Without this
	# first-order low-pass, sibilants fold back as harsh aliasing.
	_filter_alpha = 1.0 - exp(-TAU * 10000.0 / _input_rate)
	_ensure_capture_bus()
	for seat in 4:
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = SAMPLE_RATE
		generator.buffer_length = 0.24
		var player := AudioStreamPlayer.new()
		player.name = "VoicePlayback%d" % seat
		player.stream = generator
		player.bus = OUTPUT_BUS if AudioServer.get_bus_index(OUTPUT_BUS) >= 0 else "Master"
		add_child(player)
		player.play()
		_output_players[seat] = player
		_playbacks[seat] = player.get_stream_playback() as AudioStreamGeneratorPlayback
		_apply_speaker_volume(seat)

func _ensure_capture_bus() -> void:
	var bus := AudioServer.get_bus_index(CAPTURE_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, CAPTURE_BUS)
		AudioServer.set_bus_send(bus, "Master")
		AudioServer.set_bus_volume_db(bus, -80.0)
		var effect := AudioEffectCapture.new()
		effect.buffer_length = 1.0
		AudioServer.add_bus_effect(bus, effect, 0)
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

func can_toggle() -> bool:
	return audio_available and owner_node != null and owner_node.has_method("voice_chat_allowed") and owner_node.voice_chat_allowed()

func set_enabled(want: bool) -> bool:
	if not want:
		_disable()
		return false
	if not can_toggle():
		_status = "当前模式不支持麦克风"
		status_changed.emit(false, _status)
		return false
	if enabled:
		return true
	if OS.has_feature("android") and not _has_record_permission():
		permission_pending = true
		_last_permission_request = Time.get_ticks_msec()
		var requested := OS.request_permission("android.permission.RECORD_AUDIO")
		if requested:
			# Already granted but not reported by get_granted_permissions().
			permission_pending = false
			_start_capture()
			return enabled
		_status = "等待麦克风权限"
		status_changed.emit(false, _status)
		return false
	_start_capture()
	return enabled

func poll_permission() -> void:
	if not permission_pending:
		return
	if _has_record_permission():
		permission_pending = false
		_start_capture()
	elif Time.get_ticks_msec() - _last_permission_request > 20000:
		permission_pending = false
		_status = "麦克风权限未授予"
		status_changed.emit(false, _status)

func _has_record_permission() -> bool:
	var granted := OS.get_granted_permissions()
	return granted.has("RECORD_AUDIO") or granted.has("android.permission.RECORD_AUDIO")

func _start_capture() -> void:
	if _capture == null or _mic_player != null:
		return
	_mic_player = AudioStreamPlayer.new()
	_mic_player.name = "VoiceMicrophone"
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = CAPTURE_BUS
	add_child(_mic_player)
	_capture.clear_buffer()
	_mono.clear()
	_resample_pos = 0.0
	_mic_player.play()
	enabled = true
	_status = "麦克风已开启"
	set_process(true)
	status_changed.emit(true, _status)

func _disable() -> void:
	enabled = false
	permission_pending = false
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	if _capture != null:
		_capture.clear_buffer()
	_mono.clear()
	_resample_pos = 0.0
	if _status != "":
		_status = "麦克风已关闭"
		status_changed.emit(false, _status)

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	set_process(false)
	_disable()
	if _config != null and _config.voice_chat_settings_changed.is_connected(_on_settings_changed):
		_config.voice_chat_settings_changed.disconnect(_on_settings_changed)
	for player in _output_players.values():
		player.stop()
		player.queue_free()
	_output_players.clear()
	_playbacks.clear()

func set_mic_gain(value: float) -> void:
	_mic_gain = clampf(value, 0.0, 2.0)

func set_remote_volume(value: float) -> void:
	_remote_volume = clampf(value, 0.0, 2.0)
	for seat in 4:
		_apply_speaker_volume(seat)

func set_speaker_enabled(seat: int, value: bool) -> void:
	if seat < 0 or seat > 3:
		return
	_speaker_enabled[seat] = value
	if not value:
		_rx.erase(seat)
	_apply_speaker_volume(seat)
	speaker_changed.emit(seat, value)

func reset_seat(seat: int) -> void:
	# A new client/owner on a reused seat starts its packet sequence at zero.
	if seat >= 0 and seat <= 3:
		_rx.erase(seat)

func speaker_enabled(seat: int) -> bool:
	return bool(_speaker_enabled.get(seat, true))

func _apply_speaker_volume(seat: int) -> void:
	var player: AudioStreamPlayer = _output_players.get(seat)
	if player == null:
		return
	var value := _remote_volume if speaker_enabled(seat) else 0.0
	player.volume_db = linear_to_db(maxf(value, 0.001))
	var playback: AudioStreamGeneratorPlayback = _playbacks.get(seat)
	if value <= 0.0:
		player.stream_paused = true
	elif player.stream_paused:
		# Restart the generator instead of clearing an active buffer; this gives
		# an unmuted player a clean queue without retaining audio from mute time.
		player.stop()
		player.play()
		_playbacks[seat] = player.get_stream_playback() as AudioStreamGeneratorPlayback
		player.stream_paused = false
	elif playback == null:
		_playbacks[seat] = player.get_stream_playback() as AudioStreamGeneratorPlayback

func _on_settings_changed() -> void:
	if _config == null:
		return
	_mic_gain = clampf(float(_config.voice_chat_mic_gain), 0.0, 2.0)
	set_remote_volume(float(_config.voice_chat_remote_volume))

func _process(_delta: float) -> void:
	_drain_playback()
	poll_permission()
	if not enabled or _capture == null:
		return
	var frames := _capture.get_frames_available()
	if frames > 0:
		var buffer := _capture.get_buffer(frames)
		for sample in buffer:
			var mixed := (sample.x + sample.y) * 0.5
			_filter_state += _filter_alpha * (mixed - _filter_state)
			_mono.append(_filter_state)
		if _mono.size() > int(_input_rate * 2.0):
			var drop := _mono.size() - int(_input_rate)
			_mono = _mono.slice(drop)
			_resample_pos = maxf(0.0, _resample_pos - float(drop))
	_pump_resampler()

func _pump_resampler() -> void:
	if _mono.size() < 2:
		return
	var ratio := _input_rate / float(SAMPLE_RATE)
	while _mono.size() > 1 and _resample_pos + FRAME_COUNT * ratio < float(_mono.size() - 1):
		var samples := PackedFloat32Array()
		samples.resize(FRAME_COUNT)
		for index in FRAME_COUNT:
			var position := _resample_pos + float(index) * ratio
			var base := int(position)
			var fraction := position - float(base)
			samples[index] = lerpf(_mono[base], _mono[base + 1], fraction)
		_resample_pos += FRAME_COUNT * ratio
		_emit(samples)
	if _resample_pos > 4096.0:
		var drop := int(_resample_pos) - 1
		_mono = _mono.slice(drop)
		_resample_pos -= float(drop)

func _emit(samples: PackedFloat32Array) -> void:
	var gain := clampf(_mic_gain, 0.0, 2.0)
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value * gain))
	if peak < SILENCE_PEAK:
		if _silence_hold <= 0:
			return
		_silence_hold -= 1
	else:
		_silence_hold = SILENCE_HOLD_PACKETS
	var packet := PackedByteArray()
	packet.resize(PACKET_BYTES)
	packet[0] = 1
	packet[1] = 0
	packet.encode_u32(2, _sequence & 0xffffffff)
	_sequence = (_sequence + 1) & 0xffffffff
	for index in FRAME_COUNT:
		var value := samples[index] * gain
		# Soft-knee limiting keeps loud syllables from hard clipping while
		# retaining normal speech gain.
		if absf(value) > 0.9:
			value = signf(value) * (0.9 + 0.1 * tanh((absf(value) - 0.9) / 0.1))
		packet.encode_s16(HEADER_BYTES + index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	if owner_node != null and owner_node.has_method("send_local_voice"):
		owner_node.send_local_voice(packet)

static func valid_packet(packet: PackedByteArray) -> bool:
	if packet.size() != PACKET_BYTES:
		return false
	return packet[0] == 1 and packet[1] >= 0 and packet[1] <= 3

static func packet_seat(packet: PackedByteArray) -> int:
	return int(packet[1]) if packet.size() > 1 else -1

static func packet_sequence(packet: PackedByteArray) -> int:
	return int(packet.decode_u32(2)) if packet.size() >= HEADER_BYTES else -1

func play_packet(packet: PackedByteArray) -> void:
	if not valid_packet(packet):
		return
	var seat := packet_seat(packet)
	var playback: AudioStreamGeneratorPlayback = _playbacks.get(seat)
	if playback == null or not speaker_enabled(seat):
		return
	var sequence := packet_sequence(packet)
	var now := Time.get_ticks_msec()
	var state: Dictionary = _rx.get(seat, {})
	if state.is_empty():
		# Prebuffer three 20 ms packets before starting this seat. This absorbs
		# ordinary Wi-Fi/4G jitter instead of letting the generator underrun.
		state = {"next": sequence, "started": now, "last": now, "packets": {}}
		_rx[seat] = state
	elif sequence + 1000 < int(state.next):
		# A restarted client reuses the seat but starts its sequence at zero.
		state = {"next": sequence, "started": now, "last": now, "packets": {}}
		_rx[seat] = state
	if sequence < int(state.next):
		return
	if state.packets.size() >= 200:
		return
	state.packets[sequence] = packet
	state.last = now
	_last_rx[seat] = maxi(sequence, int(_last_rx.get(seat, -1)))

func _drain_playback() -> void:
	if _playbacks.is_empty() or _rx.is_empty():
		return
	var now := Time.get_ticks_msec()
	for seat in _rx.keys():
		var state: Dictionary = _rx[seat]
		if now - int(state.started) < JITTER_PREBUFFER_MS:
			continue
		var playback: AudioStreamGeneratorPlayback = _playbacks.get(seat)
		if playback == null or not speaker_enabled(seat):
			continue
		var packets: Dictionary = state.packets
		var next := int(state.next)
		while playback.get_frames_available() >= FRAME_COUNT:
			if not packets.has(next):
				if packets.is_empty():
					break
				# A lost packet should not stall the whole voice stream forever.
				# Skip the gap once the receive tail has been quiet for a moment.
				if now - int(state.last) < JITTER_GAP_MS:
					break
				var keys := packets.keys()
				keys.sort()
				next = int(keys[0])
				state.next = next
			var packet: PackedByteArray = packets[next]
			packets.erase(next)
			_push_playback(playback, packet)
			next += 1
			state.next = next
		_rx[seat] = state

func _push_playback(playback: AudioStreamGeneratorPlayback, packet: PackedByteArray) -> void:
	var output := PackedVector2Array()
	output.resize(FRAME_COUNT)
	for index in FRAME_COUNT:
		var value := float(packet.decode_s16(HEADER_BYTES + index * 2)) / 32768.0
		output[index] = Vector2(value, value)
	playback.push_buffer(output)
