extends SceneTree
## 固定种子 + 真实 JSON 文件；系统窗口回调替身覆盖取消/迟到回调/Android URI。
const H := preload("res://tests/test_harness.gd")
const EXPORT := preload("res://scripts/ui/ReplayExport.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
const SMOKE := preload("res://tests/smoke_round.gd")
var t := H.new()
var directory := "user://replay-export-test-%d" % OS.get_process_id()

class SaveDialog:
	extends "res://scripts/ui/ReplayExport.gd"
	var callback: Callable
	var filename := ""
	var dialog_count := 0
	var open_error: Error = OK
	var message := ""
	func _init() -> void:
		status_changed.connect(func(_busy, text): message = text)
	func _show_save_dialog(name: String, action: Callable) -> Error:
		filename = name
		callback = action
		dialog_count += 1
		return open_error
	func choose(path: String) -> void:
		callback.call(not path.is_empty(), PackedStringArray([path]) if not path.is_empty() else PackedStringArray(), 0)

class DocumentProvider:
	extends SaveDialog
	var received_uri := ""
	var received_contents := ""
	var write_error: Error = OK
	func _write_document(path: String, contents: String) -> Error:
		received_uri = path
		received_contents = contents
		return write_error

func _initialize() -> void: call_deferred("_run")

func _round() -> RoundState:
	var game := RoundState.new()
	game.set_rng_seed(20261018)
	game.controllers = [null, null, null, null]
	game.start_round(0, 3)
	return game

func _total(game: RoundState) -> float:
	var result := 0.0
	for player in game.players: result += player.score
	return result

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	DirAccess.make_dir_recursive_absolute(directory)
	_test_record_and_freeze()
	_test_cancel_and_errors()
	_test_android_uri()
	_test_client_and_settlement()
	await _test_ui()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	quit(t.finish("replay_export"))

func _test_record_and_freeze() -> void:
	var game := _round()
	var original := REPLAY.fingerprint(game)
	var exporter := SaveDialog.new()
	root.add_child(exporter)
	exporter.export_round(game, 0)
	t.expect(exporter.busy, "选位置期间标记忙碌")
	t.expect(exporter.filename.begins_with("安顺麻将-本局记录-") and exporter.filename.ends_with(".json"), "建议文件名可辨认且为 JSON")
	t.expect(not exporter.filename.contains(":"), "文件名不含 Windows 禁止字符")
	t.expect(exporter.message.contains("下载"), "保存前告诉用户如何选可找到的目录")
	t.expect(REPLAY.fingerprint(game) == original, "打开导出不改变回合或分数")
	var frozen: Dictionary = exporter._pending.duplicate(true)
	exporter.export_round(game, 0)
	t.expect(exporter.dialog_count == 1, "连续点击只打开一个选择器")
	t.expect(game.submit_turn(0, {"discard": game.players[0].just_drew}), "选位置时原牌局可继续推进")
	var progressed := REPLAY.fingerprint(game)
	var path := directory.path_join("中文 本局记录.json")
	var previous := FileAccess.open(path, FileAccess.WRITE)
	previous.store_string("old content".repeat(50000))
	previous.close()
	exporter.choose(path)
	t.expect(not exporter.busy and exporter._pending.is_empty(), "保存后释放快照并恢复按钮状态")
	t.expect(exporter.last_path == path and exporter.message.contains(ProjectSettings.globalize_path(path)), "成功提示包含实际路径")
	var loaded := REPLAY.load_record(path)
	t.expect(JSON.stringify(loaded) == JSON.stringify(JSON.parse_string(JSON.stringify(frozen, "", true, true))), "保存的是点击时的记录，覆盖旧长文件无尾部残留")
	var replayed := REPLAY.replay(loaded)
	t.expect(replayed.ok, "真实导出的文件可被现有重放器直接打开")
	if replayed.ok: t.expect(REPLAY.fingerprint(replayed.round) == original, "保存不混入选择目录期间的后续操作")
	t.expect(REPLAY.fingerprint(game) == progressed, "写入文件不回滚或改动正在运行的牌局")
	t.expect(_total(game) == 800, "导出后四家总分仍为800")
	t.expect(game._recorder.last_path == "", "手动导出不冒充私有目录自动留档")
	exporter.free()

func _test_cancel_and_errors() -> void:
	var game := _round()
	var exporter := SaveDialog.new()
	root.add_child(exporter)
	exporter.export_round(null, 0)
	t.expect(exporter.dialog_count == 0 and exporter.message.contains("尚未开始"), "无牌局不能伪报已保存")
	exporter.export_round(game, 0)
	var old_callback := exporter.callback
	exporter.choose("")
	t.expect(not exporter.busy and exporter.last_path.is_empty() and exporter.message.contains("取消"), "取消不显示成功且能重试")
	var stale := directory.path_join("must-not-exist.json")
	old_callback.call(true, PackedStringArray([stale]), 0)
	t.expect(not FileAccess.file_exists(stale), "取消后的迟到成功回调不写文件")
	exporter.export_round(game, 0)
	old_callback.call(true, PackedStringArray([stale]), 0)
	t.expect(exporter.busy and not FileAccess.file_exists(stale), "旧回调不能完成新请求")
	exporter.choose(directory.path_join("nonexistent/failed.json"))
	t.expect(not exporter.busy and exporter.last_path.is_empty() and exporter.message.contains("失败"), "不可写路径明确失败并恢复按钮")
	exporter.open_error = ERR_UNAVAILABLE
	exporter.export_round(game, 0)
	t.expect(not exporter.busy and exporter._pending.is_empty() and exporter.message.contains("未导出"), "系统不支持选择器时不退回隐蔽目录伪报成功")
	exporter.open_error = OK
	exporter.export_round(game, 0)
	root.remove_child(exporter)
	exporter.choose(stale)
	t.expect(not FileAccess.file_exists(stale) and not exporter.busy, "退出场景后迟到回调不再导出")
	exporter.free()
	if DisplayServer.get_name() == "headless":
		var native := EXPORT.new()
		root.add_child(native)
		native.export_round(game, 0)
		t.expect(not native.busy and native.last_path.is_empty(), "headless 调用系统保存不会挂起或伪报成功")
		native.free()

func _test_android_uri() -> void:
	var exporter := DocumentProvider.new()
	root.add_child(exporter)
	var game := _round()
	var uri := "content://com.android.providers.downloads.documents/document/msf%3A106?display=renamed.json"
	exporter.export_round(game, 0)
	exporter.choose(uri)
	t.expect(exporter.received_uri == uri and exporter.last_path == uri, "Android URI 原样交给写入层，不追加扩展名、不转路径")
	t.expect(REPLAY.replay(JSON.parse_string(exporter.received_contents)).ok, "Android 与桌面保存相同的可重放内容")
	t.expect(exporter.message.contains("所选目录") and not exporter.message.contains("content://"), "Android 成功提示指向系统文件管理器，不显示无法使用的 URI")
	exporter.write_error = ERR_FILE_CANT_WRITE
	exporter.export_round(game, 0)
	exporter.choose(uri)
	t.expect(exporter.last_path.is_empty() and exporter.message.contains("失败"), "Android 提供方拒绝写入时不报成功")
	t.expect(EXPORT.FILTERS[0].contains("application/json"), "Android 保存选择器声明 JSON MIME 类型")
	exporter.free()

func _test_client_and_settlement() -> void:
	var host := _round()
	var client := RoundState.new()
	client.set_rng_seed(20261018)
	client.apply_sync(host.serialize_for_seat(2))
	var exporter := SaveDialog.new()
	root.add_child(exporter)
	exporter.export_round(client, 2)
	t.expect(exporter.filename.contains("牌面快照") and exporter.message.contains("快照"), "客户端说明保存范围，不伪装成完整过程")
	var path := directory.path_join("client.json")
	exporter.choose(path)
	var data := REPLAY.load_record(path)
	t.expect(data.get("format") == EXPORT.SNAPSHOT_FORMAT and data.get("local_seat") == 2, "快照用独立格式并标明本机座位")
	t.expect(not REPLAY.replay(data).ok, "不完整快照不会被误认为可重放记录")
	for player in data.get("state", {}).get("players", []):
		if int(player.seat) == 2:
			t.expect(player.concealed == client.players[2].concealed, "快照保留本人牌面")
		else:
			t.expect(player.concealed.all(func(tile): return tile == "hidden0"), "快照不产生对手尚未公开的手牌")
	t.expect(not data.has("wall") and not data.get("state", {}).get("wall", {}).has("ring"), "客户端导出不推测真实牌墙")
	var finished := RoundState.new()
	finished.set_rng_seed(20261018)
	finished.controllers = []
	for seat in 4: finished.controllers.append(SMOKE.SimpleAi.new("AI"))
	finished.start_round(0, 3)
	t.expect(finished.phase == RoundState.Phase.SETTLED, "固定种子完整局已结算")
	t.expect(_total(finished) == 800, "完整局结算后四家总分800")
	var before := REPLAY.fingerprint(finished)
	exporter.export_round(finished, 0)
	path = directory.path_join("settled.json")
	exporter.choose(path)
	var replayed := REPLAY.replay(REPLAY.load_record(path))
	t.expect(replayed.ok, "结算后的完整文件仍可重放")
	if replayed.ok:
		t.expect(REPLAY.fingerprint(replayed.round) == before, "重放结算与源对局一致")
		t.expect(_total(replayed.round) == 800, "重放结算四家总分800")
	t.expect(REPLAY.fingerprint(finished) == before, "导出不改动已结算对局")
	client.apply_sync(finished.serialize_for_seat(2))
	exporter.export_round(client, 2)
	path = directory.path_join("client-settled.json")
	exporter.choose(path)
	data = REPLAY.load_record(path)
	t.expect(data.get("state", {}).get("last_result", {}).get("deltas") == finished.last_result.deltas, "联机快照保留本局四家收付")
	t.expect(data.get("state", {}).get("last_result", {}).get("transfers") == JSON.parse_string(JSON.stringify(finished.last_result.transfers)), "联机快照保留结算流水")
	t.expect(_total(client) == 800, "客户端保存结算后总分800")
	exporter.free()

func _test_ui() -> void:
	var settings = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	settings.persist_changes = false
	root.add_child(settings)
	settings.replay_exporter.free()
	var exporter := SaveDialog.new()
	settings.add_child(exporter)
	settings.replay_exporter = exporter
	exporter.status_changed.connect(settings._on_export_status)
	# 直接连接生产牌桌入口，避免为文件导出测试额外启动随机对局/AI。
	var table = load("res://scripts/ui/GameTable.gd").new()
	table.round = _round()
	table._sound_settings = settings
	settings.replay_export_requested.connect(table._export_current_replay)
	settings.open()
	settings.replay_export_button.pressed.emit()
	t.expect(exporter.busy and exporter.dialog_count == 1, "实际保存按钮通过牌桌入口打开系统保存流程")
	t.expect(settings.replay_export_button.disabled and settings.continue_button.disabled and settings.exit_room_button.disabled, "选位置期间三个底部按钮禁用，避免重复提交或退出")
	settings.close(false)
	t.expect(settings.is_open(), "系统窗口待完成时不隐藏结果提示所在面板")
	exporter.choose("")
	t.expect(not settings.replay_export_button.disabled and not settings.continue_button.disabled and not settings.exit_room_button.disabled, "取消后所有按钮恢复")
	t.expect(settings.replay_status.text.contains("取消"), "取消结果真实显示在设置面板")
	settings.replay_export_button.pressed.emit()
	exporter.choose(directory.path_join("ui-saved.json"))
	t.expect(FileAccess.file_exists(exporter.last_path) and settings.replay_status.text.contains("ui-saved.json"), "按钮可真正写出文件并显示位置")
	var buttons: Array = [settings.replay_export_button, settings.continue_button, settings.exit_room_button]
	for button in buttons:
		t.expect(button.position.y == 514 and button.size.y == 80, "保存/继续/退出同一行等高")
		t.expect(button.get_rect().end.y < settings.replay_status.position.y, "底部状态不挤压按钮")
	t.expect(buttons[0].size == buttons[1].size, "保存与继续同宽且文字不会拥挤")
	t.expect(buttons[1].position.x - buttons[0].get_rect().end.x >= 16, "保存与继续保留明确间距")
	root.content_scale_size = Vector2i(2280, 1280)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	settings.replay_status.text = "已保存到你选择的位置。打开系统“文件” → 所选目录或“最近”即可找到。\n内容为牌面与结算快照，完整过程由房主或服务器保存。"
	for dimensions in [Vector2i(1280,720), Vector2i(960,540), Vector2i(640,360), Vector2i(2400,1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		settings._layout()
		t.expect(settings.replay_status.get_visible_line_count() == 2, "保存位置和快照说明两行均可见：height=%s line=%s" % [settings.replay_status.size.y, settings.replay_status.get_line_height()])
		t.expect(root.get_visible_rect().encloses(settings.panel.get_global_rect()), "保存设置面板适配屏幕 " + str(dimensions))
		for control in buttons + [settings.replay_status]:
			t.expect(Rect2(Vector2.ZERO, settings.panel.size).encloses(control.get_rect()), "按钮和两行提示不溢出 " + str(dimensions))
		if DisplayServer.get_name() != "headless" and dimensions in [Vector2i(1280,720), Vector2i(960,540)]:
			var shots := "res://build/ui_review/replay_export"
			DirAccess.make_dir_recursive_absolute(shots)
			await RenderingServer.frame_post_draw
			t.expect(root.get_texture().get_image().save_png(shots.path_join("settings-%dx%d.png" % [dimensions.x, dimensions.y])) == OK, "保存新版设置截图")
	settings.continue_button.pressed.emit()
	t.expect(not settings.is_open(), "继续游戏关闭面板")
	t.expect(_total(table.round) == 800, "保存/取消/继续不会更改四家累计分")
	table.free()
	settings.queue_free()
	await process_frame
