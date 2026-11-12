extends SceneTree
const H := preload("res://tests/test_harness.gd")
const CHAT := preload("res://scripts/online/GMEVoiceChat.gd")
var t := H.new()

class VoiceOwner extends Node:
	var online_room := false
	var allowed := true
	func voice_chat_allowed(): return allowed

class NativeProbe extends GMEVoiceChat:
	var auth_requests := 0
	func _request_auth(_room_number): auth_requests += 1
	func _has_record_permission(): return true

class AudioProbe extends RefCounted:
	var muted := {}
	var mic := false
	var mic_error := 0
	var mic_attempts := 0
	func EnableMic(value):
		if value: mic_attempts += 1
		mic = value and mic_error == 0
		return mic_error if value else 0
	func GetMicState(): return int(mic)
	func EnableSpeaker(_value): return 0
	func SetMicVolume(_value): return 0
	func SetSpeakerVolume(_value): return 0
	func SetSpeakerVolumeByOpenID(_id, _value): return 0
	func AddAudioBlackList(id): muted[id] = true
	func RemoveAudioBlackList(id): muted.erase(id)

class ContextProbe extends RefCounted:
	var entered := true
	var audio := AudioProbe.new()
	func Poll(): pass
	func IsRoomEntered(): return entered
	func GetAudioCtrl(): return audio
	func Pause(): return 0
	func Resume(): return 0
	func ExitRoom(): entered = false
	func Uninit(): pass

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
	chat.set_remote_volume(0.4)
	chat.set_mic_gain(1.3)
	t.expect(is_equal_approx(chat._fallback._remote_volume, 0.4) and is_equal_approx(chat._fallback._mic_gain, 1.3), "direct volume changes reach the LAN receiver and microphone")
	chat._fallback._rx[1] = {"next": 90}
	chat.reset_seat(1)
	t.expect(not chat._fallback._rx.has(1), "reused seats discard the previous LAN voice queue")
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
	online.audio_available = true
	online.set_process(false)
	online.set_speaker_enabled(2, false)
	var context := ContextProbe.new()
	online._context = context
	online._process(0.0)
	t.expect(context.audio.muted.has("12342"), "muting before room entry applies to the native receiver on entry")
	online.set_enabled(true)
	t.expect(online.enabled, "native microphone starts after room entry")
	online._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	t.expect(not online.enabled and not context.audio.mic and online.microphone_requested(), "backgrounding suspends capture while remembering the user's switch")
	online._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	owner.allowed = false
	online._process(0.0)
	t.expect(not online.enabled, "resuming the app does not capture while the game connection is unavailable")
	owner.allowed = true
	online._process(0.0)
	t.expect(online.enabled and context.audio.muted.has("12342"), "fresh game connection restores microphone and local mute preference")
	context.entered = false
	online._process(0.0)
	t.expect(not online.enabled, "losing native room connection clears the advertised microphone state")
	context.entered = true
	online._process(0.0)
	t.expect(online.enabled, "native room recovery restores the requested microphone")
	context.audio.mic = false
	online._process(0.0)
	t.expect(not online.enabled, "an externally stopped microphone is not advertised as on")
	online.set_enabled(false)
	online.permission_pending = true
	online.set_enabled(false)
	t.expect(not online.permission_pending, "closing the mic cancels a pending permission request")
	context.audio.mic_error = 1
	online.set_enabled(true)
	var attempts := context.audio.mic_attempts
	for frame in 10: online._process(0.0)
	t.expect(context.audio.mic_attempts == attempts, "failed microphone capture is not retried every render frame")
	context.audio.mic_error = 0
	online.set_enabled(true)
	online._fail("temporary auth failure")
	t.expect(not online.enabled and online._context == null and online._retry_at_ms > 0, "failure closes the native session and schedules a bounded retry")
	var auth_requests := online.auth_requests
	for frame in 100: online.connect_room("1234", 1, "online", "member-token")
	t.expect(online.auth_requests == auth_requests, "game state updates do not cause an auth request storm")
	online._retry_at_ms = Time.get_ticks_msec() - 1
	online._process(0.0)
	t.expect(online.auth_requests == auth_requests + 1, "temporary connection failure retries without waiting for a move")
	for attempt in 3: online._fail("still unavailable")
	t.expect(online._retry_at_ms == 0 and not online.microphone_requested(), "repeated failures stop retrying and leave a usable manual switch")
	online.set_enabled(true)
	t.expect(online.auth_requests == auth_requests + 2, "manual retry starts authentication immediately")
	online.set_enabled(false)
	context = ContextProbe.new()
	online._context = context
	online._process(0.0)
	t.expect(not online.enabled, "cancelling a pending microphone does not reopen it when room entry finishes")
	online.set_enabled(true)
	online.connect_room("1234", 3, "online", "new-token")
	t.expect(not context.entered and online._context == null and not online.enabled and online._open_id == "12343", "seat changes retire the old native identity before authenticating the new seat")
	var stale := HTTPRequest.new()
	root.add_child(stale)
	online._on_auth_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{}".to_utf8_buffer(), "1234", stale)
	t.expect(online._auth_failed_key == "", "a stale auth response cannot overwrite the new room attempt")
	stale.queue_free()
	online.queue_free()
	owner.queue_free()
	await process_frame
	quit(t.finish("gme_voice_chat"))
