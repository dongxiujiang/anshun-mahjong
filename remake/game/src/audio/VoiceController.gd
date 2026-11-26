extends Node

const Pcm = preload("res://src/audio/OnlineVoiceChat.gd")
const Gme = preload("res://src/audio/GMEVoiceChat.gd")
const MUTE_PATH := "user://dongxiu-muted-players-v1.cfg"

signal status_changed(recording: bool, message: String)
signal speaker_changed(seat: int, audible: bool)
signal speaker_preference_failed(message: String)
signal name_mic_changed()

var recording := false
var message := "麦克风已关闭"
var _client
var _backend
var _key := ""
var _mode := ""
var _directory := ""
var _mic_gain := 1.0
var _remote_gain := 1.0
var _paused := false
var _mute_by_id := {}
var _mute_path: String
var _people := []
var _seat := -1
var _identity := [] # room instance, network mode, stable member ID
var _restore_mic_for := []
var _remote_active := []
var _lit_names := [false, false, false, false]

func _init(mute_path: String = MUTE_PATH) -> void:
	_mute_path = mute_path
	var file := ConfigFile.new()
	if file.load(_mute_path) == OK and file.get_value("format", "version", 0) == 1:
		var muted: Variant = file.get_value("voice", "muted", PackedStringArray())
		if muted is PackedStringArray:
			for player_id in muted:
				if not player_id.is_empty():
					_mute_by_id[player_id] = true

func _ready() -> void:
	get_tree().on_request_permissions_result.connect(_permission_result)

func _permission_result(permission: String, granted: bool) -> void:
	if _backend != null and permission in ["RECORD_AUDIO", "android.permission.RECORD_AUDIO"]:
		_backend.permission_result(granted)

func bind_client(client: Node) -> void:
	_client = client
	process_mode = Node.PROCESS_MODE_ALWAYS
	client.view_changed.connect(_view)
	client.session_ended.connect(_ended)
	client.voice_connection_ended.connect(_ended.bind("disconnected"))
	client.voice_packet_received.connect(_packet)
	client.voice_stream_reset.connect(_reset_stream)
	if not client.view.is_empty():
		_view(client.view)

func set_directory_url(base_url: String) -> bool:
	var url := base_url.strip_edges().trim_suffix("/")
	var pattern := RegEx.new()
	pattern.compile("^https://[A-Za-z0-9.\\-]+(:[0-9]{1,5})?(/[A-Za-z0-9_./\\-]*)?$")
	var accepted := pattern.search(url) != null
	var next := url if accepted else ""
	if _directory != next:
		_directory = next
		if _mode == "online":
			if microphone_requested(): _restore_mic_for = _identity.duplicate()
			_close()
			_view(_client.view)
	return accepted

func _view(state: Dictionary) -> void:
	var room: Dictionary = state.get("room", {})
	var mode: String = room.get("mode", "")
	var seat: int = state.get("seat", -1)
	var seats: Array = room.get("seats", [])
	if mode not in ["lan", "online"] or seat not in range(seats.size()) or not seats[seat].get("connected", false):
		if not _key.is_empty():
			_ended("")
		return
	var key := "%s/%s/%s" % [room.room_instance_id, mode, seat]
	var identity := [room.room_instance_id, mode, seats[seat].get("player_id", "")]
	if key != _key or identity != _identity:
		if identity == _identity and microphone_requested(): _restore_mic_for = identity
		if _restore_mic_for != identity: _restore_mic_for = []
		_close()
		_identity = identity
		_key = key
		_mode = mode
		_seat = seat
		if mode == "online" and (not OS.has_feature("android") or _directory.is_empty()):
			_status(false, "在线语音需要安卓版" if not OS.has_feature("android") else "请先连接语音所在的房间服务")
		else:
			_backend = Pcm.new() if mode == "lan" else Gme.new()
			add_child(_backend)
			_backend.status_changed.connect(_backend_status.bind(_backend.get_instance_id()))
			_backend.speaker_changed.connect(func(s: int, v: bool): speaker_changed.emit(s, v))
			_backend.setup(self, true)
			set_gains(_mic_gain, _remote_gain)
			if mode == "online":
				_backend.directory_url = _directory
			_status(false, "麦克风已关闭")
	var previous := _people
	_people = []
	_remote_active = []
	for i in seats.size():
		_people.append(remote_player_id(seats[i]) if i != _seat else "")
		_remote_active.append(seats[i].get("connected", false) and seats[i].get("mic_active", false))
	_refresh_names()
	if _backend == null:
		return
	var suspended: bool = _paused or _client.waiting_for_foreground_view()
	_backend.set_suspended(suspended)
	for i in _people.size():
		if i >= previous.size() or _people[i] != previous[i]:
			_reset_stream(i)
			_backend.set_speaker_enabled(i, not _mute_by_id.has(_people[i]))
	if mode == "online" and not suspended and _client.ticket.get("room_instance_id") == room.room_instance_id:
		_backend.connect_room(room.room_number, seat, room.room_instance_id, _client.ticket.get("member_token", ""))
	if not suspended and _restore_mic_for == _identity:
		_restore_mic_for = []
		_backend.set_enabled(true)

static func remote_player_id(member: Dictionary) -> String:
	var player_id: Variant = member.get("player_id", "")
	return player_id if player_id is String and member.get("ai_id", -1) < 0 else ""

func _status(value: bool, text: String) -> void:
	_set_recording(value)
	message = text
	status_changed.emit(value, text)

func _backend_status(active: bool, text: String, source: int) -> void:
	if is_instance_valid(_backend) and _backend.get_instance_id() == source:
		_status(active and voice_chat_allowed(), text)

func _set_recording(value: bool) -> void:
	if recording == value: return
	recording = value
	if not _identity.is_empty() and is_instance_valid(_client):
		_client.report_mic_active(_identity[0], _seat, value)
	_refresh_names()

func name_mic_active(seat: int) -> bool:
	return seat in range(_lit_names.size()) and _lit_names[seat]

func _refresh_names() -> void:
	var lit := [false, false, false, false]
	for seat in _people.size():
		lit[seat] = recording if seat == _seat else _remote_active[seat]
	if _lit_names != lit:
		_lit_names = lit
		name_mic_changed.emit()

func set_gains(mic: float, remote: float) -> void:
	_mic_gain = clampf(mic, 0.0, 2.0)
	_remote_gain = clampf(remote, 0.0, 2.0)
	if _backend != null:
		_backend.set_mic_gain(_mic_gain)
		_backend.set_remote_volume(_remote_gain)

func available() -> bool:
	return _backend != null and _backend.can_toggle()

func voice_chat_allowed() -> bool:
	return not _key.is_empty() and not _paused and not _client.waiting_for_foreground_view()

func set_microphone(value: bool) -> bool:
	_restore_mic_for = []
	if _backend == null:
		_status(false, message if _mode == "online" else "当前房间无法使用麦克风")
		return false
	return _backend.set_enabled(value)

func microphone_requested() -> bool:
	return (not _identity.is_empty() and _restore_mic_for == _identity) or (_backend != null and _backend.microphone_requested())

func set_speaker_enabled(seat: int, value: bool, expected_player_id: String = "") -> bool:
	var player_id: String = _people[seat] if seat in range(_people.size()) else ""
	if player_id.is_empty() or (not expected_player_id.is_empty() and expected_player_id != player_id):
		speaker_preference_failed.emit("座位已变化，请重试。")
		return false
	if speaker_enabled_for(player_id) == value:
		return true
	var next := _mute_by_id.duplicate()
	if value:
		next.erase(player_id)
	else:
		next[player_id] = true
	if not _save_muted(next):
		speaker_preference_failed.emit("本机未能保存收听设置，请重试。")
		return false
	_mute_by_id = next
	_refresh_names()
	if _backend != null:
		_backend.set_speaker_enabled(seat, value)
	else:
		speaker_changed.emit(seat, value)
	return true

func _save_muted(muted: Dictionary) -> bool:
	var file := ConfigFile.new()
	file.set_value("format", "version", 1)
	file.set_value("voice", "muted", PackedStringArray(muted.keys()))
	var temporary := _mute_path + ".tmp"
	if file.save(temporary) != OK:
		return false
	if DirAccess.rename_absolute(temporary, _mute_path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true

func speaker_enabled(seat: int) -> bool:
	return seat in range(_people.size()) and speaker_enabled_for(_people[seat])

func speaker_enabled_for(player_id: String) -> bool:
	return not player_id.is_empty() and not _mute_by_id.has(player_id)

func speech_active() -> bool:
	return _backend != null and _backend.speech_active()

func send_local_voice(packet: PackedByteArray) -> void:
	if _mode == "lan" and recording and not _paused:
		_client.send_local_voice(packet)

func _packet(packet: PackedByteArray) -> void:
	if _backend != null and _mode == "lan" and not _paused and Pcm.packet_seat(packet) != _seat:
		_backend.play_packet(packet)

func _reset_stream(seat: int) -> void:
	if _mode == "lan" and _backend != null:
		_backend.reset_seat(seat)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		_paused = what == NOTIFICATION_APPLICATION_PAUSED
		if _backend != null:
			if _paused:
				_backend.set_suspended(true)
			elif _client != null:
				_view(_client.view)

func _close() -> void:
	var old = _backend
	_backend = null
	_set_recording(false)
	if is_instance_valid(old):
		old.shutdown()
		old.queue_free()
	_people.clear()
	_remote_active.clear()
	_key = ""
	_mode = ""
	_seat = -1
	_identity = []
	_refresh_names()

func _ended(reason: String) -> void:
	if reason in ["disconnected", "connection_failed"]:
		if not _identity.is_empty():
			_restore_mic_for = _identity.duplicate() if microphone_requested() else []
	else:
		_restore_mic_for = []
	_close()
	_status(false, "麦克风已关闭")

func _exit_tree() -> void:
	_close()
