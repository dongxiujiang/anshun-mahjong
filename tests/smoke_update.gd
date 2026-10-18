extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var updater: Node

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	updater = root.get_node("UpdateManager")
	var current := str(ProjectSettings.get_setting("application/config/version", ""))
	var next := _next_version(current)
	t.expect(updater.current_version() == current and current != "", "应用版本已配置")
	t.expect(updater.auto_check and ProjectSettings.get_setting("updates/auto_check", false), "游戏默认开启启动检查更新")
	t.expect(updater.is_newer("V1.0.1", "v1.0.0"), "兼容大写 V 发布标签")
	t.expect(not updater.is_newer("V1.0.0", "1.0.0"), "大写标签同版本不更新")
	for pair in [["1.0.1", "1.0.0"], ["v2.0.0", "1.9.9"], ["1.0.0", "1.0.0"], ["0.9.9", "1.0.0"], ["1.0", "1.0.0"]]:
		var expected: bool = pair[0] in ["1.0.1", "v2.0.0"]
		t.expect(updater.is_newer(pair[0], pair[1]) == expected, "版本比较 %s / %s" % pair)
	for number in ["", "1", "1.0.3.4", "1.a.0", "v1.0.0-beta", "V1.0.1-beta", "vV1.0.1", "VV1.0.1"]:
		t.expect(updater._version_parts(number).is_empty(), "拒绝无效版本号 %s" % number)
	for url in ["https://github.com/a/b/releases/download/v1/app.exe", "https://example.com/update.json"]:
		t.expect(updater.safe_url(url), "接受 HTTPS 更新地址")
	for url in ["http://example.com/update.json", "https://user:pass@example.com/update", "javascript:alert(1)", "https://example.com/a b"]:
		t.expect(not updater.safe_url(url), "拒绝不安全更新地址")
	t.expect(updater.safe_url("http://127.0.0.1:8080/update.json", true), "测试模式允许本机 HTTP")
	t.expect(updater.valid_sha256("0".repeat(64)), "接受 SHA-256")
	t.expect(not updater.valid_sha256("0".repeat(63)), "拒绝短 SHA-256")
	var manager = load("res://scripts/autoload/UpdateManager.gd").new()
	root.add_child(manager)
	manager.apply_release({"tag_name": "v" + current, "draft": false, "prerelease": false}, "windows", true)
	t.expect(manager.state == "current", "同版本不提示更新")
	manager.apply_release({"tag_name": "V" + current, "draft": false, "prerelease": false}, "windows", true)
	t.expect(manager.state == "current", "已发布大写标签与包内版本一致")
	manager.apply_release({"tag_name": "V" + next, "html_url": "https://example.com/release", "assets": [{"name": "anshun-mahjong-windows-x64.exe", "browser_download_url": "https://example.com/game.exe"}]}, "windows")
	t.expect(manager.state == "available" and manager.latest.version == next, "大写 V 更新版本规范化")
	var digest := "a".repeat(64)
	manager.apply_release({"version": next, "release_url": "http://127.0.0.1:8080/release", "notes": "修复牌桌问题", "platforms": {"windows": {"url": "http://127.0.0.1:8080/game.exe", "sha256": digest, "size": 1234}, "android": {"url": "http://127.0.0.1:8080/game.apk", "sha256": digest, "size": 2345}}}, "windows", true)
	t.expect(manager.state == "available" and manager.can_download(), "静态清单发现 Windows 更新")
	t.expect(manager.latest.notes == "修复牌桌问题" and manager.latest.size == 1234, "读取更新说明和大小")
	manager.apply_release({"version": next, "release_url": "http://127.0.0.1:8080/release", "platforms": {"android": {"url": "http://127.0.0.1:8080/game.apk", "sha256": digest, "size": 2345}}}, "android", true)
	t.expect(manager.state == "available" and not manager.can_download() and manager.latest.platform == "android", "Android 更新改为打开 APK 下载页")
	manager.apply_release({"version": next, "release_url": "http://127.0.0.1:8080/release", "platforms": {"windows": {"url": "http://127.0.0.1:8080/game.exe", "sha256": "bad", "size": 1234}}}, "windows", true)
	t.expect(manager.state == "error", "拒绝错误校验信息")
	manager.apply_release({"tag_name": "v9.0.10", "html_url": "https://github.com/dongxiujiang/anshun-mahjong/releases", "assets": [{"name": "anshun-mahjong-windows-x64.exe", "browser_download_url": "https://example.com/game.exe", "digest": null}]}, "windows")
	t.expect(manager.state == "available" and not manager.can_download(), "缺少 GitHub 摘要时使用下载页")
	manager.apply_release({"tag_name": "v9.0.10", "draft": true}, "windows")
	t.expect(manager.state == "no_release", "不安装草稿版本")
	manager.apply_release({"tag_name": "v9.0.10", "prerelease": true}, "windows")
	t.expect(manager.state == "no_release", "不安装测试版本")
	manager.queue_free()
	await _test_ui()
	quit(t.finish("smoke_update"))

func _test_ui() -> void:
	updater.auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var digest := "b".repeat(64)
	var next := _next_version(str(ProjectSettings.get_setting("application/config/version", "")))
	updater.apply_release({"tag_name": "v9.0.10", "html_url": "https://github.com/dongxiujiang/anshun-mahjong/releases/tag/v9.0.10", "body": "更新内容\n改善局域网房间搜索\n优化横屏牌桌", "assets": [{"name": "anshun-mahjong-windows-x64.exe", "browser_download_url": "https://example.com/game.exe", "digest": "sha256:" + digest, "size": 12345678}]}, "windows")
	t.expect(menu.update_button.text.contains("9.0.10"), "主菜单提示新版本")
	menu.update_panel.open()
	var panel = menu.update_panel
	t.expect(panel.notes.text.contains("局域网") and not panel.action_button.disabled, "面板显示说明并可下载")
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(2400, 1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var rect: Rect2 = panel.panel.get_global_rect()
		t.expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= root.size.x + 1 and rect.end.y <= root.size.y + 1, "更新面板适配横屏")
		var menu_rect: Rect2 = menu.content.get_global_rect()
		t.expect(menu_rect.position.y >= 0 and menu_rect.end.y <= root.size.y + 1, "主菜单增加更新入口后仍在屏幕内")
	updater.state = "downloading"
	updater.downloaded_bytes = 1000
	updater.total_bytes = 2000
	updater.state_changed.emit()
	t.expect(panel.progress.visible and panel.progress.value == 50.0 and panel.action_button.text == "取消下载", "显示下载进度和取消")
	updater.state = "ready"
	updater.state_changed.emit()
	t.expect(panel.action_button.text == "打开下载文件夹", "工程运行不替换 Godot")
	updater.apply_release({"version": "9.0.10", "notes": "优化局域网房间搜索与选座\n改善横屏牌桌布局\n新增出牌语音与背景音乐", "release_url": "https://example.com/release", "platforms": {"android": {"url": "https://example.com/game.apk"}}}, "android")
	t.expect(panel.action_button.text == "下载 APK", "安卓显示下载 APK 入口")
	var boot := root.get_node("PatchBoot")
	updater.apply_release({"schema": 2, "version": next, "notes": "优化横屏手牌布局\n调整出牌语音\n修复结算显示", "release_url": "https://example.com/release", "patches": {"android": {"base_id": boot.base_id, "base_version": boot.base_version, "engine": boot.engine_version(), "url": "https://example.com/patch.pck", "sha256": digest, "size": 3456789}}}, "android")
	t.expect(panel.action_button.text == "下载小版本补丁" and panel.detail.text.contains("不需要重新安装"), "安卓小版本面板说明无需安装")
	updater.state = "ready"
	updater.state_changed.emit()
	t.expect(panel.action_button.text == "重启应用生效", "小版本下载后显示重启生效")
	updater.state = "available"
	updater.state_changed.emit()
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/update_panel.png")
	panel.close()
	t.expect(not panel.is_open(), "关闭更新面板后继续游戏")
	updater.auto_check = true
	updater._automatic_prompted = false
	updater.state_changed.emit()
	t.expect(panel.is_open(), "启动发现新版自动显示更新面板")
	panel.close()
	updater.state_changed.emit()
	t.expect(not panel.is_open(), "关闭后状态刷新不会反复弹窗")
	updater.state = "error"
	updater._automatic_prompted = false
	updater.state_changed.emit()
	t.expect(not panel.is_open(), "启动检查失败允许继续游戏")
	updater.state = "ready"
	updater.state_changed.emit()
	t.expect(panel.is_open(), "已下载的补丁在启动时提醒重启")
	panel.close()
	updater.auto_check = false
	menu.queue_free()
	await process_frame
	updater.latest.clear()
	updater.state = "idle"

func _next_version(value: String) -> String:
	var parts := value.split(".")
	if parts.size() != 3: return value
	return "%s.%s.%d" % [parts[0], parts[1], int(parts[2]) + 1]
