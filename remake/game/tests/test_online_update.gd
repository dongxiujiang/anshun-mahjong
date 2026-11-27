extends SceneTree

const Boot := preload("res://src/app/PatchBoot.gd")
const Manager := preload("res://src/app/UpdateManager.gd")
const Dialog := preload("res://src/app/UpdateDialog.gd")
const Settings := preload("res://src/app/AppSettings.gd")
const Main := preload("res://scenes/Main.tscn")
const AudioRetirement := preload("res://tests/AudioRetirement.gd")
var checks := 0
var failures := 0
var folder := "user://test-online-update-%d" % Time.get_ticks_usec()
var server := TCPServer.new()
var peers := []
var manifest: Dictionary = {}
var payload := PackedByteArray([71, 68, 80, 67, 1, 2, 3, 4])
var origin := ""
var requests := 0
var manifest_requests := 0
var redirect_target := "/v1/downloads/update.pck"
var states := []

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + text)

func _initialize() -> void:
	_run.call_deferred()

func _process(_delta: float) -> bool:
	while server.is_connection_available():
		peers.append({"socket": server.take_connection(), "data": PackedByteArray()})
	for index in range(peers.size() - 1, -1, -1):
		var peer: StreamPeerTCP = peers[index].socket
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host(); peers.remove_at(index); continue
		if peer.get_available_bytes() > 0:
			var incoming := peer.get_data(peer.get_available_bytes())
			if incoming[0] == OK: peers[index].data.append_array(incoming[1])
		var text: String = peers[index].data.get_string_from_utf8()
		if not "\r\n\r\n" in text: continue
		requests += 1
		var path := text.split(" ")[1]
		if path == "/v1/updates/manifest": manifest_requests += 1
		if path == "/redirect":
			peer.put_data(("HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % redirect_target).to_utf8_buffer())
			peer.disconnect_from_host(); peers.remove_at(index); continue
		var body: PackedByteArray = JSON.stringify(manifest).to_utf8_buffer() if path == "/v1/updates/manifest" else payload
		var header := "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n" % body.size()
		peer.put_data(header.to_utf8_buffer() + body)
		peer.disconnect_from_host()
		peers.remove_at(index)
	return false

func until(predicate: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		if predicate.call(): return true
		await process_frame
		OS.delay_msec(1)
	return false

func digest(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	check(server.listen(0, "127.0.0.1") == OK, "HTTP fixture starts on ephemeral loopback port")
	origin = "http://127.0.0.1:%d" % server.get_local_port()
	var boot := Boot.new(false)
	boot.enabled = true
	boot.base_version = "2.4.1"; boot.effective_version = "2.4.1"; boot.base_id = "2.4.1-r1"
	boot.storage_path = folder.path_join("state.json"); boot.packs_directory = folder.path_join("packs")
	boot.mount_callback = func(_path): return true
	root.add_child(boot)
	var manager := Manager.new()
	manager.boot_override = boot
	manager.allow_insecure_loopback = true
	manager.download_directory = folder.path_join("downloads")
	root.add_child(manager)
	manager.configure(origin)
	manager.state_changed.connect(func(snap): states.append(snap.state))
	var patch := {"version": "2.4.2", "base_version": "2.4.1", "base_id": "2.4.1-r1", "engine": Boot.engine_version(), "platform": "all", "filename": "update.pck", "sha256": digest(payload), "size_bytes": payload.size(), "download_url": "/v1/downloads/update.pck", "notes": ["修复显示问题"], "available": true}
	var full := {"version": "2.4.2", "version_code": 9, "platform": Boot.platform_key(), "filename": "update.zip", "sha256": "a".repeat(64), "size_bytes": 8, "download_url": "/updates/update.zip", "available": true, "changelog": ["更新说明"]}
	for url in ["https://example.com/a", "https://example.com:8443/a", "http://127.0.0.1:123/a", "http://localhost/a", "http://[::1]:8080/a"]:
		check(Manager.safe_url(url, true), "allow safe URL " + url)
	for url in ["http://example.com/a", "file:///tmp/a", "https://user@example.com/a", "https://example.com/ a", "https://example.com/\na", "https://example.com/\u00a0a", "http://127.0.0.1.evil/a", "http://localhost.evil/a", "https://example.com:0/a", "https://example.com\\evil/a", "//example.com/a"]:
		check(not Manager.safe_url(url, true), "reject unsafe URL " + url.replace("\n", "\\n"))
	check(not Manager.safe_url(origin), "loopback requires explicit permission")
	check(Manager.resolve_asset_url("/v1/downloads/update.pck", origin + "/v1/updates/manifest") == origin + "/v1/downloads/update.pck", "asset URL preserves origin and port")
	manifest = {"hotpatches": [patch], "packages": {Boot.platform_key(): full}}
	check(manager.select_update(manifest, origin).get("kind") == "patch", "same version prefers hotpatch")
	for version in ["2.5.0", "3.0.0"]:
		full.version = version
		check(manager.select_update(manifest, origin).get("kind") == "full", "newer full package wins " + version)
	full.version = "2.4.2"
	var incompatible := patch.duplicate(); incompatible.base_id = "wrong"
	check(manager.select_update({"hotpatches": [incompatible], "latest_release": full}, origin).get("kind") == "full", "incompatible patch falls back to full")
	var current_code := manager.current_version_code()
	full.version = "2.4.1"; full.version_code = current_code + 1
	check(manager.select_update({"release": full}, origin).get("kind") == "full", "legacy release response and version code bump")
	full.version_code = current_code
	check(manager.select_update({"latest_release": full}, origin).is_empty(), "same version and code up to date")
	boot.effective_version = "2.4.2"
	check(manager.select_update({"release": full}, origin).is_empty(), "base package cannot replace newer patched version")
	boot.effective_version = "2.4.1"
	var newer_patch := patch.duplicate(); newer_patch.version = "2.4.3"
	check(manager.select_update({"hotpatches": [patch, newer_patch]}, origin).get("version") == "2.4.3", "highest compatible patch selected")
	var unsafe := patch.duplicate(); unsafe.download_url = "http://evil.example/update.pck"
	check(manager.select_update({"hotpatches": [unsafe]}, origin).is_empty(), "unsafe patch download rejected")
	var direct := patch.duplicate(); direct.download_url = ""; direct.direct_url = "/updates/update.pck"
	check(manager.select_update({"hotpatches": [direct]}, origin).get("url") == origin + "/updates/update.pck", "empty download URL falls back to direct URL")
	var malformed := patch.duplicate(); malformed.size_bytes = {}
	check(manager.select_update({"hotpatches": [malformed]}, origin).is_empty(), "malformed size is rejected without engine errors")
	manager.maybe_auto_check()
	check(manager.state == "idle" and manager._check_req == null and not manager._auto_checked, "headless auto check is strict no-op")
	manifest = {"hotpatches": [patch]}
	check(manager.check_updates(), "start real manifest request")
	check(await until(func(): return manager.state != "checking") and manager.state == "available", "HTTP manifest finds hotpatch")
	check(manager.latest.url == origin + "/v1/downloads/update.pck", "relative URL normalized during HTTP check")
	check(manager.start_download(), "start streamed pack download")
	check(await until(func(): return manager.state != "downloading") and manager.state == "ready", "verified download staged and ready")
	check(boot.pending_patch().get("sha256") == patch.sha256 and boot.valid_pack(boot.pending_patch()), "pending patch has verified bytes")
	check(states.has("checking") and states.has("available") and states.has("downloading") and states.has("ready"), "all expected state transitions emitted")
	check(not FileAccess.file_exists(manager._part_path), "staged download removes part file")
	manager.can_restart_callback = func(): return false
	check(not manager.apply_and_restart() and "请先退出" in manager.message, "active room blocks apply restart")
	check(not manager.rollback_and_restart() and "请先退出" in manager.message, "active room blocks rollback restart")
	check(manager.check_updates() and await until(func(): return manager.state != "checking") and manager.state == "ready", "already staged patch is ready after check")
	manager.manifest_url_override = origin + "/redirect"
	redirect_target = "/v1/updates/manifest"
	check(manager.check_updates() and await until(func(): return manager.state != "checking") and manager.state == "ready", "manifest follows validated server redirect")
	manager.manifest_url_override = ""
	redirect_target = "/v1/downloads/update.pck"
	var redirected := patch.duplicate(); redirected.download_url = "/redirect"
	manager.latest = manager._normalize(redirected, "patch", origin); manager.state = "available"
	check(manager.start_download() and await until(func(): return manager.state != "downloading") and manager.state == "ready", "download follows validated static-file redirect")
	redirect_target = "http://external.example/update.pck"
	manager.state = "available"
	check(manager.start_download() and await until(func(): return manager.state != "downloading") and manager.state == "error" and not FileAccess.file_exists(manager._part_path), "unsafe redirect rejected with part cleanup")
	redirect_target = "/v1/downloads/update.pck"
	manager.latest = manager._normalize(patch, "patch", origin)
	# Editor mode retains verified bytes without changing the global pack table.
	boot.enabled = false
	manager.state = "available"
	check(manager.start_download() and await until(func(): return manager.state != "downloading") and manager.state == "ready" and FileAccess.file_exists(manager.downloaded_path), "development mode saves verified pack")
	manager.can_restart_callback = func(): return true
	check(not manager.apply_and_restart() and "开发运行模式" in manager.message, "development mode explains restart restriction")
	boot.enabled = true
	for mode in ["sha", "magic", "size"]:
		payload = PackedByteArray([0, 0, 0, 0, 1, 2, 3, 4]) if mode == "magic" else PackedByteArray([71, 68, 80, 67, 4, 3, 2, 1])
		var bad := patch.duplicate()
		bad.sha256 = digest(payload) if mode != "sha" else "0".repeat(64)
		if mode == "size": bad.size_bytes = 9
		manager.latest = manager._normalize(bad, "patch", origin)
		manager.state = "available"
		check(manager.start_download() and await until(func(): return manager.state != "downloading") and manager.state == "error", "reject corrupted download " + mode)
		check(not FileAccess.file_exists(manager._part_path), "bad part removed " + mode)
	manager.state = "available"
	check(manager.start_download(), "start cancelable download")
	manager.cancel_download()
	check(manager.state == "available" and not FileAccess.file_exists(manager._part_path), "cancel cleans stream and part")
	# Exercise desktop full-package magic and final-file move via the same HTTP fixture.
	payload = PackedByteArray([80, 75, 3, 4, 1, 2, 3, 4])
	full.sha256 = digest(payload); full.version = "2.4.2"
	manager.latest = manager._normalize(full, "full", origin); manager.state = "available"
	check(manager.start_download() and await until(func(): return manager.state != "downloading") and manager.state == "ready" and manager.downloaded_path.ends_with("update.zip"), "desktop full package verified and moved")
	var snap := manager.snapshot(); snap.latest.version = "999.0.0"
	check(manager.latest.version == "2.4.2", "snapshot is detached from manager state")
	var dialog := Dialog.new(); root.add_child(dialog)
	for value in [["available", "patch", "下载热补丁"], ["available", "full", "下载新版安装包"], ["downloading", "patch", "取消下载"], ["ready", "patch", "重启生效"], ["ready", "full", "打开安装包"], ["up_to_date", "", "检查更新"], ["error", "", "检查更新"]]:
		var entry := patch.duplicate(); entry.kind = value[1]
		var ui_state := {"state": value[0], "latest": entry if not value[1].is_empty() else {}, "message": "测试状态", "current_version": "2.4.1", "total_bytes": 8, "downloaded_bytes": 4, "can_rollback": true}
		dialog.open_dialog(ui_state)
		await process_frame
		check(dialog.visible and dialog._primary.text == value[2] and dialog._progress.visible == (value[0] in ["downloading", "ready"]), "dialog renders " + value[0] + " " + value[1])
		check(dialog._rollback.visible == (value[0] != "downloading"), "rollback visibility " + value[0])
	var actions := []
	dialog.download_requested.connect(func(): actions.append("download"))
	dialog.apply_snapshot({"state": "available", "latest": {"kind": "patch"}})
	dialog._primary.pressed.emit()
	check(actions == ["download"], "dialog emits action signal")
	dialog.close_dialog(); check(not dialog.visible, "dialog closes")
	dialog.free()
	# Real Main uses its own manager; headless startup must create no HTTPRequest.
	var settings := Settings.new(folder.path_join("profile.cfg"))
	settings.save_profile("更新测试", 1)
	settings.update({"directory_url": origin})
	var app := Main.instantiate(); app._settings = settings
	for i in 8: await process_frame
	var before := manifest_requests
	root.add_child(app)
	for i in 4: await process_frame
	check(app._update_manager._check_req == null and not app._update_manager._auto_checked and manifest_requests == before, "Main headless boot never auto checks")
	check(find_button(app, "更新") != null, "lobby update button exists")
	app._open_settings()
	var panel = app._room_settings_panel
	check(panel.tabs.get_tab_count() == 2 and panel.tabs.get_tab_title(0) == "对局" and panel.tabs.get_tab_title(1) == "声音", "settings keeps exactly two approved tabs")
	check(find_button(panel, "检查更新") != null, "settings header update button exists")
	app._open_update_dialog()
	app._go_back()
	check(not app._update_dialog.visible and app._screen == "settings", "back closes update dialog before settings")
	await AudioRetirement.release_app(app, self)
	manager.free(); boot.free()
	for item in peers: item.socket.disconnect_from_host()
	peers.clear(); server.stop(); server = null
	remove_tree(folder)
	print("OnlineUpdate: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := find_button(child, text)
		if found != null: return found
	return null

func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for child in dir.get_directories(): remove_tree(path.path_join(child))
	for child in dir.get_files(): dir.remove(child)
	DirAccess.remove_absolute(path)
