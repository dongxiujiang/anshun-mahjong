extends Node

signal state_changed(snapshot: Dictionary)
signal check_finished(has_update: bool, snapshot: Dictionary)

const Boot := preload("res://src/app/PatchBoot.gd")
const FALLBACK_DOWNLOAD_LIMIT := 512 * 1024 * 1024
var manifest_url_override := ""
var base_url := "https://mj.dongxiu.fun"
var download_directory := "user://updates/downloads"
var allow_insecure_loopback := not OS.has_feature("template")
var can_restart_callback: Callable
var boot_override: Node
var state := "idle"
var message := "检查是否有可用更新"
var latest: Dictionary = {}
var downloaded_bytes := 0
var total_bytes := 0
var downloaded_path := ""
var automatic := false
var _auto_checked := false
var _check_req: HTTPRequest
var _download_req: HTTPRequest
var _part_path := ""
var _progress_elapsed := 0.0
var _manifest_source_url := ""
var _download_url := ""
var _check_redirects := 0
var _download_redirects := 0

func _boot() -> Node:
	return boot_override if is_instance_valid(boot_override) else get_node_or_null("/root/PatchBoot")

func configure(directory_base_url: String, custom_manifest_url: String = "") -> void:
	base_url = directory_base_url.trim_suffix("/") if not directory_base_url.is_empty() else "https://mj.dongxiu.fun"
	manifest_url_override = custom_manifest_url

func current_version() -> String:
	var boot := _boot()
	return str(boot.effective_version) if boot != null else str(ProjectSettings.get_setting("application/config/version", "2.4.2"))

func current_version_code() -> int:
	return int(ProjectSettings.get_setting("updates/version_code", 0))

func is_patched() -> bool:
	var boot := _boot()
	return boot != null and boot.is_patched()

func can_rollback() -> bool:
	var boot := _boot()
	return boot != null and boot.can_rollback()

func resolve_manifest_url() -> String:
	if not manifest_url_override.is_empty(): return manifest_url_override
	return base_url.trim_suffix("/") + "/" + str(ProjectSettings.get_setting("updates/manifest_path", "/v1/updates/manifest")).trim_prefix("/")

static func safe_url(url: String, allow_loopback_http: bool = false) -> bool:
	for c in url:
		var code := c.unicode_at(0)
		if code <= 32 or (code >= 127 and code <= 160) or code in [5760, 8232, 8233, 8239, 8287, 12288] or (code >= 8192 and code <= 8202) or c in ["@", "\\"]: return false
	var regex := RegEx.new()
	regex.compile("^(https|http)://(\\[[0-9a-fA-F:]+\\]|[a-zA-Z0-9.-]+)(:[0-9]{1,5})?([/?#].*)?$")
	var found := regex.search(url)
	if found == null: return false
	var port := found.get_string(3)
	if not port.is_empty() and (int(port.substr(1)) < 1 or int(port.substr(1)) > 65535): return false
	return found.get_string(1) == "https" or (allow_loopback_http and found.get_string(2).to_lower() in ["127.0.0.1", "localhost", "[::1]"])

static func resolve_asset_url(raw_url: String, manifest_source_url: String) -> String:
	if raw_url.begins_with("/") and not raw_url.begins_with("//"):
		var regex := RegEx.new()
		regex.compile("^https?://[^/?#]+")
		var origin := regex.search(manifest_source_url)
		return origin.get_string() + raw_url if origin != null else ""
	return raw_url

func _normalize(entry: Dictionary, kind: String, source: String) -> Dictionary:
	if not bool(entry.get("available", true)) or not Boot.valid_sha256(str(entry.get("sha256", ""))): return {}
	var filename := str(entry.get("filename", ""))
	if not Boot.safe_filename(filename): return {}
	if kind == "patch" and not filename.to_lower().ends_with(".pck"): return {}
	if kind == "full" and filename.get_extension().to_lower() not in ["apk", "zip", "exe"]: return {}
	var size := Boot.pack_size(entry)
	if size < 0 or (kind == "patch" and size < 4): return {}
	var raw_url := str(entry.get("download_url", ""))
	if raw_url.is_empty(): raw_url = str(entry.get("direct_url", ""))
	var url := resolve_asset_url(raw_url, source)
	if not safe_url(url, allow_insecure_loopback): return {}
	var normalized := entry.duplicate(true)
	normalized.kind = kind
	normalized.url = url
	normalized.size_bytes = size
	return normalized

func select_update(manifest: Dictionary, manifest_source_url: String) -> Dictionary:
	var patch: Dictionary = {}
	var boot := _boot()
	var hotpatches = manifest.get("hotpatches", [])
	if boot != null and hotpatches is Array:
		for candidate in hotpatches:
			if not candidate is Dictionary or not boot.compatible(candidate): continue
			if Boot.compare_semver(str(candidate.get("version", "")), current_version()) != 1: continue
			var normalized := _normalize(candidate, "patch", manifest_source_url)
			if not normalized.is_empty() and (patch.is_empty() or Boot.compare_semver(str(normalized.version), str(patch.version)) == 1): patch = normalized
	var packages = manifest.get("packages", {})
	var full = packages.get(Boot.platform_key()) if packages is Dictionary else null
	if not full is Dictionary: full = manifest.get("latest_release", manifest.get("release", {}))
	var package: Dictionary = {}
	if full is Dictionary:
		var target_platform := str(full.get("platform", Boot.platform_key())).to_lower()
		var comparison := Boot.compare_semver(str(full.get("version", "")), current_version())
		var code = full.get("version_code", 0)
		var higher_code: bool = (code is int or code is float) and int(code) > current_version_code()
		if target_platform in [Boot.platform_key(), "all"] and (comparison == 1 or (comparison == 0 and higher_code)):
			package = _normalize(full, "full", manifest_source_url)
	if not patch.is_empty() and (package.is_empty() or Boot.compare_semver(str(patch.version), str(package.version)) >= 0): return patch
	return package

func maybe_auto_check() -> void:
	if DisplayServer.get_name() == "headless" or not ProjectSettings.get_setting("updates/auto_check", true) or _auto_checked: return
	_auto_checked = true
	check_updates(true)

func _request_node() -> HTTPRequest:
	var request := HTTPRequest.new()
	request.timeout = 12.0
	request.use_threads = false
	# Redirect targets must not bypass safe_url's transport policy.
	request.max_redirects = 0
	add_child(request)
	return request

func check_updates(is_automatic: bool = false) -> bool:
	if state in ["checking", "downloading"]: return false
	automatic = is_automatic
	var url := resolve_manifest_url()
	if not safe_url(url, allow_insecure_loopback):
		_fail_check("更新地址无效，请使用 HTTPS 地址")
		return false
	_manifest_source_url = url
	_check_redirects = 0
	if not is_instance_valid(_check_req):
		_check_req = _request_node()
		_check_req.body_size_limit = 512 * 1024
		_check_req.request_completed.connect(_check_completed)
	_set_state("checking", "正在检查更新…")
	if _check_req.request(url) != OK:
		_fail_check("无法连接更新服务，请稍后重试")
		return false
	return true

func _redirect_target(headers: PackedStringArray, source: String) -> String:
	for header in headers:
		if header.to_lower().begins_with("location:"):
			var target := resolve_asset_url(header.substr(9).strip_edges(), source)
			if safe_url(target, allow_insecure_loopback): return target
	return ""

func _check_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if code in [301, 302, 303, 307, 308]:
		var target := _redirect_target(headers, _manifest_source_url)
		if not target.is_empty() and _check_redirects < 5:
			_check_redirects += 1
			_manifest_source_url = target
			if _check_req.request(target) == OK: return
		_fail_check("更新服务跳转地址无效或跳转次数过多")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail_check("检查更新失败，请稍后重试")
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not json.data is Dictionary:
		_fail_check("更新清单格式无效")
		return
	var manifest: Dictionary = json.data
	latest = select_update(manifest, _manifest_source_url)
	downloaded_path = ""
	downloaded_bytes = 0
	total_bytes = int(latest.get("size_bytes", 0))
	if latest.is_empty():
		_set_state("up_to_date", "当前已是最新版本")
	else:
		var boot := _boot()
		var pending: Dictionary = boot.pending_patch() if boot != null else {}
		if latest.kind == "patch" and pending.get("sha256", "") == latest.sha256 and boot.valid_pack(pending):
			_set_state("ready", "热补丁已就绪，退出房间后重启生效")
		else:
			_set_state("available", "发现新版本 v%s" % latest.version)
	check_finished.emit(not latest.is_empty(), snapshot())

func _fail_check(text: String) -> void:
	_set_state("error", text)
	check_finished.emit(false, snapshot())

func start_download() -> bool:
	if state != "available" or latest.is_empty(): return false
	if not safe_url(str(latest.get("url", "")), allow_insecure_loopback): return false
	if latest.kind == "full" and OS.get_name() == "Android":
		if OS.shell_open(latest.url) != OK:
			_set_state("error", "无法打开浏览器，请稍后重试")
			return false
		_set_state("available", "已打开浏览器下载新版安装包，下载后点击安装即可保留数据升级")
		return true
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(download_directory)) != OK:
		_set_state("error", "无法创建下载目录")
		return false
	_part_path = download_directory.path_join(str(latest.sha256) + ".part")
	_remove_part()
	if not is_instance_valid(_download_req):
		_download_req = _request_node()
		_download_req.timeout = 300.0
		_download_req.request_completed.connect(_download_completed)
	var expected_size := int(latest.get("size_bytes", 0))
	_download_req.download_file = _part_path
	_download_req.body_size_limit = expected_size if expected_size > 0 else FALLBACK_DOWNLOAD_LIMIT
	_download_url = str(latest.url)
	_download_redirects = 0
	downloaded_bytes = 0
	total_bytes = expected_size
	_set_state("downloading", "正在下载并校验更新…")
	if _download_req.request(latest.url) != OK:
		_download_error("无法开始下载，请稍后重试")
		return false
	return true

func _process(delta: float) -> void:
	if state != "downloading" or not is_instance_valid(_download_req): return
	_progress_elapsed += delta
	if _progress_elapsed < 0.15: return
	_progress_elapsed = 0.0
	downloaded_bytes = _download_req.get_downloaded_bytes()
	if total_bytes <= 0: total_bytes = maxi(0, _download_req.get_body_size())
	state_changed.emit(snapshot())

func _download_completed(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	if state != "downloading": return
	if code in [301, 302, 303, 307, 308]:
		var target := _redirect_target(headers, _download_url)
		if not target.is_empty() and _download_redirects < 5:
			_download_redirects += 1
			_download_url = target
			_remove_part()
			if _download_req.request(target) == OK: return
		_download_error("下载跳转地址无效或跳转次数过多")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not _valid_download():
		_download_error("下载校验失败，请重新下载")
		return
	var verified_file := FileAccess.open(_part_path, FileAccess.READ)
	total_bytes = verified_file.get_length()
	verified_file.close()
	var boot := _boot()
	if latest.kind == "patch" and boot != null and boot.enabled:
		if not boot.stage_patch(_part_path, latest):
			_download_error("热补丁保存失败，请重试")
			return
		downloaded_path = boot.packs_directory.path_join(str(latest.sha256) + ".pck")
		_remove_part()
	else:
		downloaded_path = download_directory.path_join(str(latest.sha256) + ".pck" if latest.kind == "patch" else str(latest.filename))
		var target_abs := ProjectSettings.globalize_path(downloaded_path)
		var part_abs := ProjectSettings.globalize_path(_part_path)
		if FileAccess.file_exists(target_abs): DirAccess.remove_absolute(target_abs)
		if DirAccess.rename_absolute(part_abs, target_abs) != OK:
			_download_error("无法保存已校验的更新文件")
			return
	downloaded_bytes = total_bytes
	_set_state("ready", "热补丁已校验通过，重启后生效" if latest.kind == "patch" else "安装包已校验通过，可打开文件夹安装")

func _valid_download() -> bool:
	if not FileAccess.file_exists(_part_path): return false
	var file := FileAccess.open(_part_path, FileAccess.READ)
	if file == null: return false
	var length := file.get_length()
	var magic := file.get_buffer(4)
	file.close()
	var expected := int(latest.get("size_bytes", 0))
	if expected > 0 and length != expected: return false
	var extension := str(latest.filename).get_extension().to_lower()
	if latest.kind == "patch":
		if magic != Boot.GDPC_MAGIC: return false
	elif extension in ["apk", "zip"]:
		if magic.slice(0, 2) != PackedByteArray([80, 75]): return false
	elif extension == "exe":
		if magic.slice(0, 2) != PackedByteArray([77, 90]): return false
	else: return false
	return FileAccess.get_sha256(_part_path).to_lower() == str(latest.sha256)

func _remove_part() -> void:
	if not _part_path.is_empty():
		var part_abs := ProjectSettings.globalize_path(_part_path)
		if FileAccess.file_exists(part_abs): DirAccess.remove_absolute(part_abs)

func _download_error(text: String) -> void:
	_remove_part()
	_set_state("error", text)

func cancel_download() -> void:
	if state != "downloading": return
	_download_req.cancel_request()
	_remove_part()
	_set_state("available", "下载已取消，可稍后继续")

func _restart_allowed() -> bool:
	if can_restart_callback.is_valid() and not bool(can_restart_callback.call()):
		message = "请先退出当前房间或对局，再重启生效"
		state_changed.emit(snapshot())
		return false
	return true

func apply_and_restart() -> bool:
	if not _restart_allowed() or state != "ready" or latest.is_empty(): return false
	if latest.kind == "patch":
		var boot := _boot()
		if boot == null or not boot.enabled:
			message = "当前为开发运行模式，热补丁已校验通过（正式安装包内将自动重启生效）"
			state_changed.emit(snapshot())
			return false
		if not boot.valid_pack(boot.pending_patch()):
			_set_state("error", "待生效热补丁校验失败，请重新下载")
			return false
		_restart()
		return true
	return OS.shell_open(str(latest.url) if OS.get_name() == "Android" else ProjectSettings.globalize_path(downloaded_path.get_base_dir())) == OK

func rollback_and_restart() -> bool:
	if not _restart_allowed(): return false
	var boot := _boot()
	if boot == null or not boot.can_rollback() or not boot.prepare_rollback(): return false
	_restart()
	return true

func _restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()

func _set_state(value: String, text: String) -> void:
	state = value
	message = text
	state_changed.emit(snapshot())

func snapshot() -> Dictionary:
	var boot := _boot()
	return {"state": state, "message": message, "current_version": current_version(), "base_version": str(boot.base_version) if boot != null else current_version(), "is_patched": is_patched(), "can_rollback": can_rollback(), "latest": latest.duplicate(true), "downloaded_bytes": downloaded_bytes, "total_bytes": total_bytes, "downloaded_path": downloaded_path, "automatic": automatic}

func _exit_tree() -> void:
	if is_instance_valid(_check_req): _check_req.cancel_request()
	if is_instance_valid(_download_req): _download_req.cancel_request()
	_remove_part()
