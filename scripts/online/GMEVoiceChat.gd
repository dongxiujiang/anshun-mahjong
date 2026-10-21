class_name GMEVoiceChat
extends Node
## Tencent GME real-time voice bridge.
##
## Android uses the GME JAR + arm64 native libraries through JavaClassWrapper,
## so no custom Java plugin/AAR is required. Windows currently keeps the old
## PCM fallback until the GME C++ GDExtension is built.

signal status_changed(enabled: bool, message: String)
signal speaker_changed(seat: int, enabled: bool)

const AUTH_URL_DEFAULT := "https://mj.dongxiu.fun/gme-auth"
const ROOM_TYPE := 1  # fluency voice room

var owner_node: Node
var enabled := false
var audio_available := false
var permission_pending := false
var _last_permission_request := 0
var _status := ""
var _use_gme := false
var _fallback = null
var _mic_gain := 1.0
var _remote_volume := 0.8
var _speaker_enabled := {0: true, 1: true, 2: true, 3: true}
var _open_id := ""
var _room_number := ""
var _room_key := ""
var _member_token := ""
var _context = null
var _audio = null
var _activity = null
var _delegate = null
var _java = null
var _in_room := false
var _want_mic := false
var _auth_http: HTTPRequest
var _app_id := "1400802279"
var _enter_started_ms := 0
var _enter_timeout_reported := false

func setup(owner: Node, allow_audio: bool) -> void:
	owner_node = owner
	audio_available = allow_audio
	var config := get_node_or_null("/root/GameConfig")
	if config != null:
		_mic_gain = clampf(float(config.voice_chat_mic_gain), 0.0, 2.0)
		_remote_volume = clampf(float(config.voice_chat_remote_volume), 0.0, 2.0)
		if not config.voice_chat_settings_changed.is_connected(_on_settings_changed):
			config.voice_chat_settings_changed.connect(_on_settings_changed)
	_use_gme = allow_audio and OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper")
	if _use_gme:
		_java = Engine.get_singleton("JavaClassWrapper")
		set_process(true)
		return
	# Windows/Linux/headless retain the existing PCM path until a native GME
	# Windows extension is available.
	_fallback = load("res://scripts/online/OnlineVoiceChat.gd").new()
	_fallback.name = "GMEPcmFallback"
	add_child(_fallback)
	_fallback.setup(owner, allow_audio)
	_fallback.status_changed.connect(_on_fallback_status)
	_fallback.speaker_changed.connect(func(seat: int, value: bool): speaker_changed.emit(seat, value))
	enabled = bool(_fallback.enabled)

func uses_network_pcm() -> bool:
	return not _use_gme

func play_packet(packet: PackedByteArray) -> void:
	if _fallback != null:
		_fallback.play_packet(packet)

func can_toggle() -> bool:
	if _fallback != null:
		return _fallback.can_toggle()
	return audio_available and owner_node != null and owner_node.has_method("voice_chat_allowed") and owner_node.voice_chat_allowed()

func connect_room(room_number: String, seat: int, _player_name: String, member_token: String = "") -> void:
	if not _use_gme or seat < 0 or room_number.length() < 4:
		return
	_member_token = member_token
	var key := "%s/%d" % [room_number, seat]
	if key == _room_key and (_context != null or _auth_http != null):
		return
	_room_key = key
	_room_number = room_number
	# GME's Init/openId must be an INT64-shaped string, not "seat0".
	_open_id = _make_open_id(room_number, seat)
	_request_auth(room_number)

static func _make_open_id(room_number: String, seat: int) -> String:
	return "%s%d" % [room_number, seat]

func _request_auth(room_number: String) -> void:
	if _auth_http != null:
		_auth_http.queue_free()
	_auth_http = HTTPRequest.new()
	_auth_http.name = "GMEAuthRequest"
	add_child(_auth_http)
	_auth_http.request_completed.connect(_on_auth_completed.bind(room_number))
	var base := str(ProjectSettings.get_setting("network/gme_auth_url", AUTH_URL_DEFAULT))
	var query := "?room=%s&openid=%s" % [room_number.uri_encode(), _open_id.uri_encode()]
	var headers := PackedStringArray(["X-Room-Token: " + _member_token])
	var error := _auth_http.request(base + query, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_fail("GME 鉴权请求失败")

func _on_auth_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, room_number: String) -> void:
	if _auth_http != null:
		_auth_http.queue_free()
		_auth_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("GME 鉴权失败 HTTP=%d result=%d" % [code, result])
		return
	_status = "GME 鉴权成功 HTTP=200"
	status_changed.emit(false, _status)
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or str(data.get("auth", "")) == "":
		_fail("GME 鉴权数据无效")
		return
	_app_id = str(data.get("app_id", _app_id))
	var auth := Marshalls.base64_to_raw(str(data.get("auth", "")))
	_join_room(room_number, auth)

func _join_room(room_number: String, auth: PackedByteArray) -> void:
	if not _use_gme:
		return
	var runtime = Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		_fail("GME AndroidRuntime 不可用")
		return
	_activity = runtime.getActivity()
	if _activity == null:
		_fail("GME 无法获取 Android Activity")
		return
	if _java == null:
		_fail("GME JavaClassWrapper 不可用")
		return
	var cls = _java.call("wrap", "com.gme.TMG.ITMGContext")
	if cls == null:
		_fail("GME SDK 未加载")
		return
	_context = cls.GetInstance(_activity)
	if _context == null:
		_fail("GME SDK 初始化失败")
		return
	_delegate = _java.call("create_proxy", self, ["com.gme.TMG.ITMGContext$ITMGDelegate"])
	if _delegate != null:
		_context.call("SetTMGDelegate", _delegate)
	var init_ret = int(_context.call("Init", _app_id, _open_id))
	if init_ret != 0:
		_fail("GME Init 失败 code=%d" % init_ret)
		return
	_audio = _context.call("GetAudioCtrl")
	if _audio == null:
		_fail("GME GetAudioCtrl 返回空")
		return
	_context.call("Poll")
	# GME Android 2.9.17 signature: EnterRoom(String, int, byte[]).
	var enter_ret = int(_context.call("EnterRoom", room_number, ROOM_TYPE, auth))
	if enter_ret != 0:
		_fail("GME EnterRoom 失败 code=%d" % enter_ret)
		return
	_enter_started_ms = Time.get_ticks_msec()
	_enter_timeout_reported = false
	_status = "GME Init=0 EnterRoom=0 openid=%s，等待 IsRoomEntered…" % _open_id
	status_changed.emit(false, _status)

func OnEvent(_event_type, _data) -> void:
	# JavaClassWrapper proxy callback. Room state is polled every frame.
	pass

func _process(_delta: float) -> void:
	if not _use_gme or _context == null:
		return
	_context.call("Poll")
	if not _in_room:
		var entered = _context.call("IsRoomEntered")
		if bool(entered):
			_in_room = true
			_audio = _context.call("GetAudioCtrl")
			if _audio != null:
				_audio.call("EnableSpeaker", true)
				set_remote_volume(_remote_volume)
			_status = "GME 语音已连接 IsRoomEntered=true"
			status_changed.emit(enabled, _status)
			if _want_mic:
				_start_mic()
		elif _enter_started_ms > 0 and not _enter_timeout_reported and Time.get_ticks_msec() - _enter_started_ms > 5000:
			_enter_timeout_reported = true
			_status = "GME 进房超时 IsRoomEntered=false"
			status_changed.emit(false, _status)
	elif _want_mic and not enabled:
		_start_mic()

func set_enabled(want: bool) -> bool:
	if _fallback != null:
		var result: bool = _fallback.set_enabled(want)
		enabled = bool(_fallback.enabled)
		return result
	if not want:
		_stop_mic()
		return false
	if not can_toggle():
		_status = "当前模式不支持麦克风"
		status_changed.emit(false, _status)
		return false
	if enabled:
		return true
	_want_mic = true
	if OS.has_feature("android") and not _has_record_permission():
		permission_pending = true
		_last_permission_request = Time.get_ticks_msec()
		if OS.request_permission("android.permission.RECORD_AUDIO"):
			permission_pending = false
		else:
			_status = "等待麦克风权限"
			status_changed.emit(false, _status)
			return false
	if not _in_room:
		_status = "正在连接 GME 语音…"
		status_changed.emit(false, _status)
		return false
	_start_mic()
	return enabled

func _start_mic() -> void:
	if not _in_room or _audio == null or (not _want_mic and not enabled):
		return
	var mic_ret = int(_audio.call("EnableMic", true))
	var speaker_ret = int(_audio.call("EnableSpeaker", true))
	_audio.call("SetMicVolume", roundi(_mic_gain * 100.0))
	# GME's per-openID speaker volume supports 0..200; the global speaker
	# volume is left at 100 so remote gain can boost quietly recorded voices.
	_audio.call("SetSpeakerVolume", 100)
	_apply_remote_volumes()
	if mic_ret != 0:
		_status = "GME EnableMic 失败 code=%d speaker=%d" % [mic_ret, speaker_ret]
		status_changed.emit(false, _status)
		return
	enabled = true
	_want_mic = false
	_status = "麦克风已开启 EnableMic=0 speaker=%d" % speaker_ret
	status_changed.emit(true, _status)

func _stop_mic() -> void:
	enabled = false
	_want_mic = false
	if _audio != null:
		_audio.call("EnableMic", false)
	if _status != "":
		_status = "麦克风已关闭"
		status_changed.emit(false, _status)

func poll_permission() -> void:
	if _fallback != null:
		_fallback.poll_permission()
		enabled = bool(_fallback.enabled)
		return
	if not permission_pending:
		return
	if _has_record_permission():
		permission_pending = false
		if _in_room:
			_start_mic()
		else:
			_status = "权限已授予，等待 GME 进房"
			status_changed.emit(false, _status)
	elif Time.get_ticks_msec() - _last_permission_request > 20000:
		permission_pending = false
		_status = "麦克风权限未授予"
		status_changed.emit(false, _status)

func _has_record_permission() -> bool:
	var granted := OS.get_granted_permissions()
	return granted.has("RECORD_AUDIO") or granted.has("android.permission.RECORD_AUDIO")

func _on_settings_changed() -> void:
	var config := get_node_or_null("/root/GameConfig")
	if config == null: return
	set_mic_gain(float(config.voice_chat_mic_gain))
	set_remote_volume(float(config.voice_chat_remote_volume))

func set_mic_gain(value: float) -> void:
	_mic_gain = clampf(value, 0.0, 2.0)
	if _audio != null:
		_audio.call("SetMicVolume", roundi(_mic_gain * 100.0))

func set_remote_volume(value: float) -> void:
	_remote_volume = clampf(value, 0.0, 2.0)
	if _audio != null:
		_audio.call("SetSpeakerVolume", 100)
		_apply_remote_volumes()

func _apply_remote_volumes() -> void:
	if _audio == null or _room_number == "":
		return
	for seat in 4:
		if not speaker_enabled(seat):
			continue
		_audio.call("SetSpeakerVolumeByOpenID", _make_open_id(_room_number, seat), roundi(_remote_volume * 100.0))

func set_speaker_enabled(seat: int, value: bool) -> void:
	if seat < 0 or seat > 3:
		return
	_speaker_enabled[seat] = value
	# Windows/Linux use the PCM fallback; its mute state must follow the UI even
	# when no Android GME audio object exists.
	if _fallback != null:
		_fallback.set_speaker_enabled(seat, value)
	if _audio != null:
		var open_id := _make_open_id(_room_number, seat)
		if value:
			_audio.call("RemoveAudioBlackList", open_id)
			_audio.call("SetSpeakerVolumeByOpenID", open_id, roundi(_remote_volume * 100.0))
		else:
			_audio.call("AddAudioBlackList", open_id)
	if _fallback == null:
		speaker_changed.emit(seat, value)

func speaker_enabled(seat: int) -> bool:
	return bool(_speaker_enabled.get(seat, true))

func _on_fallback_status(value: bool, message: String) -> void:
	enabled = value
	status_changed.emit(value, message)

func _fail(message: String) -> void:
	_status = message
	status_changed.emit(false, _status)

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	set_process(false)
	var config = get_node_or_null("/root/GameConfig") if is_inside_tree() else null
	if config != null and config.voice_chat_settings_changed.is_connected(_on_settings_changed):
		config.voice_chat_settings_changed.disconnect(_on_settings_changed)
	if _fallback != null:
		_fallback.shutdown()
		_fallback.queue_free()
		_fallback = null
	if _context != null:
		if _audio != null:
			_audio.call("EnableMic", false)
			_audio.call("EnableSpeaker", false)
		_context.call("ExitRoom")
		_context.call("Uninit")
	_context = null
	_audio = null
	_activity = null
	_delegate = null
	_in_room = false
	enabled = false
	if _auth_http != null:
		_auth_http.queue_free()
		_auth_http = null
