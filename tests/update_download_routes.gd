extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var updater = load("res://scripts/autoload/UpdateManager.gd").new()
	updater.auto_check = false
	root.add_child(updater)
	t.expect(updater.manifest_urls == [
		"https://mj.dongxiu.fun/updates/update-manifest.json",
		"https://mj.dongxiu.fun/updates/update-manifest-fallback.json",
	], "self-hosted primary and fallback manifests are compiled in")
	var asset := "https://github.com/owner/repo/releases/download/V1.2.3/game.apk"
	var routes: Array = updater._routes_for(asset)
	t.expect(routes.size() == 4 and routes[-1] == asset, "three public proxies then original GitHub URL")
	t.expect(routes[0] == "https://ghproxy.net/" + asset, "currently reachable proxy is preferred")
	for extension in ["exe", "apk", "pck", "json"]:
		t.expect(updater._routes_for(asset.replace("apk", extension)).size() == 4, "release asset routing includes " + extension)
	t.expect(updater._routes_for("https://github.com/owner/repo/releases/latest/download/update-manifest.json").size() == 4, "latest asset download URL supported")
	for url in ["https://api.github.com/repos/owner/repo/releases/latest", "https://github.com/owner/repo/releases", "https://github.com.evil.test/owner/repo/releases/download/v1/a", "https://user@github.com/owner/repo/releases/download/v1/a", "http://127.0.0.1:8000/game.exe", "https://example.com/game.apk", "https://ghproxy.net/" + asset, asset + "?token=secret", asset + "#fragment"]:
		t.expect(updater._routes_for(url) == [url], "nonpublic/nonasset URL is never forwarded to proxies: " + url)
	updater.use_download_proxies = false
	t.expect(updater._routes_for(asset) == [asset], "proxies can be disabled without changing original URLs")
	updater.use_download_proxies = true
	updater.download_proxies = ["https://good.example", "https://good.example/", "http://bad.example/", "https://user@bad.example/", "https://bad.example/?x=", "https://bad.example/https://github.com/", "https://backup.example/"]
	t.expect(updater._routes_for(asset) == ["https://good.example/" + asset, "https://backup.example/" + asset, asset], "prefixes normalized, deduplicated and validated")
	for sample in [
		["bytes 20-99/100", 20, 100, 80, true],
		["bytes 20-99/100", 20, 100, 30, true],
		["bytes 0-99/100", 20, 100, 80, false],
		["bytes 20-99/101", 20, 100, 80, false],
		["bytes 20-19/100", 20, 100, 0, false],
		["bytes 20-100/100", 20, 100, 80, false],
		["bytes 20-99/*", 20, 100, 80, false],
		["bytes 20-99/100", 20, 100, 81, false],
		["", 20, 100, 80, false]]:
		t.expect(updater._valid_range(PackedStringArray(["content-range: " + sample[0]]), sample[1], sample[2], sample[3]) == sample[4], "Content-Range validated: " + str(sample))
	updater.free()
	quit(t.finish("update_download_routes"))
