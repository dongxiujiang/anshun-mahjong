extends Node
## Tencent GME real-time voice bridge.
##
## Android uses the GME JAR + arm64 native libraries through JavaClassWrapper.
## VoiceDelegate supplies the concrete callback class required by the SDK.

signal status_changed(enabled: bool, message: String)
signal speaker_changed(seat: int, enabled: bool)

const Protocol = preload("res://src/domain/Protocol.gd")
var directory_url := ""
var _instance := ""
const FLUENCY_ROOM := 1
const RETRY_DELAYS_MS := [1000, 3000, 8000]
const ENTER_TIMEOUT_MS := 10000

var owner_node: Node
var enabled := false
var audio_available := false
var permission_pending := false
var _last_permission_request := 0
var _status := ""
var _use_gme := false
var _mic_gain := 1.0
var _remote_volume := 0.8
var _speaker_enabled := {0: true, 1: true, 2: true, 3: true}
var _open_id := ""
var _room_number := ""
var _room_key := ""
var _auth_failed_key := ""
var _member_token := ""
var _context = null
var _audio = null
var _activity = null
var _delegate = null
var _java = null
var _in_room := false
var _want_mic := false
var _auth_http: HTTPRequest
var _app_id := ""
var _enter_started_ms := 0
var _retry_at_ms := 0
var _retry_count := 0
var _suspended := false

func setup(owner: Node, allow_audio: bool) -> void:
	owner_node = owner
	audio_available = allow_audio
	_use_gme = allow_audio and OS.has_feature("android") and Engine.has_singleton("JavaClassWrapper")
	if _use_gme:
		_java = Engine.get_singleton("JavaClassWrapper")
		set_process(true)
		return
	set_process(false)

func can_toggle() -> bool:
	return _use_gme and owner_node != null and owner_node.voice_chat_allowed()

func connect_room(room_number: String, seat: int, instance_id: String, member_token: String) -> void:
	_instance = instance_id
	if not _use_gme or seat not in range(4) or room_number.length() < 4 or member_token.is_empty() or _instance.is_empty() or directory_url.is_empty():
		return
	var token_changed := _member_token != member_token
	_member_token = member_token
	var key := "%s/%s/%d" % [instance_id, room_number, seat]
	if token_changed and _room_key == key:
		_release_native()
		_auth_failed_key = ""
		_retry_count = 0
		_retry_at_ms = 0
	if key == _room_key and (_context != null or _auth_http != null or _auth_failed_key == key):
		return
	if key != _room_key:
		_release_native()
		_auth_failed_key = ""
		_retry_count = 0
		_retry_at_ms = 0
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
	_auth_http.timeout = 8.0
	_auth_http.max_redirects = 0
	_auth_http.body_size_limit = 8192
	add_child(_auth_http)
	_auth_http.request_completed.connect(_on_auth_completed.bind(_auth_http))
	var base := directory_url + "/v1/gme-auth"
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	var query := "?room=%s&instance=%s&openid=%s&nonce=%s" % [room_number.uri_encode(), _instance.uri_encode(), _open_id.uri_encode(), nonce]
	var headers := PackedStringArray(["X-Room-Token: " + _member_token])
	_status = "语音连接中…"
	status_changed.emit(false, _status)
	var error := _auth_http.request(base + query, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_auth_http.queue_free()
		_auth_http = null
		_auth_failed_key = _room_key
		_fail("GME 鉴权请求失败")

func _on_auth_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	if request != _auth_http: return
	if _auth_http != null:
		_auth_http.queue_free()
		_auth_http = null
	if _suspended: return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# The failed key prevents state-frame retry storms; timed retries are
		# bounded, and a manual click can start a fresh attempt immediately.
		_auth_failed_key = _room_key
		var errors := {403: "房间语音身份验证失败，请重新加入", 429: "语音连接过于频繁，请稍后重试", 503: "当前房间服务尚未开启在线语音"}
		_fail(errors.get(code, "语音连接失败，请检查网络"))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not valid_auth(data) or data.voice_room != "dx-" + _instance:
		_fail("GME 鉴权数据无效")
		return
	_app_id = str(data.get("app_id", _app_id))
	var auth := Marshalls.base64_to_raw(str(data.get("auth", "")))
	_join_room(str(data.voice_room), auth)

static func valid_auth(data: Dictionary) -> bool:
	if data.get("variant") != Protocol.VARIANT_ID or data.get("protocol") != Protocol.PROTOCOL_VERSION:
		return false
	var app_id := str(data.get("app_id", ""))
	var auth := str(data.get("auth", ""))
	return app_id.is_valid_int() and app_id.to_int() > 0 and str(data.get("voice_room", "")).begins_with("dx-") and not auth.is_empty() and not Marshalls.base64_to_raw(auth).is_empty()

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
	var delegate_class = _java.call("wrap", "com.anshun.mahjong.VoiceDelegate")
	if delegate_class == null:
		_fail("GME 回调组件未加载")
		return
	_delegate = delegate_class.VoiceDelegate()
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
	# GME Android signature: EnterRoom(String, int, byte[]).
	var enter_ret := int(_context.call("EnterRoom", room_number, FLUENCY_ROOM, auth))
	if enter_ret != 0:
		_fail("GME EnterRoom 失败 code=%d" % enter_ret)
		return
	_enter_started_ms = Time.get_ticks_msec()
	_status = "正在进入房间语音…"
	status_changed.emit(false, _status)

func _process(_delta: float) -> void:
	poll_permission()
	if not _use_gme or _suspended:
		return
	if _context == null:
		if _retry_at_ms > 0 and Time.get_ticks_msec() >= _retry_at_ms and _auth_http == null:
			_retry_at_ms = 0
			_request_auth(_room_number)
		return
	_context.call("Poll")
	if not bool(_context.call("IsRoomEntered")):
		if _in_room:
			if _audio != null:
				_audio.call("EnableMic", false)
				_audio.call("EnableSpeaker", false)
			_in_room = false
			enabled = false
			_enter_started_ms = Time.get_ticks_msec()
			_status = "语音连接中…"
			status_changed.emit(false, _status)
		elif _enter_started_ms > 0 and Time.get_ticks_msec() - _enter_started_ms > ENTER_TIMEOUT_MS:
			_fail("语音连接超时，请点击名字重试")
		return
	if not _in_room:
		_in_room = true
		_audio = _context.call("GetAudioCtrl")
		if _audio == null:
			_fail("语音播放未就绪，请点击名字重试")
			return
		set_remote_volume(_remote_volume)
		if int(_audio.call("EnableSpeaker", true)) != 0:
			_fail("语音播放开启失败，请点击名字重试")
			return
		_retry_count = 0
		_retry_at_ms = 0
		_auth_failed_key = ""
		_status = "语音已连接"
		status_changed.emit(false, _status)
		if _want_mic: _start_mic()
	elif enabled and int(_audio.call("GetMicState")) != 1:
		_stop_mic()
		_status = "麦克风已停止，请点击名字重新开启"
		status_changed.emit(false, _status)

func set_suspended(value: bool) -> void:
	if _suspended == value: return
	_suspended = value
	if value:
		if _audio != null:
			_audio.call("EnableMic", false)
			_audio.call("EnableSpeaker", false)
		if _context != null: _context.call("Pause")
		enabled = false
		_in_room = false
		_status = "语音已暂停，返回牌局后恢复"
		status_changed.emit(false, _status)
	else:
		if _context != null:
			_context.call("Resume")
			_enter_started_ms = Time.get_ticks_msec()
		elif _auth_http == null and _room_number != "":
			_retry_count = 0
			_retry_at_ms = Time.get_ticks_msec()

func microphone_requested() -> bool:
	return _want_mic or enabled or permission_pending

func set_enabled(want: bool) -> bool:
	if not want:
		_stop_mic()
		return false
	# A manual retry starts immediately instead of waiting for a game event.
	_auth_failed_key = ""
	_retry_count = 0
	_retry_at_ms = 0
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
		if _context == null and _auth_http == null and _room_number != "":
			_request_auth(_room_number)
		_status = "语音连接中…"
		status_changed.emit(false, _status)
		return false
	_start_mic()
	return enabled

func _start_mic() -> void:
	if _suspended or not can_toggle() or not _want_mic: return
	if OS.has_feature("android") and not _has_record_permission():
		permission_pending = true
		_last_permission_request = Time.get_ticks_msec()
		return
	if not _in_room or _audio == null:
		return
	var mic_ret = int(_audio.call("EnableMic", true))
	var speaker_ret = int(_audio.call("EnableSpeaker", true))
	if speaker_ret != 0:
		_fail("语音播放开启失败，请点击名字重试")
		return
	_audio.call("SetMicVolume", roundi(_mic_gain * 100.0))
	# GME's per-openID speaker volume supports 0..200; the global speaker
	# volume is left at 100 so remote gain can boost quietly recorded voices.
	_audio.call("SetSpeakerVolume", 100)
	_apply_remote_volumes()
	if mic_ret != 0:
		_want_mic = false
		enabled = false
		_status = "GME EnableMic 失败 code=%d speaker=%d" % [mic_ret, speaker_ret]
		status_changed.emit(false, _status)
		return
	if int(_audio.call("GetMicState")) != 1:
		_stop_mic()
		_status = "麦克风未开启，请点击名字重试"
		status_changed.emit(false, _status)
		return
	enabled = true
	_status = "麦克风已开启"
	status_changed.emit(true, _status)

func _stop_mic() -> void:
	enabled = false
	_want_mic = false
	permission_pending = false
	if _audio != null:
		_audio.call("EnableMic", false)
	if _status != "":
		_status = "麦克风已关闭"
		status_changed.emit(false, _status)

func poll_permission() -> void:
	if _suspended or not permission_pending:
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
		_want_mic = false
		_status = "麦克风权限未授予"
		status_changed.emit(false, _status)

func _has_record_permission() -> bool:
	if not OS.has_feature("android"): return true
	var granted := OS.get_granted_permissions()
	return granted.has("RECORD_AUDIO") or granted.has("android.permission.RECORD_AUDIO")

func permission_result(granted: bool) -> void:
	if not permission_pending:
		return
	if granted:
		if _suspended:
			permission_pending = false
		else:
			poll_permission()
	else:
		permission_pending = false
		_want_mic = false
		_status = "麦克风权限未授予"
		status_changed.emit(false, _status)

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
		var open_id := _make_open_id(_room_number, seat)
		if speaker_enabled(seat):
			_audio.call("RemoveAudioBlackList", open_id)
			_audio.call("SetSpeakerVolumeByOpenID", open_id, roundi(_remote_volume * 100.0))
		else:
			_audio.call("AddAudioBlackList", open_id)

func set_speaker_enabled(seat: int, value: bool) -> void:
	if seat < 0 or seat > 3:
		return
	_speaker_enabled[seat] = value
	if _audio != null:
		var open_id := _make_open_id(_room_number, seat)
		if value:
			_audio.call("RemoveAudioBlackList", open_id)
			_audio.call("SetSpeakerVolumeByOpenID", open_id, roundi(_remote_volume * 100.0))
		else:
			_audio.call("AddAudioBlackList", open_id)
	speaker_changed.emit(seat, value)

func speaker_enabled(seat: int) -> bool:
	return bool(_speaker_enabled.get(seat, true))

func speech_active() -> bool:
	return not _suspended and _in_room and _audio != null and ((enabled and int(_audio.call("GetMicLevel")) > 1) or (_remote_volume > 0 and int(_audio.call("GetSpeakerLevel")) > 1))

func _fail(message: String) -> void:
	_release_native()
	_want_mic = false
	permission_pending = false
	_auth_failed_key = _room_key
	_retry_at_ms = 0
	if _retry_count < RETRY_DELAYS_MS.size():
		_retry_at_ms = Time.get_ticks_msec() + RETRY_DELAYS_MS[_retry_count]
		_retry_count += 1
	_status = message
	status_changed.emit(false, _status)

func _exit_tree() -> void:
	shutdown()

func shutdown() -> void:
	set_process(false)
	_release_native()
	_want_mic = false
	permission_pending = false
	_retry_at_ms = 0
	_room_key = ""
	_room_number = ""
	_member_token = ""
	_instance = ""

func _release_native() -> void:
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
	_enter_started_ms = 0
	if _auth_http != null:
		_auth_http.queue_free()
		_auth_http = null
