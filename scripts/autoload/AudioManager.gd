extends Node
## 三条独立音频通道。全部素材随工程导入，PC/安卓运行时无需语音服务。

signal settings_changed
signal event_played(event: Dictionary)
signal discard_impact_played
signal settlement_cue_played(cue: String)

const AUDIO_ROOT := "res://res/audio/"
const SETTINGS_PATH := "user://audio_settings.cfg"
const SETTINGS_STORE := preload("res://scripts/core/UserSettingsStore.gd")
const CHANNELS := ["music", "voice", "effects"]
const BUSES := {"music": "Music", "voice": "Voice", "effects": "Effects"}
const DEFAULT_VOLUMES := {"music": 0.12, "voice": 0.8, "effects": 0.65}
const SETTINGS_VERSION := 2
const ACTION_VOICES := ["pong", "kong", "ready", "hu", "zimo"]
const VOICE_QUEUE_LIMIT := 3
const SETTLEMENT_CUES := ["flip", "chicken", "kong", "win", "other", "coins"]

var volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var enabled := {"music": true, "voice": true, "effects": true}
var preview_voice_seat := 0
var settings_path := SETTINGS_PATH
var persist_settings := DisplayServer.get_name() != "headless"
var music_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
var effects_player: AudioStreamPlayer
var settlement_player: AudioStreamPlayer
var table_active := false
var _table_owner := 0
var _streams := {}
var _voice_queue: Array[String] = []
var _voice_seat_queue: Array[int] = []
var _playing_voice_seat := 0
var _win_priority := false
var _last_session := ""
var _last_event_id := 0
var _duck_tween: Tween
var _application_paused := false

func _ready() -> void:
	for channel in CHANNELS:
		var bus := AudioServer.get_bus_index(BUSES[channel])
		if bus < 0:
			AudioServer.add_bus()
			bus = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, BUSES[channel])
			AudioServer.set_bus_send(bus, "Master")
	music_player = _player("BackgroundMusic", "Music")
	voice_player = _player("TileVoice", "Voice")
	effects_player = _player("TileEffects", "Effects")
	settlement_player = _player("SettlementEffects", "Effects")
	voice_player.finished.connect(_on_voice_finished)
	if persist_settings: _load_settings()
	_apply_settings()
	# 提前加载，首次喊牌不在出牌时读取磁盘。
	_stream("music/table")
	_stream("effects/discard")
	for cue in SETTLEMENT_CUES: _stream("effects/settlement_" + cue)
	for suit in ["wan", "tiao", "tong"]:
		for rank in range(1, 10):
			_stream("voice/%s%d" % [suit, rank])
	for action in ACTION_VOICES:
		_stream("voice/" + action)
	for seat in range(1, 4):
		for suit in ["wan", "tiao", "tong"]:
			for rank in range(1, 10):
				_stream("voice/seat%d/%s%d" % [seat, suit, rank])
		for action in ACTION_VOICES:
			_stream("voice/seat%d/%s" % [seat, action])

func _player(node_name: String, bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player

func _exit_tree() -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	for player in [music_player, voice_player, effects_player, settlement_player]:
		if player != null:
			player.stop()
			player.stream = null
	_streams.clear()

func _stream(key: String) -> AudioStream:
	if _streams.has(key):
		return _streams[key] as AudioStream
	for extension in ["ogg", "wav", "mp3"]:
		var path: String = AUDIO_ROOT + key + "." + extension
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null and key.begins_with("voice/"):
				# 用户替换素材时即便导入选项启用了循环，也保证牌名只说一次。
				stream = stream.duplicate() as AudioStream
				if stream is AudioStreamWAV:
					stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
				elif stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
					stream.loop = false
			_streams[key] = stream
			return stream
	return null

func begin_table(owner: Node = null) -> void:
	table_active = true
	_table_owner = owner.get_instance_id() if owner != null else 0
	reset_round()
	if music_player.stream == null:
		var source := _stream("music/table")
		if source != null:
			var loop := source.duplicate() as AudioStream
			if loop is AudioStreamWAV:
				loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
				loop.loop_begin = 0
				loop.loop_end = int(loop.get_length() * loop.mix_rate)
			elif loop is AudioStreamOggVorbis or loop is AudioStreamMP3:
				loop.loop = true
			music_player.stream = loop
	if music_player.stream != null and not music_player.playing:
		music_player.play()
	music_player.stream_paused = _application_paused

func end_table(owner: Node = null) -> void:
	if owner != null and owner.get_instance_id() != _table_owner:
		return
	table_active = false
	_table_owner = 0
	reset_round()
	music_player.stop()

func reset_round(session: String = "", event_id: int = 0) -> void:
	_last_session = session
	_last_event_id = event_id
	_voice_queue.clear()
	_voice_seat_queue.clear()
	_win_priority = false
	voice_player.stop()
	effects_player.stop()
	settlement_player.stop()
	_duck_music(false)

## 本地展示音效，不发送网络事件，不占用出牌语音；重连最终态不调用。
func play_settlement_cue(cue: String, owner: Node = null) -> bool:
	if cue not in SETTLEMENT_CUES or not table_active or _application_paused:
		return false
	if owner != null and owner.get_instance_id() != _table_owner:
		return false
	if not enabled.effects or float(volumes.effects) <= 0.0:
		return false
	var stream := _stream("effects/settlement_" + cue)
	if stream == null: return false
	settlement_player.stream = stream
	settlement_player.play()
	settlement_cue_played.emit(cue)
	return true

func stop_settlement_cue(owner: Node = null) -> void:
	if owner != null and owner.get_instance_id() != _table_owner: return
	if settlement_player != null: settlement_player.stop()

func play_event(event: Dictionary, defer_discard_effect: bool = false) -> void:
	if not table_active:
		return
	var action := str(event.get("action", ""))
	var tile := str(event.get("tile", ""))
	if (action != "discard" and action not in ACTION_VOICES) or (action == "discard" and not Tiles.all_values().has(tile)):
		return
	var session := str(event.get("session", ""))
	var event_id := int(event.get("id", 0))
	if session == "" or event_id <= 0:
		return
	if session != _last_session:
		reset_round(session)
	if event_id <= _last_event_id:
		return
	_last_event_id = event_id
	if _application_paused:
		return
	if action == "discard":
		if not defer_discard_effect: play_discard_impact()
		_queue_voice(tile, false, int(event.get("seat", 0)))
	else:
		_queue_voice(action, action in ["hu", "zimo"], int(event.get("seat", 0)))
	event_played.emit(event.duplicate(true))

func play_discard_impact(owner_node: Node = null) -> void:
	if not table_active or _application_paused: return
	if owner_node != null and owner_node.get_instance_id() != _table_owner: return
	if enabled.effects and float(volumes.effects) > 0.0:
		effects_player.stream = _stream("effects/discard")
		if effects_player.stream != null:
			effects_player.play()
			discard_impact_played.emit()

func _queue_voice(key: String, priority: bool, seat: int = 0) -> void:
	if not enabled.voice or float(volumes.voice) <= 0.0:
		return
	if priority:
		_voice_queue.clear()
		_voice_seat_queue.clear()
		voice_player.stop()
		_win_priority = true
	elif _win_priority:
		return
	if voice_player.playing:
		# 短语逐条播放；掉线后瞬间补多条时只保留最近几条，避免声音长时间落后。
		while _voice_queue.size() >= VOICE_QUEUE_LIMIT:
			var discard_index := -1
			for index in _voice_queue.size():
				if _voice_queue[index] not in ACTION_VOICES:
					discard_index = index
					break
			if discard_index < 0:
				# 碰、杠、报听都要喊；积压时可以舍弃牌名，保留动作语音。
				if key not in ACTION_VOICES:
					return
				break
			_voice_queue.remove_at(discard_index)
			_voice_seat_queue.remove_at(discard_index)
		_voice_queue.append(key)
		_voice_seat_queue.append(clampi(seat, 0, 3))
	else:
		_play_voice(key, seat)

func _play_voice(key: String, seat: int = 0) -> void:
	_playing_voice_seat = clampi(seat, 0, 3)
	var prefix := "voice/" if _playing_voice_seat == 0 else "voice/seat%d/" % _playing_voice_seat
	var stream := _stream(prefix + key)
	if stream == null and _playing_voice_seat != 0:
		stream = _stream("voice/" + key)
	if stream == null:
		_on_voice_finished()
		return
	voice_player.stream = stream
	_duck_music(true)
	voice_player.play()

func _on_voice_finished() -> void:
	if not _voice_queue.is_empty():
		var key: String = _voice_queue.pop_front()
		var seat: int = _voice_seat_queue.pop_front() if not _voice_seat_queue.is_empty() else 0
		_play_voice(key, seat)
	else:
		_win_priority = false
		_duck_music(false)

func _duck_music(ducked: bool) -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	if not is_inside_tree():
		return
	_duck_tween = create_tween()
	_duck_tween.tween_property(music_player, "volume_db", -11.0 if ducked else 0.0, 0.1 if ducked else 0.35)

func set_volume(channel: String, value: float, persist: bool = true) -> void:
	if channel not in CHANNELS:
		return
	volumes[channel] = clampf(value, 0.0, 1.0)
	_settings_updated(channel, persist)

func set_enabled(channel: String, on: bool, persist: bool = true) -> void:
	if channel not in CHANNELS:
		return
	enabled[channel] = on
	_settings_updated(channel, persist)

func _settings_updated(channel: String, persist: bool) -> void:
	_apply_settings()
	if channel == "voice" and (not enabled.voice or float(volumes.voice) <= 0.0):
		_voice_queue.clear()
		_voice_seat_queue.clear()
		_win_priority = false
		voice_player.stop()
		_duck_music(false)
	if channel == "effects" and (not enabled.effects or float(volumes.effects) <= 0.0):
		effects_player.stop()
		settlement_player.stop()
	if persist:
		if save_settings() != OK: push_warning("无法保存声音设置，请检查存储空间")
	settings_changed.emit()

func _apply_settings() -> void:
	for channel in CHANNELS:
		var index := AudioServer.get_bus_index(BUSES[channel])
		var volume := float(volumes[channel])
		AudioServer.set_bus_mute(index, not enabled[channel] or volume <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volume)))

func save_settings(path: String = "") -> Error:
	if path == "" and not persist_settings: return OK
	var target := settings_path if path == "" else path
	var config := SETTINGS_STORE.read_config(target)
	config.set_value("settings", "version", SETTINGS_VERSION)
	config.set_value("voice", "preview_seat", preview_voice_seat)
	for channel in CHANNELS:
		config.set_value(channel, "volume", volumes[channel])
		config.set_value(channel, "enabled", enabled[channel])
	return SETTINGS_STORE.write_config(config, target)

func _load_settings(path: String = "") -> void:
	var config := SETTINGS_STORE.read_config(settings_path if path == "" else path)
	for channel in CHANNELS:
		var volume = config.get_value(channel, "volume", DEFAULT_VOLUMES[channel])
		volumes[channel] = clampf(float(volume), 0.0, 1.0) if (volume is float or volume is int) and is_finite(float(volume)) else DEFAULT_VOLUMES[channel]
		var on = config.get_value(channel, "enabled", true)
		enabled[channel] = on if on is bool else true
	var seat = config.get_value("voice", "preview_seat", 0)
	preview_voice_seat = seat if seat is int and seat >= 0 and seat < 4 else 0
	# Loading is read-only: an older version's saved values always win over new
	# defaults, including values that happen to equal an old default.

func set_preview_voice_seat(seat: int, persist: bool = true) -> void:
	if seat < 0 or seat >= 4: return
	preview_voice_seat = seat
	if persist and save_settings() != OK: push_warning("无法保存声音设置，请检查存储空间")
	settings_changed.emit()

func preview_voice(seat: int = 0) -> void:
	if not _application_paused:
		_queue_voice("tong8", true, seat)

func _notification(what: int) -> void:
	if music_player == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_application_paused = true
		music_player.stream_paused = true
		reset_round(_last_session, _last_event_id)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_application_paused = false
		music_player.stream_paused = false
