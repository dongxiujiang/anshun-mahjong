extends Node
## GitHub Releases two-tier updates: compatible PCK patches or a full EXE/APK.
signal state_changed
signal check_finished

const DOWNLOAD_DIR := "user://updates"
const MAX_PACKAGE_BYTES := 1024 * 1024 * 1024
# Public release assets only. GitHub API metadata/digests stay on GitHub HTTPS.
const DEFAULT_DOWNLOAD_PROXIES := ["https://ghproxy.net/", "https://ghproxy.com/", "https://gh.llkk.cc/"]
const ROUTE_IDLE_SECONDS := 8.0
var download_proxies: Array = DEFAULT_DOWNLOAD_PROXIES.duplicate()
var use_download_proxies := true
var download_directory := DOWNLOAD_DIR
var state := "idle"
var message := "点击检查是否有新版本"
var latest: Dictionary = {}
var downloaded_path := ""
var downloaded_bytes := 0
var total_bytes := 0
var repository := ""
var manifest_url := ""
var manifest_urls: Array[String] = []
var auto_check := true
var _metadata: HTTPRequest
var _download: HTTPRequest
var _check_url := ""
var _partial_path := ""
var _automatic_checked := false
var _automatic_prompted := false
var _automatic_check_active := false
var _automatic_retry_used := false
var _automatic_retry_pending := false
var _progress_timer := 0.0
var _release_context: Dictionary = {}
var _manifest_digest := ""
var _metadata_routes: Array[String] = []
var _metadata_route := 0
var _download_routes: Array[String] = []
var _download_route := 0
var _chunk_path := ""
var _request_offset := 0
var _range_chunk_bytes := 4 * 1024 * 1024
var _download_generation := 0
var _idle_seconds := 0.0
var _last_progress := 0
var _link_probe: HTTPRequest
var _link_routes: Array[String] = []
var _link_route := 0
var _link_range_probe := false
var _last_browser_route := ""

func _ready() -> void:
	repository = str(ProjectSettings.get_setting("updates/github_repository", ""))
	manifest_url = str(ProjectSettings.get_setting("updates/manifest_url", ""))
	manifest_urls.clear()
	var configured_manifests = ProjectSettings.get_setting("updates/manifest_urls", [])
	if configured_manifests is Array:
		for value in configured_manifests:
			if value is String and str(value).strip_edges() != "":
				manifest_urls.append(str(value).strip_edges())
	auto_check = bool(ProjectSettings.get_setting("updates/auto_check", true))
	use_download_proxies = bool(ProjectSettings.get_setting("updates/use_download_proxies", true))
	download_proxies = Array(ProjectSettings.get_setting("updates/download_proxies", DEFAULT_DOWNLOAD_PROXIES))
	_metadata = HTTPRequest.new()
	_metadata.timeout = 15.0
	_metadata.body_size_limit = 512 * 1024
	_metadata.max_redirects = 5
	_metadata.use_threads = true
	add_child(_metadata)
	_metadata.request_completed.connect(_metadata_done)
	_download = HTTPRequest.new()
	_download.timeout = 600.0
	_download.body_size_limit = MAX_PACKAGE_BYTES
	_download.max_redirects = 5
	_download.use_threads = true
	add_child(_download)
	_download.request_completed.connect(_download_done)
	_link_probe = HTTPRequest.new()
	_link_probe.timeout = ROUTE_IDLE_SECONDS
	_link_probe.body_size_limit = 64 * 1024
	_link_probe.max_redirects = 5
	_link_probe.use_threads = true
	add_child(_link_probe)
	_link_probe.request_completed.connect(_link_done)
	var boot := get_node("/root/PatchBoot")
	if boot.boot_message != "": message = boot.boot_message
	var pending: Dictionary = boot.pending_patch()
	if not pending.is_empty():
		latest = pending.duplicate(true)
		latest["kind"] = "patch"
		latest["notes"] = str(pending.get("notes", ""))
		downloaded_path = ProjectSettings.globalize_path(boot._pack_path(pending))
		_set_state("ready", "小版本 %s 已下载，重启后生效" % pending.version)
	# 每次启动只检查一次，切换大厅/牌桌不会重复请求。
	call_deferred("maybe_check")

func current_version() -> String:
	var boot := get_node_or_null("/root/PatchBoot")
	return str(boot.effective_version) if boot != null else str(ProjectSettings.get_setting("application/config/version", "1.0.0"))

func maybe_check() -> void:
	if auto_check and not _automatic_checked and DisplayServer.get_name() != "headless":
		_automatic_checked = true
		if state not in ["checking", "downloading", "ready"]:
			check_updates()
			_automatic_check_active = state == "checking"

func _retry_startup_check() -> void:
	if not _automatic_retry_pending: return
	_automatic_retry_pending = false
	if not auto_check or state != "error": return
	check_updates()
	_automatic_check_active = state == "checking"

func claim_startup_prompt() -> bool:
	if not auto_check or _automatic_prompted or state not in ["available", "ready"]: return false
	_automatic_prompted = true
	return true

static func _normalized_version(value: String) -> String:
	var normalized := value.strip_edges()
	if normalized.begins_with("v") or normalized.begins_with("V"):
		normalized = normalized.substr(1)
	return normalized

static func _version_parts(value: String) -> PackedInt32Array:
	var normalized := _normalized_version(value)
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

static func verify_manifest_payload(payload_b64: String, signature_b64: String, public_key_b64: String) -> Dictionary:
	# RSA-3072 PKCS#1 v1.5 over the exact UTF-8 signed payload. The private
	# key stays offline; only this public key is embedded in the binary.
	if payload_b64 == "" or signature_b64 == "" or public_key_b64 == "":
		return {}
	if payload_b64.length() % 4 != 0 or signature_b64.length() % 4 != 0 or public_key_b64.length() % 4 != 0:
		return {}
	var payload := Marshalls.base64_to_raw(payload_b64)
	var signature := Marshalls.base64_to_raw(signature_b64)
	var public_pem := Marshalls.base64_to_raw(public_key_b64).get_string_from_utf8()
	if payload.is_empty() or signature.is_empty() or public_pem == "":
		return {}
	var key := CryptoKey.new()
	if key.load_from_string(public_pem, true) != OK:
		return {}
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(payload)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, hasher.finish(), signature, key):
		return {}
	var parsed = JSON.parse_string(payload.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}

static func is_github_asset(url: String) -> bool:
	# Do not forward API calls, credentials, signed query strings, or URLs from
	# arbitrary origins to third-party services. Never recursively wrap a proxy.
	if not safe_url(url) or not url.begins_with("https://github.com/") or url.contains("?") or url.contains("#") or url.contains("\\"): return false
	var path := url.trim_prefix("https://github.com/").split("/")
	return path.size() == 6 and path[0] != "" and path[1] != "" and path[2] == "releases" and ((path[3] == "download" and path[4] != "") or (path[3] == "latest" and path[4] == "download")) and path[5] != ""

func _routes_for(url: String) -> Array[String]:
	var routes: Array[String] = []
	if use_download_proxies and is_github_asset(url):
		for raw in download_proxies:
			var prefix := str(raw).strip_edges().trim_suffix("/") + "/"
			if not safe_url(prefix) or prefix.contains("?") or prefix.contains("#") or prefix.contains("\\"): continue
			# A prefix must be an HTTPS origin, never another wrapped target URL.
			if prefix.trim_prefix("https://").split("/").size() != 2: continue
			var candidate := prefix + url
			if candidate not in routes: routes.append(candidate)
			if routes.size() >= 6: break
	routes.append(url)
	return routes

static func _header(headers: PackedStringArray, key: String) -> String:
	for line in headers:
		var colon := line.find(":")
		if colon > 0 and line.left(colon).to_lower() == key.to_lower(): return line.substr(colon + 1).strip_edges()
	return ""

func platform_key() -> String:
	return "android" if OS.get_name() == "Android" else "windows"

func check_updates() -> void:
	if state in ["checking", "downloading", "opening"]: return
	_automatic_retry_pending = false
	_automatic_check_active = false
	latest.clear()
	_release_context.clear()
	_manifest_digest = ""
	_metadata_routes.clear()
	var local_allowed := not OS.has_feature("template")
	var routes: Array[String] = []
	if manifest_url != "":
		routes = [manifest_url]
	elif not manifest_urls.is_empty():
		routes = manifest_urls.duplicate()
	elif repository != "":
		var pieces := repository.split("/")
		if pieces.size() != 2 or repository.contains(" ") or repository.contains("..") or repository.contains("?") or repository.contains("#"):
			_set_state("error", "更新仓库配置无效")
			return
		routes = ["https://api.github.com/repos/%s/releases/latest" % repository]
	else:
		_set_state("error", "尚未配置更新来源")
		return
	for route in routes:
		if not safe_url(route, local_allowed):
			_set_state("error", "更新来源地址无效，请使用 HTTPS 下载地址")
			return
	_check_url = routes[0]
	_set_state("checking", "正在检查新版本…")
	_start_metadata(routes)

func _start_metadata(routes: Array[String]) -> void:
	_metadata_routes = routes
	_metadata_route = -1
	_request_next_metadata()

func _request_next_metadata() -> bool:
	_metadata_route += 1
	while _metadata_route < _metadata_routes.size():
		_metadata.timeout = ROUTE_IDLE_SECONDS
		var headers := PackedStringArray(["User-Agent: Anshun-Mahjong/" + current_version(), "Accept: application/json"])
		if _metadata.request(_metadata_routes[_metadata_route], headers) == OK: return true
		_metadata_route += 1
	_set_state("error", "无法读取更新信息，请稍后重试")
	return false

func _set_state(value: String, text_value: String) -> void:
	state = value
	message = text_value
	state_changed.emit()

func _metadata_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state != "checking": return
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_state("error", "检查更新失败，请检查网络后重试")
	elif code == 404:
		if _release_context.is_empty():
			_set_state("no_release", "暂未发布正式更新，当前版本 %s" % current_version())
		else:
			_set_state("error", "更新清单暂时不可用，请稍后重试")
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
			if _release_context.is_empty():
				# The self-hosted manifest is not pinned by a GitHub API digest.
				# Production templates must carry the offline RSA signature;
				# editor/headless fixtures may use an unsigned local manifest.
				if not OS.has_feature("template"):
					apply_release(data, platform_key(), true)
				else:
					var public_key := str(ProjectSettings.get_setting("updates/manifest_public_key", ""))
					var signed := verify_manifest_payload(str(data.get("signed_payload", "")),
						str(data.get("signature", "")), public_key)
					if signed.is_empty() or int(signed.get("schema", 0)) != 2:
						_set_state("error", "更新清单签名无效，请稍后重试")
					else:
						apply_release(signed, platform_key(), false)
			else:
				var expected := _normalized_version(str(_release_context.tag_name))
				if _normalized_version(str(data.get("version", ""))) != expected or int(data.get("schema", 0)) != 2:
					_set_state("error", "发布标签与更新清单不一致")
				else:
					if str(data.get("notes", "")) == "": data["notes"] = str(_release_context.get("body", ""))
					data["release_url"] = str(_release_context.get("html_url", ""))
					apply_release(data, platform_key(), not OS.has_feature("template"))
	if state in ["error", "no_release"] and _metadata_route + 1 < _metadata_routes.size():
		_set_state("checking", "当前线路不可用，正在切换下载线路…")
		if _request_next_metadata(): return
	if state != "checking":
		_release_context.clear()
		_manifest_digest = ""
		# 启动时网络尚未就绪或服务临时失败，稍后自动重试一次。
		var transient_failure := result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429
		if state == "error" and transient_failure and _automatic_check_active and not _automatic_retry_used:
			_automatic_retry_used = true
			_automatic_retry_pending = true
			_set_state("error", "自动检查暂未成功，2 秒后重试…")
			get_tree().create_timer(2.0).timeout.connect(_retry_startup_check)
		_automatic_check_active = false
		check_finished.emit()

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
		# Only proxy a manifest pinned by a digest obtained from the official API.
		_start_metadata(_routes_for(url) if valid_sha256(_manifest_digest) else [url])
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
	var version := _normalized_version(str(data.get("tag_name", "") if github else data.get("version", "")))
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
	if latest.is_empty() or state in ["checking", "downloading", "opening"]: return ERR_UNAVAILABLE
	var url := str(latest.url if latest.platform == "android" and latest.url != "" else latest.page)
	if url == "": url = str(latest.url)
	if not safe_url(url, not OS.has_feature("template")): return ERR_INVALID_PARAMETER
	if not is_github_asset(url): return _open_browser_url(url)
	_link_routes = _routes_for(url)
	if _last_browser_route in _link_routes:
		# Browser downloads cannot report failures back to the game. A second
		# tap starts with another route instead of reopening the same bad link.
		var start := (_link_routes.find(_last_browser_route) + 1) % _link_routes.size()
		_link_routes = _link_routes.slice(start) + _link_routes.slice(0, start)
	_link_route = -1
	_set_state("opening", "正在选择可用下载线路…")
	_next_link()
	return OK

func _open_browser_url(url: String) -> Error:
	return OS.shell_open(url)

func _next_link() -> void:
	_link_route += 1
	_link_range_probe = false
	while _link_route < _link_routes.size():
		if _link_probe.request(_link_routes[_link_route], PackedStringArray(["User-Agent: Anshun-Mahjong-Updater", "Accept-Encoding: identity"]), HTTPClient.METHOD_HEAD) == OK: return
		_link_route += 1
	_set_state("available", "暂时没有可用下载线路，请稍后重试")

func _link_done(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if state != "opening": return
	# Some proxies reject HEAD. A bounded Range probe checks the first bytes.
	if code in [405, 501] and not _link_range_probe:
		_link_range_probe = true
		if _link_probe.request(_link_routes[_link_route], PackedStringArray(["User-Agent: Anshun-Mahjong-Updater", "Accept-Encoding: identity", "Range: bytes=0-3"])) == OK: return
	var content_type := _header(headers, "Content-Type").to_lower()
	var length := _header(headers, "Content-Length").to_int()
	var expected := int(latest.get("size", 0))
	var valid := result == HTTPRequest.RESULT_SUCCESS and code in [200, 206] and not content_type.contains("text/") and not content_type.contains("json")
	if _link_range_probe:
		var magic := PackedByteArray([80, 75]) if latest.get("platform", "") == "android" else PackedByteArray([77, 90])
		valid = valid and body.size() >= magic.size() and body.slice(0, magic.size()) == magic
		if code == 206: valid = valid and _valid_range(headers, 0, expected, body.size())
	else:
		valid = valid and length > 0 and (expected <= 0 or length == expected)
	if valid and _open_browser_url(_link_routes[_link_route]) == OK:
		_last_browser_route = _link_routes[_link_route]
		_set_state("available", "已打开下载；未成功可再次点击下载按钮切换线路")
	else:
		_next_link()

func download_update() -> void:
	if state in ["checking", "downloading", "opening"] or not can_download(): return
	_download_generation += 1
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(download_directory))
	if err != OK:
		_set_state("error", "无法创建更新文件夹，请检查磁盘空间")
		return
	downloaded_path = ""
	var extension := "pck" if latest.get("kind", "full") == "patch" else "exe"
	_partial_path = download_directory + "/mahjong-%s.%s.part" % [latest.version, extension]
	_chunk_path = _partial_path + ".chunk"
	_cleanup_partial()
	_download_routes = _routes_for(str(latest.url))
	_download_route = -1
	total_bytes = int(latest.size)
	downloaded_bytes = 0
	_set_state("downloading", "正在下载小版本，完成后重启生效" if extension == "pck" else "正在下载新版应用，完成后可重启更新")
	_next_download("无法开始下载，请重试")

static func _file_length(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	return file.get_length() if file != null else 0

func _next_download(failure: String) -> void:
	_download_route += 1
	while _download_route < _download_routes.size():
		if _download_route > 0: _set_state("downloading", "正在切换下载线路，继续下载…")
		if _request_download_chunk() == OK: return
		_download_route += 1
	_cleanup_partial()
	_set_state("error", failure)

func _request_download_chunk() -> Error:
	if FileAccess.file_exists(_chunk_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(_chunk_path))
	_request_offset = _file_length(_partial_path)
	var expected := int(latest.size)
	if expected > 0 and _request_offset >= expected:
		_cleanup_partial()
		_request_offset = 0
	_download.download_file = _chunk_path
	_idle_seconds = 0.0
	_last_progress = 0
	downloaded_bytes = _request_offset
	var headers := PackedStringArray(["User-Agent: Anshun-Mahjong-Updater", "Accept-Encoding: identity"])
	if expected > 0:
		var last := mini(expected - 1, _request_offset + maxi(256, _range_chunk_bytes) - 1)
		headers.append("Range: bytes=%d-%d" % [_request_offset, last])
	# Commit only completed HTTP ranges. HTTPRequest can omit response headers
	# on disconnect, so an interrupted chunk is retried from its last checkpoint.
	return _download.request(_download_routes[_download_route], headers)

func _continue_download(generation: int) -> void:
	if state == "downloading" and generation == _download_generation and _request_download_chunk() != OK:
		_next_download("无法继续下载，请稍后重试")

func _process(delta: float) -> void:
	if state != "downloading": return
	var received := _download.get_downloaded_bytes()
	_idle_seconds = 0.0 if received > _last_progress else _idle_seconds + delta
	_last_progress = received
	if _idle_seconds >= ROUTE_IDLE_SECONDS:
		_download.cancel_request()
		# No completion headers on cancellation: do not trust/merge this chunk.
		_next_download("下载线路长时间没有响应，请稍后重试")
		return
	_progress_timer -= delta
	if _progress_timer > 0.0: return
	_progress_timer = 0.2
	downloaded_bytes = _request_offset + maxi(0, received)
	var size_value := _download.get_body_size()
	if int(latest.size) <= 0 and size_value > 0: total_bytes = _request_offset + size_value
	if total_bytes > 0: downloaded_bytes = mini(downloaded_bytes, total_bytes)
	state_changed.emit()

func cancel_download() -> void:
	if state == "opening":
		_link_probe.cancel_request()
		_link_routes.clear()
		_set_state("available", "已取消选择下载线路")
		return
	if state != "downloading": return
	_download_generation += 1
	_download.cancel_request()
	_cleanup_partial()
	_set_state("available", "下载已取消，可以稍后继续")

func _cleanup_partial() -> void:
	if _partial_path != "" and FileAccess.file_exists(_partial_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_partial_path))
	if _chunk_path != "" and FileAccess.file_exists(_chunk_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_chunk_path))

static func _valid_range(headers: PackedStringArray, offset: int, expected: int, length: int) -> bool:
	var regex := RegEx.new()
	regex.compile("^bytes ([0-9]+)-([0-9]+)/([0-9]+)$")
	var matched := regex.search(_header(headers, "Content-Range"))
	if matched == null: return false
	var first := matched.get_string(1).to_int()
	var last := matched.get_string(2).to_int()
	var total := matched.get_string(3).to_int()
	return first == offset and last >= first and total > last and total <= MAX_PACKAGE_BYTES and (expected <= 0 or total == expected) and length <= last - first + 1

func _merge_chunk(code: int, headers: PackedStringArray) -> bool:
	var length := _file_length(_chunk_path)
	var expected := int(latest.size)
	if length <= 0 or length > MAX_PACKAGE_BYTES: return false
	var encoding := _header(headers, "Content-Encoding").to_lower()
	if encoding not in ["", "identity"]: return false
	var content_type := _header(headers, "Content-Type").to_lower()
	if content_type.contains("text/") or content_type.contains("json"): return false
	if code == 200:
		# A server can ignore Range. Replace the partial file rather than append
		# a whole response to it. No proxy's Range support is assumed.
		if expected > 0 and length > expected: return false
		if FileAccess.file_exists(_partial_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(_partial_path))
		return DirAccess.rename_absolute(ProjectSettings.globalize_path(_chunk_path), ProjectSettings.globalize_path(_partial_path)) == OK
	if code != 206 or not _valid_range(headers, _request_offset, expected, length): return false
	if _file_length(_partial_path) != _request_offset: return false
	var source := FileAccess.open(_chunk_path, FileAccess.READ)
	var target := FileAccess.open(_partial_path, FileAccess.READ_WRITE if _request_offset > 0 else FileAccess.WRITE)
	if source == null or target == null: return false
	target.seek_end()
	while source.get_position() < length:
		var buffer := source.get_buffer(mini(65536, length - source.get_position()))
		if buffer.is_empty(): return false
		target.store_buffer(buffer)
		if target.get_error() != OK: return false
	target.close()
	source.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_chunk_path))
	return true

func _download_done(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	if state != "downloading": return
	var merged := _merge_chunk(code, headers)
	if not merged or result != HTTPRequest.RESULT_SUCCESS:
		# Only known-size validated response spans are kept for another route.
		if int(latest.size) <= 0: _cleanup_partial()
		_next_download("下载未完成，请检查网络和磁盘空间后重试")
		return
	var file := FileAccess.open(_partial_path, FileAccess.READ)
	var length := file.get_length() if file != null else 0
	var patch: bool = latest.get("kind", "full") == "patch"
	var magic := PackedByteArray([71, 68, 80, 67]) if patch else PackedByteArray([77, 90])
	var valid_package := file != null and file.get_buffer(magic.size()) == magic
	if file != null: file.close()
	if length == 0 or int(latest.size) > 0 and length != int(latest.size):
		if code == 206 and length > 0 and length < int(latest.size):
			call_deferred("_continue_download", _download_generation)
			return
		_next_download("更新包不完整，请重新下载")
		return
	if not valid_package:
		_cleanup_partial()
		_next_download("下载文件不是有效的小版本补丁，请重试" if patch else "下载文件不是有效的 Windows 程序，请重试")
		return
	if FileAccess.get_sha256(_partial_path).to_lower() != str(latest.sha256):
		_cleanup_partial()
		_next_download("更新文件校验失败，已删除下载文件，请重试")
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
