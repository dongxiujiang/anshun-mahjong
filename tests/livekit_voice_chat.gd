extends SceneTree
## The LiveKit adapter must stay inert in headless/server mode and preserve the
## per-seat speaker API used by the table UI.

const H := preload("res://tests/test_harness.gd")
const CHAT := preload("res://scripts/online/LiveKitVoiceChat.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var chat = CHAT.new()
	root.add_child(chat)
	chat.setup(null, false)
	t.expect(not chat.audio_available and not chat.enabled, "headless voice stays disabled")
	t.expect(chat.speaker_enabled(0) and chat.speaker_enabled(1), "speakers default on")
	chat.set_speaker_enabled(2, false)
	t.expect(not chat.speaker_enabled(2), "seat speaker can be muted")
	chat.set_speaker_enabled(2, true)
	t.expect(chat.speaker_enabled(2), "seat speaker can be restored")
	t.expect(not chat.set_enabled(true), "headless microphone cannot start")
	chat.shutdown()
	chat.queue_free()
	await process_frame
	quit(t.finish("livekit_voice_chat"))
