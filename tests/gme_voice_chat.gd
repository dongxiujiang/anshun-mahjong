extends SceneTree
const H := preload("res://tests/test_harness.gd")
const CHAT := preload("res://scripts/online/GMEVoiceChat.gd")
var t := H.new()

class VoiceOwner extends Node:
	var online_room := false
	func voice_chat_allowed(): return true

class NativeProbe extends GMEVoiceChat:
	var auth_requests := 0
	func _request_auth(_room_number): auth_requests += 1

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
	var owner := VoiceOwner.new()
	root.add_child(owner)
	var lan := NativeProbe.new()
	lan.owner_node = owner
	lan._use_gme = true
	root.add_child(lan)
	lan.connect_room("1234", 1, "LAN")
	t.expect(lan.uses_network_pcm() and lan._fallback != null, "Android LAN voice uses the authenticated game connection")
	t.expect(lan.auth_requests == 0, "LAN microphone does not request authentication for a nonexistent online room")
	lan.queue_free()
	var online := NativeProbe.new()
	online.owner_node = owner
	online._use_gme = true
	owner.online_room = true
	root.add_child(online)
	online.connect_room("1234", 1, "online", "member-token")
	t.expect(not online.uses_network_pcm() and online.auth_requests == 1, "Android online rooms retain GME authentication")
	online.queue_free()
	owner.queue_free()
	await process_frame
	quit(t.finish("gme_voice_chat"))
