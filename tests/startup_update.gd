extends SceneTree
## 使用真实窗口后端验证自动检查；地址由本地测试HTTP服务提供。
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var endpoint := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--startup-url="): endpoint = argument.substr(14)
	ProjectSettings.set_setting("updates/manifest_url", endpoint)
	ProjectSettings.set_setting("updates/auto_check", true)
	call_deferred("_run")

func _run() -> void:
	var manager := root.get_node("UpdateManager")
	manager.manifest_url = endpoint
	manager.auto_check = true
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	var deadline := Time.get_ticks_msec() + 10000
	t.expect(manager._metadata.use_threads, "Update metadata runs off the UI thread")
	t.expect(menu.update_status_label.text == manager.message, "Startup check status is visible in the menu")
	while (manager.state in ["idle", "checking"] or manager._automatic_retry_pending) and Time.get_ticks_msec() < deadline:
		await process_frame
	print("[startup_update] state=%s message=%s endpoint=%s" % [manager.state, manager.message, manager._check_url])
	t.expect(manager._automatic_checked, "Startup automatically checks without pressing a button")
	var has_update := endpoint.ends_with("/new") or endpoint.ends_with("/retry")
	t.expect(manager.state == ("available" if has_update else ("current" if endpoint.ends_with("/current") else "error")), "Startup receives actual HTTP result")
	t.expect(menu.update_panel.is_open() == has_update, "Only a new release opens the update panel")
	t.expect(menu.update_status_label.text == manager.message, "Automatic check result is visible without pressing a button")
	if has_update:
		t.expect(menu.update_panel.notes.text.contains("全员准备"), "Automatic popup shows the release notes")
		menu.update_panel.close()
	menu.queue_free()
	await process_frame
	menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await create_timer(2.3).timeout
	t.expect(not menu.update_panel.is_open(), "Returning to the menu never prompts again during the same launch")
	menu.queue_free()
	await process_frame
	quit(t.finish("startup_update"))
