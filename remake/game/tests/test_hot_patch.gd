extends SceneTree

const Boot := preload("res://src/app/PatchBoot.gd")
var checks := 0
var failures := 0
var folder := "user://test-hot-patch-%d" % Time.get_ticks_usec()
var mounted := []

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + text)

func _initialize() -> void:
	_run.call_deferred()

func make_boot():
	var boot := Boot.new(false)
	boot.enabled = true
	boot.storage_path = folder.path_join("patch-state.json")
	boot.packs_directory = folder.path_join("packs")
	boot.base_version = "2.4.1"
	boot.effective_version = boot.base_version
	boot.base_id = "2.4.1-r1"
	boot.mount_callback = func(path): mounted.append(path); return true
	return boot

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var boot = make_boot()
	check(root.get_node("PatchBoot").enabled == (OS.has_feature("template") and not OS.has_feature("editor")), "autoload gated by export features")
	var source := folder.path_join("source.pck")
	write_bytes(source, PackedByteArray([71, 68, 80, 67, 1, 2, 3, 4]))
	var patch := {"version": "2.4.2", "base_version": "2.4.1", "base_id": "2.4.1-r1", "engine": Boot.engine_version(), "platform": Boot.platform_key(), "filename": "patch.pck", "size_bytes": 8, "sha256": FileAccess.get_sha256(source)}
	for target in ["2.4.2", "2.5.0"]:
		var entry := patch.duplicate(); entry.version = target
		check(boot.compatible(entry), "compatible bump " + target)
	for target in ["3.0.0", "2.4.1", "2.4.0", "2.4", "vV2.4.2"]:
		var entry := patch.duplicate(); entry.version = target
		check(not boot.compatible(entry), "reject version " + target)
	for pair in [["base_id", "wrong"], ["base_version", "2.4.0"], ["engine", "0.0.0"], ["platform", "unknown"]]:
		var entry := patch.duplicate(); entry[pair[0]] = pair[1]
		check(not boot.compatible(entry), "reject " + pair[0])
	var all := patch.duplicate(); all.platform = "ALL"
	check(boot.compatible(all), "platform all is case insensitive")
	check(Boot.compare_semver("v2.5.0", "2.4.9") == 1 and Boot.compare_semver("2.4.1", "2.4.1") == 0 and Boot.compare_semver("1.0.0", "2.0.0") == -1 and Boot.compare_semver("2.-4.1", "2.4.1") == -2, "strict semantic versions")
	check(Boot.parse_semver("V2.4.2147483647").size() == 3 and Boot.parse_semver("2.4.2147483648").is_empty(), "semantic version integer bounds")
	check(not Boot.valid_sha256("A".repeat(64)), "reject uppercase hashes")
	for pair in [["sha256", "0".repeat(64)], ["size_bytes", 9], ["filename", "../patch.pck"], ["filename", "..\\patch.pck"]]:
		var entry := patch.duplicate(); entry[pair[0]] = pair[1]
		check(not boot.stage_patch(source, entry), "reject invalid stage " + pair[0])
	var bad_source := folder.path_join("bad.pck")
	write_bytes(bad_source, PackedByteArray([0, 0, 0, 0, 1, 2, 3, 4]))
	var bad := patch.duplicate(); bad.sha256 = FileAccess.get_sha256(bad_source)
	check(not boot.stage_patch(bad_source, bad), "reject invalid magic even with correct hash")
	check(boot.stage_patch(source, patch), "stage valid pack")
	check(FileAccess.file_exists(boot.packs_directory.path_join(patch.sha256 + ".pck")) and boot.pending_patch().sha256 == patch.sha256, "content addressed pack and pending state")
	check(FileAccess.file_exists(boot.storage_path) and not FileAccess.file_exists(boot.storage_path + ".tmp"), "atomic state committed")
	boot.free(); boot = make_boot(); boot.boot()
	check(boot.active_patch().sha256 == patch.sha256 and boot.pending_patch().is_empty() and boot._trial and boot.effective_version == "2.4.2", "pending promoted before mount")
	check(mounted.size() == 1 and mounted[0].ends_with(patch.sha256 + ".pck"), "mount callback received content path")
	boot.free(); boot = make_boot(); boot.boot()
	check(boot.effective_version == "2.4.1" and not boot._trial and boot.active_patch().is_empty(), "crashed trial reverts to base")
	check("自动回退" in boot.boot_message and not boot.confirm_boot(), "rollback message and no false confirmation")
	check(boot.stage_patch(source, patch), "restage after rollback")
	boot.boot()
	write_bytes(boot.packs_directory.path_join("stale.pck"), PackedByteArray([1]))
	check(boot.confirm_boot() and not boot._trial and boot._confirmed and "已生效" in boot.boot_message, "critical scripts confirm boot")
	check(not boot.confirm_boot() and not FileAccess.file_exists(boot.packs_directory.path_join("stale.pck")), "confirmation idempotent and stale pack pruned")
	var next_source := folder.path_join("next.pck")
	write_bytes(next_source, PackedByteArray([71, 68, 80, 67, 5, 6, 7, 8]))
	var next := patch.duplicate(); next.version = "2.4.3"; next.sha256 = FileAccess.get_sha256(next_source)
	check(boot.stage_patch(next_source, next), "stage second patch")
	boot.free(); boot = make_boot(); boot.boot()
	check(boot.effective_version == "2.4.3" and boot._state.previous.sha256 == patch.sha256 and boot.confirm_boot(), "second patch retains previous confirmed pack")
	check(boot.can_rollback() and boot.prepare_rollback(), "prepare rollback to previous patch")
	boot.free(); boot = make_boot(); boot.boot()
	check(boot.effective_version == "2.4.2" and not boot._trial, "manual rollback restores previous patch")
	check(boot.can_rollback() and boot.prepare_rollback(), "prepare manual rollback")
	boot.free(); boot = make_boot(); boot.boot()
	check(boot.effective_version == "2.4.1" and not boot.can_rollback(), "manual rollback returns to base")
	check(boot.stage_patch(source, patch), "stage for mount failure")
	boot.mount_callback = func(_path): return false
	boot.boot()
	check(boot.effective_version == "2.4.1" and "无法加载" in boot.boot_message and not boot._trial, "failed mount rolls back")
	# A torn primary state must recover from the last complete backup.
	write_bytes(boot.storage_path, "{".to_utf8_buffer())
	check(not boot._read_state().is_empty(), "recover backup after torn state")
	# A new full-package base cannot reuse patches from the old installation.
	boot.base_id = "2.4.1-r2"
	boot.boot()
	check(boot.active_patch().is_empty() and boot.pending_patch().is_empty() and boot.effective_version == boot.base_version, "base id change resets stale state")
	boot.free()
	remove_tree(folder)
	print("HotPatch: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func write_bytes(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()

func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for child in dir.get_directories(): remove_tree(path.path_join(child))
	for child in dir.get_files(): dir.remove(child)
	DirAccess.remove_absolute(path)
