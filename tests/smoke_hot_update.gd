extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var manager = load("res://scripts/autoload/UpdateManager.gd").new()
	root.add_child(manager)
	var boot := root.get_node("PatchBoot")
	var current := str(ProjectSettings.get_setting("application/config/version", ""))
	var next := _next_version(current)
	var patch := {"base_id": boot.base_id, "base_version": boot.base_version, "engine": boot.engine_version(), "url": "https://example.com/patch.pck", "sha256": "a".repeat(64), "size": 1234}
	var full := {"url": "https://example.com/app.exe", "sha256": "b".repeat(64), "size": 9999}
	var data := {"schema": 2, "version": next, "patches": {"windows": patch, "android": patch}, "packages": {"windows": full, "android": full}, "release_url": "https://example.com/release"}
	manager.apply_release(data, "windows")
	t.expect(manager.state == "available" and manager.latest.kind == "patch" and manager.can_download(), "兼容小版本优先选择补丁")
	t.expect(manager.latest.size == 1234 and manager.message.contains("无需"), "小版本显示补丁大小")
	manager.apply_release(data, "android")
	t.expect(manager.latest.kind == "patch" and manager.can_download(), "Android 小版本也在游戏内下载")
	manager.state = "ready"
	t.expect(not manager.can_install(), "工程调试不会加载用户补丁")
	for field in ["base_id", "base_version", "engine", "platform"]:
		var bad := data.duplicate(true)
		bad.patches.windows[field] = "incompatible"
		manager.apply_release(bad, "windows")
		t.expect(manager.latest.kind == "full" and manager.latest.size == 9999, "不兼容 %s 使用完整安装包" % field)
	var major := data.duplicate(true)
	major.version = "2.0.0"
	manager.apply_release(major, "windows")
	t.expect(manager.latest.kind == "full", "新主版本需要完整应用")
	var invalid := data.duplicate(true)
	invalid.patches.windows.sha256 = ""
	manager.apply_release(invalid, "windows")
	t.expect(manager.state == "error", "没有摘要不下载代码补丁")
	invalid = data.duplicate(true)
	invalid.patches.windows.url = "http://example.com/patch.pck"
	manager.apply_release(invalid, "windows")
	t.expect(manager.state == "error", "拒绝 HTTP 补丁地址")
	var old := data.duplicate(true)
	old.version = current
	manager.apply_release(old, "windows")
	t.expect(manager.state == "current", "补丁不降级")
	var fallback := data.duplicate(true)
	fallback.packages = {}
	fallback.patches.windows.base_id = "old-install"
	fallback.installation_url = "https://example.com/full-release"
	manager.apply_release(fallback, "windows")
	t.expect(manager.latest.kind == "full" and manager.latest.page.ends_with("full-release"), "旧安装版可前往完整基线发布页")
	# Exercise durable staging without touching the actual application's user data.
	var isolated = load("res://scripts/autoload/PatchBoot.gd").new()
	isolated.enabled = true
	isolated.storage_path = "res://build/hot_unit/patch-state.json"
	isolated.packs_directory = "res://build/hot_unit/packs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/hot_unit"))
	var source := "res://build/hot_unit/test.pck"
	var file := FileAccess.open(source, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([71, 68, 80, 67, 0, 0, 0, 0]))
	file.close()
	var entry := patch.duplicate(true)
	entry.merge({"version": next, "platform": "windows", "sha256": FileAccess.get_sha256(source), "size": 8}, true)
	t.expect(isolated.stage_patch(ProjectSettings.globalize_path(source), entry), "补丁写入独立目录并持久保存待应用状态")
	t.expect(isolated.pending_patch().get("version", "") == next, "重启前读取待应用版本")
	var stored: Dictionary = isolated.pending_patch()
	file = FileAccess.open(isolated._pack_path(stored), FileAccess.WRITE)
	file.store_string("damaged")
	file.close()
	t.expect(isolated.pending_patch().is_empty(), "待应用补丁被损坏时拒绝使用")
	entry.base_id = "wrong"
	t.expect(not isolated.stage_patch(ProjectSettings.globalize_path(source), entry), "不同基线不能保存为待应用补丁")
	isolated.free()
	manager.queue_free()
	await process_frame
	quit(t.finish("smoke_hot_update"))

func _next_version(value: String) -> String:
	var parts := value.split(".")
	if parts.size() != 3: return value
	return "%s.%s.%d" % [parts[0], parts[1], int(parts[2]) + 1]
