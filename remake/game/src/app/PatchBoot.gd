extends Node
## Runs before application scripts are loaded. A trial is committed only by Main.

const STATE_PATH := "user://updates/patch-state.json"
const PACK_DIR := "user://updates/packs"
const GDPC_MAGIC: PackedByteArray = [71, 68, 80, 67]
const CRITICAL_SCRIPTS := ["res://src/domain/Round.gd", "res://src/anshun/scoring/ScoringEngine.gd", "res://src/presentation/TableView.gd", "res://src/app/Main.gd"]

var storage_path := STATE_PATH
var packs_directory := PACK_DIR
var base_version := ""
var base_id := ""
var base_version_code := 0
var effective_version := ""
var boot_message := ""
var enabled := false
var auto_mount_in_boot := true
var mount_callback: Callable
var _state: Dictionary = {}
var _trial := false
var _confirmed := false
var _verified_pack_signature := ""
var _watchdog_timer: Timer

func _init(auto_boot: bool = true) -> void:
	base_version = str(ProjectSettings.get_setting("application/config/version", "2.4.1"))
	base_id = str(ProjectSettings.get_setting("updates/base_id", ""))
	base_version_code = int(ProjectSettings.get_setting("updates/version_code", 0))
	effective_version = base_version
	enabled = OS.has_feature("template") and not OS.has_feature("editor") and not base_id.is_empty()
	if auto_boot and enabled:
		boot()

static func engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [info.major, info.minor, info.patch]

static func platform_key() -> String:
	match OS.get_name():
		"Android": return "android"
		"Windows": return "windows"
		"Linux", "X11": return "linux"
	return OS.get_name().to_lower()

static func valid_sha256(value: String) -> bool:
	if value.length() != 64: return false
	for c in value:
		if c not in "0123456789abcdef": return false
	return true

static func parse_semver(value: String) -> PackedInt32Array:
	var clean := value.substr(1) if value.begins_with("v") or value.begins_with("V") else value
	var parts := clean.split(".")
	if parts.size() != 3: return PackedInt32Array()
	var result := PackedInt32Array()
	for part in parts:
		if part.is_empty(): return PackedInt32Array()
		var number := 0
		for c in part:
			if c not in "0123456789": return PackedInt32Array()
			number = number * 10 + int(c)
			if number > 2147483647: return PackedInt32Array()
		result.append(number)
	return result

static func compare_semver(a: String, b: String) -> int:
	var left := parse_semver(a)
	var right := parse_semver(b)
	if left.size() != 3 or right.size() != 3: return -2
	for i in 3:
		if left[i] != right[i]: return 1 if left[i] > right[i] else -1
	return 0

func compatible(patch: Dictionary) -> bool:
	var target := parse_semver(str(patch.get("version", "")))
	var base := parse_semver(base_version)
	return target.size() == 3 and base.size() == 3 and target[0] == base[0] and compare_semver(str(patch.version), base_version) == 1 and str(patch.get("base_id", "")) == base_id and str(patch.get("base_version", "")) == base_version and str(patch.get("engine", "")) == engine_version() and str(patch.get("platform", "")).to_lower() in [platform_key(), "all"]

static func safe_filename(value: String) -> bool:
	return not value.is_empty() and value == value.validate_filename() and value == value.get_file() and value not in [".", ".."]

static func pack_size(patch: Dictionary) -> int:
	var value = patch.get("size_bytes", patch.get("size", 0))
	return int(value) if value is int or value is float else 0

func _pack_path(patch: Dictionary) -> String:
	return packs_directory.path_join(str(patch.get("sha256", "")) + ".pck")

func valid_pack(patch: Dictionary) -> bool:
	var sha := str(patch.get("sha256", ""))
	if not compatible(patch) or not valid_sha256(sha): return false
	var path := _pack_path(patch)
	if not FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	var length := file.get_length()
	var magic := file.get_buffer(4)
	file.close()
	if length != pack_size(patch) or magic != GDPC_MAGIC: return false
	var signature := "%s:%d:%d" % [path, length, FileAccess.get_modified_time(path)]
	if _verified_pack_signature == signature: return true
	if FileAccess.get_sha256(path).to_lower() != sha: return false
	_verified_pack_signature = signature
	return true

func _read_state() -> Dictionary:
	for path in [storage_path, storage_path + ".bak", storage_path + ".tmp"]:
		if not FileAccess.file_exists(path): continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK: continue
		var parsed = json.data
		if parsed is Dictionary and parsed.get("base_id") is String and parsed.get("trial", false) is bool and parsed.get("active", {}) is Dictionary and parsed.get("previous", {}) is Dictionary and parsed.get("pending", {}) is Dictionary:
			return parsed
	return {}

func _save_state() -> bool:
	var target_abs := ProjectSettings.globalize_path(storage_path)
	if DirAccess.make_dir_recursive_absolute(target_abs.get_base_dir()) != OK: return false
	var tmp := storage_path + ".tmp"
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	var bak_abs := target_abs + ".bak"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(_state))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	if FileAccess.file_exists(target_abs):
		if FileAccess.file_exists(bak_abs) and DirAccess.remove_absolute(bak_abs) != OK: return false
		if DirAccess.rename_absolute(target_abs, bak_abs) != OK: return false
	if DirAccess.rename_absolute(tmp_abs, target_abs) != OK:
		if FileAccess.file_exists(bak_abs): DirAccess.rename_absolute(bak_abs, target_abs)
		return false
	return true

func boot() -> void:
	if not enabled: return
	effective_version = base_version
	_trial = false
	_confirmed = false
	boot_message = ""
	_state = _read_state()
	if _state.get("base_id", "") != base_id:
		_state = {"base_id": base_id, "active": {}, "previous": {}, "pending": {}, "trial": false}
		if not _save_state(): return
	if _state.get("trial", false):
		_state.active = _state.get("previous", {})
		_state.previous = {}
		_state.pending = {}
		_state.trial = false
		boot_message = "上次热补丁未能正常启动，已自动回退原版本"
		if not _save_state(): return
	if not _state.get("pending", {}).is_empty():
		if valid_pack(_state.pending):
			_state.previous = _state.get("active", {})
			_state.active = _state.pending
			_state.pending = {}
			_state.trial = true
		else:
			_state.pending = {}
			boot_message = "热补丁校验失败，继续使用当前版本"
		if not _save_state(): return
	var active := active_patch()
	if not active.is_empty() and not _mount(active):
		_state.active = _state.get("previous", {})
		_state.previous = {}
		_state.trial = false
		if not _save_state(): return
		active = active_patch()
		if not active.is_empty() and not _mount(active):
			_state.active = {}
			_save_state()
		boot_message = "热补丁无法加载，已恢复原版本"
	_trial = bool(_state.get("trial", false))
	if not active_patch().is_empty(): effective_version = str(_state.active.version)

func _mount(patch: Dictionary) -> bool:
	if not valid_pack(patch): return false
	if mount_callback.is_valid(): return bool(mount_callback.call(ProjectSettings.globalize_path(_pack_path(patch))))
	if not auto_mount_in_boot: return false
	return ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(_pack_path(patch)), true)

func stage_patch(source_path: String, patch: Dictionary) -> bool:
	var sha := str(patch.get("sha256", ""))
	if not enabled or not compatible(patch) or not valid_sha256(sha) or not safe_filename(str(patch.get("filename", ""))): return false
	if not FileAccess.file_exists(source_path) or FileAccess.get_sha256(source_path).to_lower() != sha: return false
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null: return false
	var valid_source := source.get_length() == pack_size(patch) and source.get_buffer(4) == GDPC_MAGIC
	source.close()
	if not valid_source: return false
	var packs_abs := ProjectSettings.globalize_path(packs_directory)
	if DirAccess.make_dir_recursive_absolute(packs_abs) != OK: return false
	var source_abs := ProjectSettings.globalize_path(source_path)
	var target := _pack_path(patch)
	var target_abs := ProjectSettings.globalize_path(target)
	var tmp_abs := target_abs + ".tmp"
	if DirAccess.copy_absolute(source_abs, tmp_abs) != OK:
		if FileAccess.file_exists(tmp_abs): DirAccess.remove_absolute(tmp_abs)
		return false
	if FileAccess.get_sha256(tmp_abs).to_lower() != sha:
		DirAccess.remove_absolute(tmp_abs)
		return false
	_verified_pack_signature = ""
	if FileAccess.file_exists(target_abs) and valid_pack(patch):
		DirAccess.remove_absolute(tmp_abs)
	else:
		if FileAccess.file_exists(target_abs) and DirAccess.remove_absolute(target_abs) != OK:
			DirAccess.remove_absolute(tmp_abs)
			return false
		if DirAccess.rename_absolute(tmp_abs, target_abs) != OK:
			DirAccess.remove_absolute(tmp_abs)
			return false
	if not valid_pack(patch):
		DirAccess.remove_absolute(target_abs)
		return false
	_state = _read_state()
	if _state.get("base_id", "") != base_id: _state = {"base_id": base_id, "active": {}, "previous": {}, "trial": false}
	_state.pending = patch.duplicate(true)
	return _save_state()

func pending_patch() -> Dictionary:
	return _state.get("pending", {}).duplicate(true)

func active_patch() -> Dictionary:
	return _state.get("active", {}).duplicate(true)

func is_patched() -> bool:
	return not active_patch().is_empty() and effective_version != base_version

func can_rollback() -> bool:
	return is_patched() and not _trial

func prepare_rollback() -> bool:
	if not can_rollback(): return false
	_state.active = _state.get("previous", {})
	_state.previous = {}
	_state.pending = {}
	_state.trial = false
	return _save_state()

func _ready() -> void:
	if _trial and DisplayServer.get_name() != "headless":
		_watchdog_timer = Timer.new()
		_watchdog_timer.one_shot = true
		_watchdog_timer.wait_time = 20.0
		_watchdog_timer.timeout.connect(_watchdog)
		add_child(_watchdog_timer)
		_watchdog_timer.start()

func _watchdog() -> void:
	if not _trial or _confirmed: return
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()

func confirm_boot() -> bool:
	if not _trial or _confirmed: return false
	for path in CRITICAL_SCRIPTS:
		var script = load(path)
		if not script is Script or not script.can_instantiate(): return false
	_state.trial = false
	if not _save_state():
		_state.trial = true
		return false
	_trial = false
	_confirmed = true
	if is_instance_valid(_watchdog_timer): _watchdog_timer.stop()
	boot_message = "热补丁 v%s 已生效" % effective_version
	_cleanup_packs()
	return true

func _cleanup_packs() -> void:
	var keep := []
	for key in ["active", "previous", "pending"]:
		keep.append(str(_state.get(key, {}).get("sha256", "")) + ".pck")
	var dir := DirAccess.open(packs_directory)
	if dir == null: return
	for filename in dir.get_files():
		if filename.ends_with(".pck") and filename not in keep: dir.remove(filename)
