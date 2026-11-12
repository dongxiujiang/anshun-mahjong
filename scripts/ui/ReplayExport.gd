extends Node
## 单机和联机权威端共用；完整记录不经过其他玩家的牌局快照。
signal status_changed(busy: bool, message: String)

var busy := false
var state := {}
var base_url := ""
var _round: RoundState
var _mode := "single"
var _http: HTTPRequest
var _pending := {}

func submit_round(round_state: RoundState, mode: String = "single") -> void:
	if busy:
		status_changed.emit(true, str(state.get("message", "正在提交…")))
		return
	if round_state == null or round_state.players.size() != 4 or round_state.phase == RoundState.Phase.IDLE:
		_set_status("error", "本局尚未开始，请发牌后再提交。")
		return
	if str(state.get("session", "")) == round_state.audio_session and state.get("status") == "done":
		status_changed.emit(false, "本局已经提交，无需重复提交。")
		return
	_disconnect_round()
	_round = round_state
	_mode = mode
	state = {"session": _round.audio_session}
	if _round.phase == RoundState.Phase.SETTLED:
		_upload()
	else:
		_round.round_finished.connect(_round_finished)
		_round.state_update.connect(_check_round)
		_set_status("waiting", "已登记，本局结束后自动提交。")

func _check_round() -> void:
	if _round != null and (_round.audio_session != state.get("session", "") or _round.phase == RoundState.Phase.IDLE):
		_disconnect_round()
		_set_status("error", "本局未完成，未提交记录。")

func _round_finished(_result: Dictionary) -> void:
	_upload()

func _upload() -> void:
	_pending = _round.replay_record()
	_disconnect_round()
	if _pending.is_empty() or _pending.get("final", {}).is_empty():
		_set_status("error", "未取得完整记录，请在结算后重试。")
		return
	var url := base_url
	if url.is_empty():
		var network := get_node_or_null("/root/Network")
		url = network.directory.base_url if network != null and network.directory != null else str(ProjectSettings.get_setting("online/default_url", ""))
	if not (url.begins_with("https://") or url.begins_with("http://")):
		_set_status("error", "请先在联机页面设置服务器地址，再提交本局。")
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 20.0
		_http.body_size_limit = 16 * 1024
		add_child(_http)
		_http.request_completed.connect(_completed)
	_set_status("uploading", "正在提交完整记录…")
	var error := _http.request(url.trim_suffix("/") + "/round-records", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST,
		JSON.stringify({"mode": _mode, "record": _pending}, "", true, true))
	if error != OK: _set_status("error", "暂时连不上服务器，请稍后重新提交。")

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not is_inside_tree() or state.get("status") != "uploading": return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("error", "提交未成功，请检查网络后重试。")
	elif code in [200, 201] and data is Dictionary and data.get("ok") == true and data.get("id") == state.get("session"):
		_set_status("done", "本局完整记录已提交。")
	elif code == 404:
		_set_status("error", "服务器尚未开通记录提交，请更新服务器后重试。")
	elif code == 429:
		_set_status("error", "提交太频繁了，请稍后再试。")
	else:
		_set_status("error", "服务器未保存本局记录，请稍后重试。")

func _set_status(value: String, message: String) -> void:
	busy = value in ["waiting", "uploading"]
	state["status"] = value
	state["message"] = message
	if not busy: _pending.clear()
	status_changed.emit(busy, message)

func _disconnect_round() -> void:
	if _round != null:
		if _round.round_finished.is_connected(_round_finished): _round.round_finished.disconnect(_round_finished)
		if _round.state_update.is_connected(_check_round): _round.state_update.disconnect(_check_round)
	_round = null

func _exit_tree() -> void:
	_disconnect_round()
	if _http != null: _http.cancel_request()
	busy = false
	_pending.clear()
