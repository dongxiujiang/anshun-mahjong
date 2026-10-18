extends Node
## 用户主动导出使用系统另存为；内部 user://replays 自动留档仍由 RoundReplay 管理。
## Android SAF 返回 content:// URI，必须原样交给 FileAccess，不能拼接后缀或转成本地路径。
signal status_changed(busy: bool, message: String)

const FILTERS: Array[String] = ["*.json;麻将对局记录;application/json"]
const SNAPSHOT_FORMAT := "anshun-mahjong-table-snapshot"
var busy := false
var last_path := ""
var _pending := {}
var _snapshot_only := false
var _request_id := 0

func export_round(round_state: RoundState, local_seat: int) -> void:
	if busy: return
	if round_state == null or round_state.players.size() != 4 or round_state.phase in [RoundState.Phase.IDLE, RoundState.Phase.DEALING]:
		status_changed.emit(false, "本局尚未开始，请发牌后再保存。")
		return
	# 在打开系统窗口前冻结内容，避免用户选择目录期间牌局推进或进入下一局。
	_pending = round_state.replay_record()
	_snapshot_only = _pending.is_empty()
	if _snapshot_only:
		_pending = {
			"format": SNAPSHOT_FORMAT, "schema": 1,
			"version": str(ProjectSettings.get_setting("application/config/version", "")),
			"saved_at": Time.get_datetime_string_from_system(true), "local_seat": local_seat,
			"note": "联机客户端牌面与结算快照，不含完整操作过程；完整对局记录由房主或服务器保存。",
			"state": round_state.serialize_for_seat(local_seat),
		}
	_request_id += 1
	busy = true
	last_path = ""
	var hint := "请选择保存位置，建议选择“下载”文件夹。"
	if _snapshot_only: hint += "\n本机保存牌面与结算快照，完整过程由房主保存。"
	status_changed.emit(true, hint)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var filename := "安顺麻将-%s-%s.json" % ["牌面快照" if _snapshot_only else "本局记录", stamp]
	var error := _show_save_dialog(filename, _on_selected.bind(_request_id))
	if error != OK:
		_finish("无法打开系统保存窗口，记录未导出。请在支持文件选择器的设备上重试。")

func _show_save_dialog(filename: String, callback: Callable) -> Error:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE): return ERR_UNAVAILABLE
	# 安卓让系统提供可写目录；桌面默认打开下载目录。
	var directory := "" if OS.has_feature("android") else OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	return DisplayServer.file_dialog_show("保存本局记录（建议选择下载文件夹）", directory, filename,
		false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(FILTERS), callback, get_window().get_window_id())

func _on_selected(selected: bool, paths: PackedStringArray, _filter: int, request_id: int) -> void:
	if not busy or request_id != _request_id: return
	if not selected or paths.is_empty() or paths[0].is_empty():
		_finish("已取消保存，未导出文件。")
		return
	var path := paths[0]
	var error := _write_document(path, JSON.stringify(_pending, "\t", true, true))
	if error != OK:
		_finish("保存失败，请检查剩余空间并重新选择保存位置。")
		return
	last_path = path
	var message := "已保存到：" + ProjectSettings.globalize_path(path)
	if path.begins_with("content://"):
		message = "已保存到你选择的位置。打开系统“文件” → 所选目录或“最近”即可找到。"
	if _snapshot_only: message += "\n内容为牌面与结算快照，完整过程由房主或服务器保存。"
	_finish(message)

func _write_document(path: String, contents: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	var data := contents.to_utf8_buffer()
	var stored := file.store_buffer(data)
	file.flush()
	file.close()
	if not stored: return ERR_FILE_CANT_WRITE
	# 包括 Android 文档提供方在内，只有实际读回一致才显示保存成功。
	var verified := FileAccess.open(path, FileAccess.READ)
	if verified == null: return ERR_FILE_CANT_READ
	var matches := verified.get_length() == data.size() and verified.get_buffer(data.size()) == data
	verified.close()
	return OK if matches else ERR_FILE_CANT_WRITE

func _finish(message: String) -> void:
	busy = false
	_pending.clear()
	status_changed.emit(false, message)

func _exit_tree() -> void:
	# 退出牌桌后的迟到回调不能写入文件或访问已释放的设置控件。
	_request_id += 1
	busy = false
	_pending.clear()
