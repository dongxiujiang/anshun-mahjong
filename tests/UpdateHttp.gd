extends Node
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var manager: Node
var base_url := ""

func _ready() -> void: _run()

func _arg(name_value: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(name_value + "="): return value.substr(name_value.length() + 1)
	return ""

func _wait_until(predicate: Callable, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())

func _check(endpoint: String, expected: String) -> void:
	manager.manifest_url = base_url + endpoint
	manager.check_updates()
	t.expect(await _wait_until(func(): return manager.state != "checking"), "HTTP check completes: " + endpoint)
	t.expect(manager.state == expected, "HTTP result " + endpoint + " = " + expected)

func _run() -> void:
	manager = get_node("/root/UpdateManager")
	base_url = _arg("--update-base")
	manager.auto_check = false
	manager.download_directory = "res://build/update_fixture/downloads"
	await _check("/missing", "no_release")
	await _check("/broken", "error")
	await _check("/limited", "error")
	await _check("/current", "current")
	await _check("/manifest", "available")
	t.expect(manager.latest.version == "9.0.10" and manager.can_download(), "Manifest selects package")
	manager.download_update()
	t.expect(await _wait_until(func(): return manager.state != "downloading"), "Package finishes")
	t.expect(manager.state == "ready" and FileAccess.file_exists(manager.downloaded_path), "Package validated and saved")
	t.expect(FileAccess.get_sha256(manager.downloaded_path) == manager.latest.sha256, "Real downloaded hash")
	t.expect(not manager.can_install(), "Editor project cannot overwrite Godot executable")
	var original_path: String = OS.get_executable_path()
	t.expect(not manager.install_and_restart() and OS.get_executable_path() == original_path, "Install guard keeps editor executable")
	var saved_path: String = manager.downloaded_path
	await _check("/bad-hash", "available")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "error" and manager.message.contains("校验"), "Bad hash cannot install")
	t.expect(not FileAccess.file_exists(manager._partial_path), "Bad package removed")
	await _check("/download-error", "available")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "error", "Download HTTP error retains app")
	await _check("/bad-size", "available")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "error" and manager.message.contains("不完整"), "Incorrect expected size rejected")
	await _check("/bad-exe", "available")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "error" and manager.message.contains("Windows"), "Wrong platform executable rejected")
	await _check("/slow-manifest", "available")
	manager.download_update()
	await get_tree().create_timer(0.25).timeout
	t.expect(manager.state == "downloading", "Slow download still active")
	manager.cancel_download()
	t.expect(manager.state == "available" and not FileAccess.file_exists(manager._partial_path), "Cancel clears partial download")
	await _check("/github-patch", "available")
	t.expect(manager.latest.kind == "patch" and manager.latest.version == "1.2.2", "GitHub release fetches and verifies separate patch manifest")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "ready" and manager.downloaded_path.ends_with(".pck"), "Windows small version downloads a real PCK")
	t.expect(FileAccess.get_sha256(manager.downloaded_path) == manager.latest.sha256, "PCK download hash verified")
	var patch_info: Dictionary = manager.latest.duplicate(true)
	patch_info.platform = "android"
	manager.latest = patch_info
	manager.state = "available"
	t.expect(manager.can_download(), "Android small version uses in-game download")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "ready" and manager.downloaded_path.ends_with(".pck"), "Android small version saves PCK without an APK installer")
	await _check("/github-wrong-digest", "error")
	t.expect(manager.message.contains("清单校验"), "Tampered GitHub manifest rejected")
	await _check("/patch-bad-hash", "available")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "error" and manager.message.contains("校验"), "Corrupt patch download rejected")
	await _check("/patch-wrong-format", "available")
	manager.download_update()
	await _wait_until(func(): return manager.state != "downloading")
	t.expect(manager.state == "error" and manager.message.contains("补丁"), "Invalid PCK format rejected")
	# Helper generated by Godot, tested separately on isolated dummy executables.
	manager.latest = {"version": "9.0.10", "sha256": FileAccess.get_sha256(saved_path)}
	var helper: String = manager.prepare_windows_helper(_arg("--target"), saved_path, int(_arg("--wait-pid")))
	t.expect(helper != "" and FileAccess.file_exists(helper), "Replacement helper generated")
	var text := FileAccess.get_file_as_string(helper)
	t.expect(not text.contains("@@"), "No unresolved helper tokens")
	t.expect(text.contains("Wait-Process") and text.contains(".previous") and text.contains("Get-UpdateHash"), "Helper waits, backs up, verifies")
	var info := FileAccess.open("res://build/update_fixture/test-result.json", FileAccess.WRITE)
	info.store_string(JSON.stringify({"helper": helper, "source": saved_path}))
	info.close()
	get_tree().quit(t.finish("update_http"))
