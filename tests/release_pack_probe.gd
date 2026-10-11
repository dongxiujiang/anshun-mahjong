extends SceneTree
## Run with an exported Windows main pack and this external script; never shipped.
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _expect(value: bool, label: String) -> void:
	if not value: failures.append(label)
	print("[release_pack] %s %s" % ["OK" if value else "FAIL", label])

func _run() -> void:
	_expect(ProjectSettings.get_setting("application/config/version") == "1.2.0", "version")
	_expect(ProjectSettings.get_setting("updates/base_id") == "1.2.0-boot1", "baseline")
	_expect(ProjectSettings.get_setting("application/config/icon") == "res://res/icons/game_icon.png", "new icon setting")
	_expect(FileAccess.file_exists("res://res/icons/game_icon.png"), "new icon packaged")
	_expect(FileAccess.get_file_as_string("res://res/update/windows_update.ps1").contains("Get-UpdateHash"), "full updater helper")
	_expect(root.get_node_or_null("PatchBoot") != null and root.get_node_or_null("UpdateManager") != null, "hot update autoloads")
	_expect(root.get_node_or_null("MCPRuntimeServer") == null, "development runtime excluded")
	root.get_node("UpdateManager").auto_check = false
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	_expect(menu.update_button != null and menu.update_panel != null, "menu update entry")
	menu.queue_free()
	await process_frame
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await process_frame
	_expect(is_instance_valid(table), "exported table instantiated")
	_expect(root.get_node("AudioManager").get_script() != null, "audio loaded")
	table.queue_free()
	await create_timer(0.3).timeout
	print("[release_pack] passed" if failures.is_empty() else "[release_pack] failed: " + ", ".join(failures))
	quit(0 if failures.is_empty() else 1)
