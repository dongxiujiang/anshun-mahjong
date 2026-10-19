extends SceneTree
## Headless checks for voice packet framing, per-seat mute state and persisted
## voice settings. Real microphone capture needs a device and is manually tested.

const H := preload("res://tests/test_harness.gd")
const VOICE := preload("res://scripts/online/OnlineVoiceChat.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packet := PackedByteArray()
	packet.resize(VOICE.PACKET_BYTES)
	packet[0] = 1
	packet[1] = 2
	packet.encode_u32(2, 123)
	t.expect(VOICE.valid_packet(packet), "voice packet has the expected framing")
	t.expect(VOICE.packet_seat(packet) == 2, "voice packet carries the sender seat")
	t.expect(VOICE.packet_sequence(packet) == 123, "voice packet carries its sequence")
	t.expect(not VOICE.valid_packet(PackedByteArray()), "empty voice packet is rejected")
	var short := packet.duplicate()
	short.resize(100)
	t.expect(not VOICE.valid_packet(short), "truncated voice packet is rejected")

	var config = root.get_node("/root/GameConfig")
	var old_mic: float = config.voice_chat_mic_gain
	var old_remote: float = config.voice_chat_remote_volume
	config.set_voice_chat_mic_gain(1.5, false)
	config.set_voice_chat_remote_volume(0.35, false)
	t.expect(is_equal_approx(config.voice_chat_mic_gain, 1.5), "microphone gain is stored")
	t.expect(is_equal_approx(config.voice_chat_remote_volume, 0.35), "remote voice volume is stored")
	config.set_voice_chat_mic_gain(old_mic, false)
	config.set_voice_chat_remote_volume(old_remote, false)

	var chat := VOICE.new()
	root.add_child(chat)
	chat.setup(Node.new(), false)
	t.expect(chat.speaker_enabled(1), "remote speaker starts enabled")
	chat.set_speaker_enabled(1, false)
	t.expect(not chat.speaker_enabled(1), "remote speaker can be muted by seat")
	chat.set_speaker_enabled(1, true)
	t.expect(chat.speaker_enabled(1), "remote speaker can be restored")
	chat.shutdown()
	chat.queue_free()

	var audio_chat := VOICE.new()
	root.add_child(audio_chat)
	audio_chat.setup(Node.new(), true)
	await process_frame
	t.expect(audio_chat.speaker_enabled(2), "audio playback channels initialize")
	audio_chat.set_speaker_enabled(2, false)
	audio_chat.set_speaker_enabled(2, true)
	t.expect(audio_chat.speaker_enabled(2), "audio speaker mute can be restored")
	audio_chat.shutdown()
	audio_chat.queue_free()

	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await process_frame
	t.expect(table._voice_button != null and not table._voice_button.visible, "offline table hides the microphone button")
	t.expect(table._player_tile_areas.voice_speaker_buttons.size() == 4, "table creates four seat speaker slots")
	for seat in 4:
		t.expect(not table._player_tile_areas.voice_speaker_buttons[seat].visible, "offline/AI seat speaker stays hidden")
	t.expect(table._sound_settings.mic_gain_slider != null and table._sound_settings.remote_volume_slider != null, "table exposes microphone and remote-volume sliders")
	table.queue_free()
	await process_frame

	quit(t.finish("voice_chat"))
