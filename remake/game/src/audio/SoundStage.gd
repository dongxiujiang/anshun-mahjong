extends Node

signal dice_visual_requested

const Packs = preload("res://src/audio/VoicePacks.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const ROOT := "res://assets/audio/"
const DUCK_DB := -11.0

var _music := AudioStreamPlayer.new()
var _effects := AudioStreamPlayer.new()
var _cue_player := AudioStreamPlayer.new()
var _speech := AudioStreamPlayer.new()
var _bell := AudioStreamPlayer.new()
var _voice
var _settings := {"music_enabled": false, "music_volume": 0.12, "voice_enabled": true,
	"voice_volume": 0.8, "effects_enabled": true, "effects_volume": 0.65}
var _cache := {}
var _queue := []
var _instance := ""
var _number := -1
var _last_event := 0
var _phase := ""
var _viewer := -1
var _previous_duck := false
var _chat_duck := false
var _app_paused := false
var _game_paused := false
var _restoring := false
var _ringing := false
var _next_ring := 0
var defer_dice_until_visual_ready := false
var _pending_dice_roll := false
var _pending_dice_timeout := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for player in [_music, _effects, _cue_player, _speech, _bell]:
		add_child(player)
	_effects.max_polyphony = 3
	_cue_player.max_polyphony = 6
	_bell.stream = _make_bell()
	_speech.finished.connect(_speak_next)
	_mix(false)
	_sync_process()


func _sync_process() -> void:
	set_process((_pending_dice_roll or not _instance.is_empty()) and not _app_paused and not _game_paused)

func bind_client(client: Node, voice: Node) -> void:
	_voice = voice
	client.view_changed.connect(accept_view)
	client.session_ended.connect(_ended)
	if not client.view.is_empty():
		accept_view(client.view)

func configure(settings: Dictionary) -> void:
	for key in ["music_enabled", "voice_enabled", "effects_enabled"]:
		if settings.has(key):
			_settings[key] = bool(settings[key])
	if settings.has("music"):
		_settings.music_enabled = bool(settings.music)
	for key in ["music_volume", "voice_volume", "effects_volume"]:
		if settings.has(key):
			_settings[key] = clampf(float(settings[key]), 0.0, 1.0)
	if not _settings.voice_enabled or _settings.voice_volume == 0.0:
		_queue.clear()
		_speech.stop()
	if not _settings.effects_enabled or _settings.effects_volume == 0.0:
		_effects.stop()
		_cue_player.stop()
		_bell.stop()
	_mix(_previous_duck, _chat_duck)
	_update_music()

func accept_view(view: Dictionary) -> void:
	var room: Dictionary = view.get("room", {})
	var round_view: Dictionary = view.get("round", {})
	var instance: String = room.get("room_instance_id", "")
	if instance.is_empty():
		return
	var initial := _instance != instance or _restoring
	var number: int = room.get("round_number", 0)
	if initial or number != _number:
		_stop_short_sounds()
		_last_event = 0
	_instance = instance
	_number = number
	_viewer = view.get("seat", -1)
	_game_paused = view.get("paused", false)
	var active := not _app_paused and not _game_paused
	var phase: String = round_view.get("phase", "")
	if active and not initial and phase == "dice" and _phase != phase:
		if defer_dice_until_visual_ready:
			_pending_dice_roll = true
			_pending_dice_timeout = 0.65
			dice_visual_requested.emit()
		else:
			_effect("dice_roll")
	elif phase != "dice":
		_pending_dice_roll = false
	_phase = phase
	for event in round_view.get("audio_events", []):
		if event.id <= _last_event:
			continue
		_last_event = event.id
		if active and not initial:
			_announce(event.seat, event.clip, room.get("seats", []))
	_restoring = false
	if not active:
		_stop_short_sounds()
	var timer: Dictionary = view.get("clock", {})
	var clock_phase: String = str(timer.get("phase", ""))
	var has_choices_key: bool = round_view.has("choices")
	var has_actions: bool = not round_view.get("choices", {}).get("actions", []).is_empty()
	var our_timer: bool = (phase != "turn" or round_view.get("turn", -1) == _viewer) and (not has_choices_key or has_actions or clock_phase in ["grace", "overdue"])
	var should_ring: bool = active and our_timer and timer.get("reminder", false)
	if should_ring != _ringing:
		_ringing = should_ring
		_next_ring = 0
		if not _ringing:
			_bell.stop()
	_update_music()
	_sync_process()

func notify_dice_visual_ready() -> void:
	if _pending_dice_roll and not _app_paused and not _game_paused:
		_pending_dice_roll = false
		_effect("dice_roll")

func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		var full := ROOT + path
		var stream: AudioStream
		# 优先加载 Godot 预导入二进制音频资源（零 WAV 实时解析卡顿）；仅无导入缓存的纯脚本测试回退读原文件
		if ResourceLoader.exists(full):
			stream = ResourceLoader.load(full) as AudioStream
		if stream == null and FileAccess.file_exists(full):
			stream = AudioStreamMP3.load_from_file(full) if full.ends_with(".mp3") else AudioStreamWAV.load_from_file(full)
		_cache[path] = stream
	return _cache[path]

func _effect(clip: String) -> void:
	if _settings.effects_enabled and _settings.effects_volume > 0.0:
		_effects.stream = _stream("effects/" + clip + ".wav")
		if _effects.stream:
			_effects.play()

func play_cue(clip: String, pitch: float = 1.0) -> void:
	if _app_paused or _game_paused:
		return
	if not _settings.effects_enabled or _settings.effects_volume <= 0.0:
		return
	var stream := _stream("effects/" + clip + ".wav")
	if stream != null:
		_cue_player.stream = stream
		_cue_player.pitch_scale = clampf(pitch, 0.5, 2.5)
		_cue_player.play()

func _announce(seat: int, clip: String, seats: Array) -> void:
	if seat not in range(4):
		return
	var tile := Catalog.valid_value(clip)
	if not tile and clip not in ["ready", "pong", "kong", "hu", "zimo"]:
		return
	if tile:
		_effect("discard")
	elif clip in ["pong", "kong"]:
		play_cue("meld_slam")
	elif clip == "ready":
		play_cue("ready_chime")
	elif clip in ["hu", "zimo"]:
		play_cue("win_fanfare")
	if not _settings.voice_enabled or _settings.voice_volume <= 0.0:
		return
	var selected: Variant = seats[seat].get("voice_pack") if seat < seats.size() else null
	var pack: String = selected if selected is String and Packs.ORDER.has(selected) else Packs.DEFAULT
	if clip in ["hu", "zimo"]:
		_queue = _queue.filter(func(item): return item.clip in ["hu", "zimo"])
	_queue.append({"pack": pack, "clip": clip})
	if _queue.size() > 4:
		for i in _queue.size():
			if Catalog.valid_value(_queue[i].clip):
				_queue.remove_at(i)
				break
	if not _speech.playing:
		_speak_next()

func _speak_next() -> void:
	if not _queue.is_empty() and not _app_paused and not _game_paused:
		var item: Dictionary = _queue.pop_front()
		_speech.stream = _stream("voice_packs/%s/%s.wav" % [item.pack, item.clip])
		if _speech.stream:
			_speech.play()

func _update_music() -> void:
	if _instance.is_empty() or not _settings.music_enabled or _settings.music_volume <= 0.0:
		_music.stop()
		return
	if _music.stream == null:
		_music.stream = _stream("music/table.mp3")
		if _music.stream is AudioStreamMP3:
			_music.stream.loop = true
	if _app_paused or _game_paused:
		_music.stream_paused = true
	else:
		_music.stream_paused = false
		if _music.stream and not _music.playing:
			_music.play()

func _process(delta: float) -> void:
	if _app_paused or _game_paused or _instance.is_empty():
		return
	if _pending_dice_roll:
		_pending_dice_timeout -= delta
		if _pending_dice_timeout <= 0.0:
			notify_dice_visual_ready()
	var chat: bool = is_instance_valid(_voice) and _voice.speech_active()
	var duck: bool = _speech.playing or chat
	if duck != _previous_duck or chat != _chat_duck:
		_mix(duck, chat)
	if _ringing and Time.get_ticks_msec() >= _next_ring:
		_next_ring = Time.get_ticks_msec() + 1000
		if _settings.effects_enabled and _settings.effects_volume > 0.0:
			_bell.play()

func _mix(duck: bool, chat: bool = false) -> void:
	_previous_duck = duck
	_chat_duck = chat
	var attenuation := DUCK_DB if duck else 0.0
	_music.volume_db = linear_to_db(maxf(0.0001, _settings.music_volume)) + attenuation
	_speech.volume_db = linear_to_db(maxf(0.0001, _settings.voice_volume)) + (DUCK_DB if chat else 0.0)
	_effects.volume_db = linear_to_db(maxf(0.0001, _settings.effects_volume)) + attenuation
	_cue_player.volume_db = _effects.volume_db - 3.5
	_bell.volume_db = _effects.volume_db - 2.0

func _stop_short_sounds() -> void:
	_pending_dice_roll = false
	_queue.clear()
	_speech.stop()
	_effects.stop()
	_cue_player.stop()
	_bell.stop()
	_ringing = false

func _ended(_reason: String) -> void:
	_instance = ""
	_phase = ""
	_number = -1
	_last_event = 0
	_stop_short_sounds()
	_music.stop()
	for player in [_music, _effects, _cue_player, _speech]:
		player.stream = null
	_cache.clear()
	_sync_process()

func _exit_tree() -> void:
	_ended("")
	_bell.stream = null

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		_app_paused = what == NOTIFICATION_APPLICATION_PAUSED
		if _app_paused:
			_stop_short_sounds()
		else:
			_restoring = true
		_update_music()
		_sync_process()

static func _make_bell() -> AudioStreamWAV:
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(9702)
	for i in data.size() / 2:
		var t := float(i) / sample.mix_rate
		var envelope := minf(1.0, t * 160.0) * exp(-26.0 * t) * minf(1.0, (0.22 - t) * 100.0)
		var tone := sin(TAU * 760.0 * t) + 0.28 * sin(TAU * 1517.0 * t)
		data.encode_s16(i * 2, roundi(7000.0 * envelope * tone))
	sample.data = data
	return sample
