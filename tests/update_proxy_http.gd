extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var base := ""
var manager
var fixture: Dictionary

class TestUpdater extends "res://scripts/autoload/UpdateManager.gd":
	var package_routes: Array[String] = []
	var manifest_routes: Array[String] = []
	var opened: Array[String] = []
	func _routes_for(url: String) -> Array[String]:
		return manifest_routes.duplicate() if url.ends_with(".json") else package_routes.duplicate()
	func _open_browser_url(url: String) -> Error:
		opened.append(url)
		return OK

func _initialize() -> void: call_deferred("_run")

func _wait(done: Callable, seconds: float = 14.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not done.call() and Time.get_ticks_msec() < deadline: await process_frame
	return done.call()

func _set_package(kind: String = "full") -> void:
	manager.latest = fixture[kind].duplicate(true)
	manager.state = "available"

func _download(paths: Array, kind: String = "full", success: bool = true) -> void:
	_set_package(kind)
	manager.package_routes.clear()
	for path in paths: manager.package_routes.append(base + str(path))
	manager.download_update()
	t.expect(await _wait(func(): return manager.state != "downloading"), "bounded download: " + str(paths))
	t.expect(manager.state == ("ready" if success else "error"), "download result: " + str(paths) + " / " + manager.message)
	if success:
		t.expect(FileAccess.get_sha256(manager.downloaded_path) == fixture[kind].sha256, "every accepted route ends with authoritative SHA256")
		t.expect(manager.downloaded_bytes == fixture[kind].size, "final progress is whole file, not last Range chunk")
	else:
		t.expect(not FileAccess.file_exists(manager._partial_path) and not FileAccess.file_exists(manager._chunk_path), "exhausted routes remove partial files")

func _manifest(paths: Array, endpoint: String = "/release", success: bool = true) -> void:
	manager.manifest_routes.clear()
	for path in paths: manager.manifest_routes.append(base + str(path))
	manager.manifest_url = base + endpoint
	manager.check_updates()
	t.expect(await _wait(func(): return manager.state != "checking"), "manifest failover completes")
	t.expect(manager.state == ("available" if success else "error"), "manifest result: " + str(paths) + " / " + manager.message)
	if success: t.expect(manager.latest.version == "9.0.10", "fallback preserves GitHub release version and digest context")

func _link(paths: Array, expected: String) -> void:
	_set_package("android")
	manager.package_routes.clear()
	for path in paths: manager.package_routes.append(base + str(path))
	manager.opened.clear()
	t.expect(manager.open_download_page() == OK, "APK link selection starts")
	t.expect(await _wait(func(): return manager.state != "opening"), "APK link selection completes")
	t.expect(manager.opened == ([base + expected] if expected != "" else []), "only a verified usable APK route opens in browser")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proxy-base="): base = arg.trim_prefix("--proxy-base=")
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://build/update_proxy_fixture/fixture.json"))
	manager = TestUpdater.new()
	root.add_child(manager)
	manager.auto_check = false
	manager._range_chunk_bytes = 1024
	manager.download_directory = "res://build/update_proxy_fixture/downloads"
	await _manifest(["/fail", "/html", "/manifest"])
	await _manifest(["/wrong-manifest", "/manifest"])
	await _manifest(["/wrong-manifest", "/fail"], "/release", false)
	await _manifest(["/missing", "/manifest"])
	await _manifest(["/missing", "/missing"], "/release", false)
	await _download(["/fail", "/limited", "/html", "/full"])
	await _download(["/partial", "/resume"])
	await _download(["/partial", "/ignore-range"])
	await _download(["/partial", "/bad-range", "/resume"])
	await _download(["/corrupt", "/full"])
	await _download(["/stall", "/full"])
	await _download(["/fail", "/patch"], "patch")
	await _download(["/fail", "/corrupt"], "full", false)
	# Cancellation kills active work and cannot start another route later.
	_set_package()
	manager.package_routes.assign([base + "/slow", base + "/cancel-must-not-run"])
	manager.download_update()
	await create_timer(0.1).timeout
	manager.cancel_download()
	await create_timer(0.4).timeout
	t.expect(manager.state == "available" and not FileAccess.file_exists(manager._partial_path) and not FileAccess.file_exists(manager._chunk_path), "cancel stops failover and removes chunks")
	await _link(["/fail", "/html", "/apk"], "/apk")
	await _link(["/apk", "/apk-backup"], "/apk-backup")
	await _link(["/head-not-supported"], "/head-not-supported")
	await _link(["/html", "/fail"], "")
	_set_package("android")
	manager.package_routes.assign([base + "/slow", base + "/cancel-must-not-run"])
	manager.open_download_page()
	manager.cancel_download()
	await create_timer(0.1).timeout
	t.expect(manager.state == "available" and manager.opened.is_empty(), "cancel APK probe never opens browser")
	manager.free()
	quit(t.finish("update_proxy_http"))
