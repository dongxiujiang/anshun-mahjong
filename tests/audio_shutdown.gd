extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var audio := root.get_node("AudioManager")
	var players: Array = [audio.voice_player, audio.effects_player, audio.settlement_player].filter(func(p): return p != null)
	# Exercise real streams and playback objects, including paused audio and a
	# slowed/paused scene tree. Muting alone must not bypass the audio thread.
	for pause_audio in [false, true]:
		audio.begin_table()
		audio.preview_voice(0)
		audio.preview_voice(1)
		audio.play_discard_impact()
		audio.play_settlement_cue("coins")
		var refs: Array[WeakRef] = []
		for player in players:
			t.expect(player.has_stream_playback(), "all four channels own a real playback before shutdown")
			if player.has_stream_playback(): refs.append(weakref(player.get_stream_playback()))
			player.stream_paused = pause_audio
		paused = pause_audio
		Engine.time_scale = 0.01 if pause_audio else 1.0
		t.expect(await H.drain_audio(self), "shutdown drains audio while paused=" + str(pause_audio))
		for ref in refs: t.expect(ref.get_ref() == null, "audio thread releases playback before process exit")
		for player in players:
			t.expect(not player.playing and player.stream == null, "stopped players no longer retain streams")
		t.expect(not audio.table_active and audio._voice_queue.is_empty() and audio._streams.is_empty(), "shutdown clears queued voices and cached resources")
		paused = false
		Engine.time_scale = 1.0
	quit(t.finish("audio_shutdown"))
