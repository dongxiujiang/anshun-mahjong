extends Node
## GitHub Releases two-tier updates: compatible PCK patches or a full EXE/APK.
signal state_changed
signal check_finished

const DOWNLOAD_DIR := "user://updates"
const MAX_PACKAGE_BYTES := 1024 * 1024 * 1024
var download_directory := DOWNLOAD_DIR
var state := "idle"
var message := "点击检查是否有新版本"
var latest: Dictionary = {}
var downloaded_path := ""
var downloaded_bytes := 0
var total_bytes := 0
var repository := ""
var manifest_url := ""
var auto_check := true
var _metadata: HTTPRequest
var _download: HTTPRequest
var _check_url := ""
var _partial_path := ""
var _automatic_checked := false
var _progress_timer := 0.0
var _release_context: Dictionary = {}
var _manifest_digest := ""

func _ready() -> void:
	repository = str(ProjectSettings.get_setting("updates/github_repository", ""))
	manifest_url = str(ProjectSettings.get_setting("updates/manifest_url", ""))
	auto_check = bool(ProjectSettings.get_setting("updates/auto_check", true))
	_metadata = HTTPRequest.new()
	_metadata.timeout = 15.0
	_metadata.body_size_limit = 512 * 1024
	_metadata.max_redirects = 5
	add_child(_metadata)
	_metadata.request_completed.connect(_metadata_done)
	_download = HTTPRequest.new()
	_download.timeout = 600.0
	_download.body_size_limit = MAX_PACKAGE_BYTES
	_download.max_redirects = 5
	_download.use_threads = true
	add_child(_download)
	_download.request_completed.connect(_download_done)
	var boot := get_node("/root/PatchBoot")
	if boot.boot_message != "": message = boot.boot_message
	var pending: Dictionary = boot.pending_patch()
	if not pending.is_empty():
		latest = pending.duplicate(true)
		latest["kind"] = "patch"
		latest["notes"] = str(pending.get("notes", ""))
		downloaded_path = ProjectSettings.globalize_path(boot._pack_path(pending))
		_set_state("ready", "小版本 %s 已下载，重启后生效" % pending.version)

func current_version() -> String:
	var boot := get_node_or_null("/root/PatchBoot")
	return str(boot.effective_version) if boot != null else str(ProjectSettings.get_setting("application/config/version", "1.2.0"))

func maybe_check() -> void:
	if auto_check and state != "ready" and not _automatic_checked and DisplayServer.get_name() != "headless":
		_automatic_checked = true
		check_updates()

static func _version_parts(value: String) -> PackedInt32Array:
	var normalized := value.strip_edges().trim_prefix("v")
	var pieces := normalized.split(".")
	if pieces.size() < 2 or pieces.size() > 3: return PackedInt32Array()
	var out := PackedInt32Array()
	for piece in pieces:
		if piece == "": return PackedInt32Array()
		for character in piece.to_utf8_buffer():
			if character < 48 or character > 57: return PackedInt32Array()
		if piece.length() > 8: return PackedInt32Array()
		out.append(piece.to_int())
	while out.size() < 3: out.append(0)
	return out

static func is_newer(candidate: String, installed: String) -> bool:
	var a := _version_parts(candidate)
	var b := _version_parts(installed)
	if a.is_empty() or b.is_empty(): return false
	for index in 3:
		if a[index] != b[index]: return a[index] > b[index]
	return false

static func safe_url(value: String, allow_local: bool = false) -> bool:
	if value.contains("\n") or value.contains("\r") or value.contains(" "): return false
	if value.begins_with("https://"):
		var authority := value.substr(8).split("/")[0]
		return authority != "" and not authority.contains("@")
	# HTTP is limited to loopback for integration tests / local preview.
	if allow_local and value.begins_with("http://"):
		var authority := value.substr(7).split("/")[0].split(":")[0]
		return authority in ["127.0.0.1", "localhost"]
	return false

static func valid_sha256(value: String) -> bool:
	if value.length() != 64: return false
	for character in value.to_lower().to_utf8_buffer():
		if not (character >= 48 and character <= 57 or character >= 97 and character <= 102): return false
	return true

func platform_key() -> String:
	return "android" if OS.get_name() == "Android" else "windows"

func check_updates() -> void:
	if state in ["checking", "downloading"]: return
	latest.clear()
	_release_context.clear()
	_manifest_digest = ""
	var local_allowed := not OS.has_feature("template")
	if manifest_url != "":
		_check_url = manifest_url
	elif repository != "":
		var pieces := repository.split("/")
		if pieces.size() != 2 or repository.contains(" ") or repository.contains("..") or repository.contains("?") or repository.contains("#"):
			_set_state("error", "更新仓库配置无效")
			return
		_check_url = "https://api.github.com/repos/%s/releases/latest" % repository
	else:
		_set_state("error", "尚未配置更新来源")
		return
	if not safe_url(_check_url, local_allowed):
		_set_state("error", "更新来源地址无效，请使用 HTTPS 下载地址")
		return
	_set_state("checking", "正在检查新版本…")
	var headers := PackedStringArray(["User-Agent: Anshun-Mahjong/" + current_version(), "Accept: application/json"])
	if _metadata.request(_check_url, headers) != OK:
		_set_state("error", "无法开始检查，请稍后重试")

func _set_state(value: String, text_value: String) -> void:
	state = value
	message = text_value
	state_changed.emit()

func _metadata_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state != "checking": return
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_state("error", "检查更新失败，请检查网络后重试")
	elif code == 404:
		_set_state("no_release", "暂未发布正式更新，当前版本 %s" % current_version())
	elif code == 403 or code == 429:
		_set_state("error", "更新来源暂时限制访问，请稍后重试")
	elif code < 200 or code >= 300:
		_set_state("error", "更新来源暂时不可用（%d）" % code)
	else:
		var parser := JSON.new()
		var valid := parser.parse(body.get_string_from_utf8()) == OK
		var data = parser.data
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		if not body.is_empty(): hasher.update(body)
		var body_hash := hasher.finish().hex_encode()
		if _manifest_digest != "" and body_hash != _manifest_digest:
			_set_state("error", "更新清单校验失败，请重试")
		elif not valid or not data is Dictionary:
			_set_state("error", "更新信息格式有误，请稍后重试")
		else:
			if not _release_context.is_empty():
				var expected := str(_release_context.tag_name).trim_prefix("v")
				if str(data.get("version", "")) != expected or int(data.get("schema", 0)) != 2:
					_set_state("error", "发布标签与更新清单不一致")
				else:
					if str(data.get("notes", "")) == "": data["notes"] = str(_release_context.get("body", ""))
					data["release_url"] = str(_release_context.get("html_url", ""))
					apply_release(data, platform_key(), not OS.has_feature("template"))
				_release_context.clear()
				_manifest_digest = ""
			else:
				apply_release(data, platform_key(), not OS.has_feature("template"))
	if state != "checking": check_finished.emit()

func _fetch_release_manifest(data: Dictionary, allow_local: bool) -> bool:
	var assets = data.get("assets", [])
	if not assets is Array: return false
	var name_value := str(ProjectSettings.get_setting("updates/manifest_asset", "update-manifest.json"))
	for asset in assets:
		if not asset is Dictionary or str(asset.get("name", "")) != name_value: continue
		var url := str(asset.get("browser_download_url", ""))
		if not safe_url(url, allow_local):
			_set_state("error", "更新清单地址无效")
			return true
		var digest = asset.get("digest", "")
		_manifest_digest = str(digest).trim_prefix("sha256:") if digest is String else ""
		if _manifest_digest != "" and not valid_sha256(_manifest_digest):
			_set_state("error", "更新清单校验信息无效")
			return true
		_release_context = data.duplicate(true)
		_set_state("checking", "正在读取新版本更新内容…")
		if _metadata.request(url, PackedStringArray(["User-Agent: Anshun-Mahjong-Updater", "Accept: application/json"])) != OK:
			_release_context.clear()
			_set_state("error", "无法读取更新清单，请重试")
		return true
	return false

func _patch_compatible(patch: Dictionary, version: String, platform: String) -> bool:
	var boot := get_node_or_null("/root/PatchBoot")
	if boot == null: return false
	var target := _version_parts(version)
	var base := _version_parts(str(boot.base_version))
	return target.size() == 3 and base.size() == 3 and target[0] == base[0] and str(patch.get("base_id", "")) == str(boot.base_id) and str(patch.get("base_version", "")) == str(boot.base_version) and str(patch.get("engine", "")) == boot.engine_version() and str(patch.get("platform", platform)) == platform

func apply_release(data: Dictionary, platform: String, allow_local: bool = false) -> void:
	latest.clear()
	var github := data.has("tag_name")
	if github and (bool(data.get("draft", false)) or bool(data.get("prerelease", false))):
		_set_state("no_release", "暂未发布正式更新")
		return
	var version := str(data.get("tag_name", "") if github else data.get("version", "")).trim_prefix("v")
	if _version_parts(version).is_empty():
		_set_state("error", "更新版本号无效")
		return
	if not is_newer(version, current_version()):
		_set_state("current", "已是最新版本 %s" % current_version())
		return
	if github and _fetch_release_manifest(data, allow_local): return
	var package: Dictionary = {}
	var kind := "full"
	if github:
		var expected := str(ProjectSettings.get_setting("updates/%s_asset" % platform, ""))
		var assets = data.get("assets", [])
		if not assets is Array:
			_set_state("error", "更新下载列表格式有误")
			return
		for asset in assets:
			if not asset is Dictionary: continue
			if str(asset.get("name", "")) == expected:
				var asset_digest = asset.get("digest", "")
				var digest: String = asset_digest.trim_prefix("sha256:") if asset_digest is String else ""
				package = {"url": asset.get("browser_download_url", ""), "sha256": digest, "size": asset.get("size", 0)}
				break
	else:
		var platforms = data.get("packages", data.get("platforms", {}))
		if platforms is Dictionary and platforms.get(platform, {}) is Dictionary:
			package = platforms.get(platform, {})
		if int(data.get("schema", 0)) == 2:
			var patches = data.get("patches", {})
			if patches is Dictionary and patches.get(platform, {}) is Dictionary:
				var patch: Dictionary = patches.get(platform, {})
				if not patch.is_empty() and _patch_compatible(patch, version, platform):
					package = patch
					kind = "patch"
	var page := str(data.get("html_url", "") if github else data.get("release_url", ""))
	if not github and int(data.get("schema", 0)) == 2 and kind == "full" and package.is_empty():
		page = str(data.get("installation_url", page))
	var url := str(package.get("url", ""))
	if not safe_url(page, allow_local): page = ""
	if url != "" and not safe_url(url, allow_local):
		_set_state("error", "更新下载地址无效")
		return
	if url == "" and page == "":
		_set_state("error", "新版尚未提供此平台的下载文件")
		return
	var sha := str(package.get("sha256", "")).to_lower()
	if sha != "" and not valid_sha256(sha):
		_set_state("error", "更新文件校验信息无效")
		return
	var bytes := int(package.get("size", 0))
	if bytes < 0 or bytes > MAX_PACKAGE_BYTES:
		_set_state("error", "更新包大小无效")
		return
	if kind == "patch" and (url == "" or not valid_sha256(sha) or bytes <= 0):
		_set_state("error", "小版本补丁缺少下载或校验信息")
		return
	latest = {"kind": kind, "version": version, "notes": str(data.get("body", "") if github else data.get("notes", "")).left(16000), "page": page, "url": url, "sha256": sha, "size": bytes, "platform": platform}
	if kind == "patch":
		for key in ["base_id", "base_version", "engine"]: latest[key] = str(package[key])
	_set_state("available", "发现小版本 %s，无需重新安装" % version if kind == "patch" else "发现大版本 %s，需要更新完整应用" % version)

func can_download() -> bool:
	return not latest.is_empty() and (latest.get("kind", "full") == "patch" or latest.platform == "windows") and latest.url != "" and valid_sha256(str(latest.sha256))

func can_install() -> bool:
	if latest.get("kind", "full") == "patch":
		return state == "ready" and get_node("/root/PatchBoot").enabled
	return state == "ready" and OS.get_name() == "Windows" and OS.has_feature("template") and not OS.has_feature("editor")

func open_download_page() -> Error:
	if latest.is_empty(): return ERR_UNAVAILABLE
	var url := str(latest.url if latest.platform == "android" and latest.url != "" else latest.page)
	if url == "": url = str(latest.url)
	if not safe_url(url, not OS.has_feature("template")): return ERR_INVALID_PARAMETER
	return OS.shell_open(url)

func download_update() -> void:
	if state == "downloading" or not can_download(): return
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(download_directory))
	if err != OK:
		_set_state("error", "无法创建更新文件夹，请检查磁盘空间")
		return
	downloaded_path = ""
	var extension := "pck" if latest.get("kind", "full") == "patch" else "exe"
	_partial_path = download_directory + "/mahjong-%s.%s.part" % [latest.version, extension]
	_download.download_file = _partial_path
	total_bytes = int(latest.size)
	downloaded_bytes = 0
	_set_state("downloading", "正在下载小版本，完成后重启生效" if extension == "pck" else "正在下载新版应用，完成后可重启更新")
	if _download.request(str(latest.url), PackedStringArray(["User-Agent: Anshun-Mahjong-Updater"])) != OK:
		_cleanup_partial()
		_set_state("error", "无法开始下载，请重试")

func _process(delta: float) -> void:
	if state != "downloading": return
	_progress_timer -= delta
	if _progress_timer > 0.0: return
	_progress_timer = 0.2
	downloaded_bytes = _download.get_downloaded_bytes()
	var size_value := _download.get_body_size()
	if size_value > 0: total_bytes = size_value
	state_changed.emit()

func cancel_download() -> void:
	if state != "downloading": return
	_download.cancel_request()
	_cleanup_partial()
	_set_state("available", "下载已取消，可以稍后继续")

func _cleanup_partial() -> void:
	if _partial_path != "" and FileAccess.file_exists(_partial_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_partial_path))

func _download_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if state != "downloading": return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_cleanup_partial()
		_set_state("error", "下载未完成，请检查网络和磁盘空间后重试")
		return
	var file := FileAccess.open(_partial_path, FileAccess.READ)
	var length := file.get_length() if file != null else 0
	var patch: bool = latest.get("kind", "full") == "patch"
	var magic := PackedByteArray([71, 68, 80, 67]) if patch else PackedByteArray([77, 90])
	var valid_package := file != null and file.get_buffer(magic.size()) == magic
	if file != null: file.close()
	if length == 0 or int(latest.size) > 0 and length != int(latest.size):
		_cleanup_partial()
		_set_state("error", "更新包不完整，请重新下载")
		return
	if not valid_package:
		_cleanup_partial()
		_set_state("error", "下载文件不是有效的小版本补丁，请重试" if patch else "下载文件不是有效的 Windows 程序，请重试")
		return
	if FileAccess.get_sha256(_partial_path).to_lower() != str(latest.sha256):
		_cleanup_partial()
		_set_state("error", "更新文件校验失败，已删除下载文件，请重试")
		return
	var completed := download_directory + "/mahjong-%s.%s" % [latest.version, "pck" if patch else "exe"]
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(_partial_path), ProjectSettings.globalize_path(completed)) != OK:
		_cleanup_partial()
		_set_state("error", "无法保存更新文件，请重试")
		return
	downloaded_path = ProjectSettings.globalize_path(completed)
	if patch and get_node("/root/PatchBoot").enabled:
		if not get_node("/root/PatchBoot").stage_patch(downloaded_path, latest):
			_set_state("error", "无法保存小版本补丁，原版本继续可用")
			return
	downloaded_bytes = length
	total_bytes = length
	_set_state("ready", "小版本已下载并通过校验，重启生效，无需安装" if patch else "新版已下载并通过校验，重启后更新")

static func _ps_literal(value: String) -> String:
	return "'" + value.replace("'", "''") + "'"

func prepare_windows_helper(target: String, source: String, process_id: int) -> String:
	if not target.is_absolute_path() or not source.is_absolute_path() or target.get_extension().to_lower() != "exe" or process_id < 1 or not valid_sha256(str(latest.get("sha256", ""))): return ""
	var template := FileAccess.get_file_as_string("res://res/update/windows_update.ps1")
	if template == "": return ""
	var substitutions := {"@@TARGET@@": _ps_literal(target), "@@SOURCE@@": _ps_literal(source), "@@SHA256@@": _ps_literal(str(latest.sha256)), "@@PID@@": str(process_id), "@@VERSION@@": _ps_literal(str(latest.version))}
	for token in substitutions: template = template.replace(token, substitutions[token])
	var path := ProjectSettings.globalize_path(download_directory + "/apply-update.ps1")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_buffer(PackedByteArray([239, 187, 191]))
	file.store_string(template)
	file.close()
	return path

func install_and_restart() -> bool:
	if not can_install():
		_set_state("ready", "工程运行模式下仅验证下载，请在安装版游戏中应用更新")
		return false
	# Never close an active room or table to apply an update.
	if get_node("/root/Network").mode != "" or get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/GameTable.tscn":
		_set_state("ready", "请先退出房间或对局，再重启更新")
		return false
	if FileAccess.get_sha256(downloaded_path) != str(latest.sha256):
		_set_state("error", "下载文件已变化，请重新检查并下载")
		return false
	if latest.get("kind", "full") == "patch":
		if not get_node("/root/PatchBoot").stage_patch(downloaded_path, latest):
			_set_state("error", "无法保存小版本补丁，原版本继续可用")
			return false
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
		get_tree().quit()
		return true
	var helper := prepare_windows_helper(OS.get_executable_path(), downloaded_path, OS.get_process_id())
	if helper == "":
		_set_state("ready", "无法启动更新，可打开下载文件夹使用新版")
		return false
	var powershell := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var process := OS.create_process(powershell, PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", helper]), false)
	if process < 0:
		_set_state("ready", "无法启动更新，可打开下载文件夹使用新版")
		return false
	get_tree().quit()
	return true

func open_download_folder() -> void:
	if downloaded_path != "": OS.shell_open(downloaded_path.get_base_dir())

func rollback_and_restart() -> bool:
	var boot := get_node("/root/PatchBoot")
	if not boot.can_rollback(): return false
	if get_node("/root/Network").mode != "" or get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/GameTable.tscn":
		message = "请先退出房间或对局，再恢复上一小版本"
		state_changed.emit()
		return false
	if not boot.prepare_rollback(): return false
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()
	return true
