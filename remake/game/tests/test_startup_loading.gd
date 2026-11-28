extends SceneTree
const Main = preload("res://scenes/Main.tscn")
const Client = preload("res://src/network/GameClient.gd")
const Settings = preload("res://src/app/AppSettings.gd")
const Loading = preload("res://src/app/StartupLoading.gd")
const AudioRetirement = preload("res://tests/AudioRetirement.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var page := Loading.new()
	root.add_child(page)
	check(await page.load_resources(), "startup waits for all requested resources, not only the first completed group")
	check(page.retained.size() == 31 and page.retained.all(func(item): return item != null), "tile meshes, textures, all portraits and effects remain cached")
	page.update_stage(100, "完成")
	page.update_stage(10, "旧进度")
	check(page.progress.value == 100, "displayed loading progress never goes backwards")
	page.queue_free()
	var path := "user://startup-test-" + str(Time.get_ticks_usec()) + ".cfg"
	var app := Main.instantiate()
	app._settings = Settings.new(path)
	app._settings.save_profile("加载测试", 1)
	app._settings.update({"directory_url":"http://127.0.0.1:1"})
	root.add_child(app)
	check(app._mode == "online" and app._screen == "connect", "prepared boot opens the homepage without creating a game")
	check(app._lobby_home.get_child(0).get_child_count() == 2, "homepage offers exactly solo and online")
	app._choose_mode("lan")
	check(app._mode == "online" and app._view.is_empty(), "removed mode cannot be entered through a stale callback")
	var old_ticket := {"mode":"lan", "room_number":"1234", "room_instance_id":"old", "member_token":"old", "address":"192.168.1.2", "port":7499}
	check(not app._settings.remember_room(old_ticket), "old LAN recovery tickets are rejected")
	check(not app._client.has_method("host_lan") and not app._client.has_method("promote_lan_from_standby"), "client cannot host or promote a LAN server")
	check(not app._client.connect_room("127.0.0.1", 7499, {"mode":"lan"}), "removed mode cannot open a network connection")
	var table = app._table
	table.prewarm_visuals()
	for batch in 9: table.prewarm_tiles(12)
	check(table._tile_pool.size() == 108, "all physical tile nodes are prepared before opening")
	table.show_full_wall(1)
	var nodes: Array = table.tiles.values().map(func(node): return node.get_instance_id())
	nodes.sort()
	check(table.tiles.size() == 108 and table._tile_pool.is_empty(), "opening consumes prepared tiles without an extra wall allocation")
	table.apply_view({})
	check(table.tiles.is_empty() and table._tile_pool.size() == 108, "returning to the homepage clears displayed tiles and retains reusable nodes")
	table.show_full_wall(1)
	var reused: Array = table.tiles.values().map(func(node): return node.get_instance_id())
	reused.sort()
	check(nodes == reused, "the next opening reuses the same physical nodes")
	table.apply_view({})
	app._sound.prewarm_effects()
	check(app._sound._cache.get("effects/dice_roll.wav") != null and not app._sound._effects.playing, "dice audio is loaded without playing during startup")
	await AudioRetirement.release_app(app, self)
	DirAccess.remove_absolute(path)
	print("Startup loading: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
