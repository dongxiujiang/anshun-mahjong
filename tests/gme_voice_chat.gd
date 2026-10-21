extends SceneTree
const H := preload("res://tests/test_harness.gd")
const CHAT := preload("res://scripts/online/GMEVoiceChat.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var chat = CHAT.new()
	root.add_child(chat)
	chat.setup(null, false)
	t.expect(chat.uses_network_pcm(), "desktop/headless uses PCM fallback")
	t.expect(chat.speaker_enabled(0), "seat 0 speaker defaults on")
	chat.set_speaker_enabled(1, false)
	t.expect(not chat.speaker_enabled(1), "seat 1 speaker can be muted")
	t.expect(not chat._fallback.speaker_enabled(1), "PCM fallback speaker is actually muted")
	chat.set_speaker_enabled(1, true)
	t.expect(chat.speaker_enabled(1), "seat 1 speaker can be restored")
	t.expect(chat._fallback.speaker_enabled(1), "PCM fallback speaker is restored")
	t.expect(not chat.set_enabled(true), "headless microphone stays off")
	chat.shutdown()
	chat.queue_free()
	await process_frame
	quit(t.finish("gme_voice_chat"))
