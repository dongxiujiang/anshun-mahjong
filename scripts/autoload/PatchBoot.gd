extends Node
## Stable first autoload. Mount in _init(), before any game script is loaded.
## Changes to this file, project settings or global class declarations require a full install.
const STATE_PATH := "user://updates/patch-state.json"
const PACK_DIR := "user://updates/packs"
var storage_path := STATE_PATH
var packs_directory := PACK_DIR
var base_version := ""
var base_id := ""
var effective_version := ""
var boot_message := ""
var enabled := false
var _state: Dictionary = {}
var _trial := false
var _confirmed := false
var _verified_pack_signature := ""

func _init() -> void:
	base_version = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	base_id = str(ProjectSettings.get_setting("updates/base_id", ""))
	effective_version = base_version
	enabled = OS.has_feature("template") and not OS.has_feature("editor") and base_id != ""
	if enabled: _boot()

static func engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [info.major, info.minor, info.patch]

static func platform_key() -> String:
	return "android" if OS.get_name() == "Android" else "windows"

static func _valid_hash(value: String) -> bool:
	if value.length() != 64: return false
	for c in value.to_utf8_buffer():
		if not (c >= 48 and c <= 57 or c >= 97 and c <= 102): return false
	return true

static func _version(value: String) -> PackedInt32Array:
	var pieces := value.split(".")
	if pieces.size() != 3: return PackedInt32Array()
	var out := PackedInt32Array()
	for piece in pieces:
		if piece == "" or piece.length() > 8: return PackedInt32Array()
		for c in piece.to_utf8_buffer():
			if c < 48 or c > 57: return PackedInt32Array()
		out.append(piece.to_int())
	return out

func compatible(patch: Dictionary) -> bool:
	var target := _version(str(patch.get("version", "")))
	var base := _version(base_version)
	if target.size() != 3 or base.size() != 3 or target[0] != base[0]: return false
	if target[1] < base[1] or target[1] == base[1] and target[2] <= base[2]: return false
	return str(patch.get("base_id", "")) == base_id and str(patch.get("base_version", "")) == base_version and str(patch.get("engine", "")) == engine_version() and str(patch.get("platform", "")) == platform_key()

func _read_state() -> Dictionary:
	# A interrupted rename can leave only the previous JSON file.
	for path in [storage_path, storage_path + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and int(data.get("schema", 0)) == 1: return data
	return {"schema": 1}

func _save_state() -> bool:
	var absolute := ProjectSettings.globalize_path(storage_path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK: return false
	var file := FileAccess.open(storage_path + ".tmp", FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(_state))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return false
	var backup := absolute + ".bak"
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK: return false
		if DirAccess.rename_absolute(absolute, backup) != OK: return false
	if DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK: return false
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	return true

func _pack_path(patch: Dictionary) -> String:
	var name_value := str(patch.get("file", ""))
	# Only a content-addressed file inside our own pack directory is mountable.
	if not _valid_hash(str(patch.get("sha256", ""))) or name_value != str(patch.sha256) + ".pck": return ""
	return packs_directory.path_join(name_value)

func valid_pack(patch: Dictionary) -> bool:
	if not compatible(patch): return false
	var sha := str(patch.get("sha256", ""))
	var path := _pack_path(patch)
	if path == "" or not FileAccess.file_exists(path): return false
	# Cache by content identity plus on-disk size/mtime. A corrupted or replaced
	# file invalidates the cache; the boot path then avoids hashing the same
	# still-valid pack twice.
	var probe := FileAccess.open(path, FileAccess.READ)
	if probe == null: return false
	var disk_length := probe.get_length()
	probe.close()
	var signature := "%s:%d:%d" % [sha, disk_length, FileAccess.get_modified_time(path)]
	if signature == _verified_pack_signature: return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	var valid := file.get_length() == int(patch.get("size", 0)) and file.get_buffer(4) == PackedByteArray([71, 68, 80, 67])
	file.close()
	if valid and FileAccess.get_sha256(path) == sha:
		_verified_pack_signature = signature
		return true
	return false

func _boot() -> void:
	_state = _read_state()
	if str(_state.get("base_id", base_id)) != base_id:
		_state = {"schema": 1, "base_id": base_id}
		_save_state()
	if bool(_state.get("trial", false)):
		_state["active"] = _state.get("previous", {})
		_state["previous"] = {}
		_state["pending"] = {}
		_state["trial"] = false
		_save_state()
		boot_message = "上次小版本未能正常启动，已恢复原版本"
	var pending = _state.get("pending", {})
	if pending is Dictionary and not pending.is_empty():
		if valid_pack(pending):
			_state["previous"] = _state.get("active", {})
			_state["active"] = pending
			_state["pending"] = {}
			_state["trial"] = true
			_trial = _save_state()
			if not _trial: return # Never mount a patch without recording recovery state first.
		else:
			_state["pending"] = {}
			_save_state()
			boot_message = "小版本文件校验失败，继续使用原版本"
	var active = _state.get("active", {})
	if not active is Dictionary or active.is_empty(): return
	if not _mount(active):
		_state["active"] = _state.get("previous", {})
		_state["previous"] = {}
		_state["trial"] = false
		_trial = false
		_save_state()
		active = _state.active
		if active is Dictionary and not active.is_empty(): _mount(active)
		boot_message = "小版本无法加载，已恢复原版本"

func _mount(patch: Dictionary) -> bool:
	if not valid_pack(patch): return false
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(_pack_path(patch)), true): return false
	effective_version = str(patch.version)
	return true

func stage_patch(source: String, patch: Dictionary) -> bool:
	if not enabled or not compatible(patch): return false
	var sha := str(patch.get("sha256", ""))
	if not _valid_hash(sha) or FileAccess.get_sha256(source) != sha: return false
	var target := packs_directory.path_join(sha + ".pck")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(packs_directory)) != OK: return false
	var target_abs := ProjectSettings.globalize_path(target)
	if source != target_abs:
		# Content-addressed target is immutable once valid. Copy to a temp file
		# and rename so an interrupted copy cannot corrupt an active pack.
		if not FileAccess.file_exists(target_abs) or FileAccess.get_sha256(target_abs) != sha:
			var temporary := target_abs + ".tmp"
			if DirAccess.copy_absolute(source, temporary) != OK: return false
			if FileAccess.get_sha256(temporary) != sha:
				DirAccess.remove_absolute(temporary)
				return false
			if FileAccess.file_exists(target_abs): DirAccess.remove_absolute(target_abs)
			if DirAccess.rename_absolute(temporary, target_abs) != OK:
				DirAccess.remove_absolute(temporary)
				return false
	var entry := patch.duplicate(true)
	entry["file"] = sha + ".pck"
	if not valid_pack(entry): return false
	_state = _read_state()
	_state["schema"] = 1
	_state["base_id"] = base_id
	_state["pending"] = entry
	return _save_state()

func pending_patch() -> Dictionary:
	if not enabled: return {}
	var value = _read_state().get("pending", {})
	return value if value is Dictionary and valid_pack(value) else {}

func can_rollback() -> bool:
	var active = _state.get("active", {})
	return enabled and active is Dictionary and not active.is_empty()

func prepare_rollback() -> bool:
	if not can_rollback(): return false
	_state["active"] = _state.get("previous", {})
	_state["previous"] = {}
	_state["pending"] = {}
	_state["trial"] = false
	return _save_state()

func _ready() -> void:
	if _trial:
		get_tree().create_timer(20.0).timeout.connect(_watchdog)

func confirm_boot() -> void:
	if not _trial or _confirmed: return
	# The menu calls this only after its UI is built. Also parse critical gameplay code.
	for path in ["res://scripts/core/RoundState.gd", "res://scripts/core/ScoringEngine.gd", "res://scripts/ui/GameTable.gd", "res://scripts/ui/Lobby.gd"]:
		var script = load(path)
		if not script is Script or not script.can_instantiate(): return
	for autoload_name in ["GameConfig", "AudioManager", "Network", "UpdateManager"]:
		var node := get_node_or_null("/root/" + autoload_name)
		if node == null or node.get_script() == null: return
	_state["trial"] = false
	if _save_state():
		_confirmed = true
		_trial = false
		boot_message = "小版本 %s 已生效" % effective_version
		_cleanup_packs()

func _cleanup_packs() -> void:
	var keep: Array[String] = []
	for key in ["active", "previous", "pending"]:
		var entry = _state.get(key, {})
		if entry is Dictionary: keep.append(str(entry.get("file", "")))
	for name_value in DirAccess.get_files_at(packs_directory):
		if name_value.ends_with(".pck") and not name_value in keep:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(packs_directory.path_join(name_value)))

func _watchdog() -> void:
	if not _trial or _confirmed: return
	# Persistent trial flag rolls back on the next launch, including after a crash.
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()
