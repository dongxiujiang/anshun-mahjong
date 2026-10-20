extends SceneTree
## 联机大厅：昵称自动生成“昵称+麻将局”；手动改名后不再跟随昵称。

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var config = root.get_node("GameConfig")
	var network = root.get_node("Network")
	var old_name: String = config.player_name
	var old_prefs: Dictionary = network.lobby_preferences.duplicate()
	config.set_player_name("张三", false)
	network.lobby_preferences = {"online": false, "number": "778899", "name": "旧房间", "room_name_manual": false}
	var lobby = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	var ok: bool = lobby.room_name_input.text == "张三麻将局"
	lobby.player_input.text = "李四"
	lobby._on_player_name_changed("李四")
	ok = ok and lobby.room_name_input.text == "李四麻将局"
	lobby.room_name_input.text = "我的自定义房间"
	lobby._on_room_name_changed("我的自定义房间")
	lobby.player_input.text = "王五"
	lobby._on_player_name_changed("王五")
	ok = ok and lobby.room_name_input.text == "我的自定义房间"
	lobby.queue_free()
	await process_frame
	# A new lobby must preserve the manual name and not force it back.
	var lobby2 = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby2)
	await process_frame
	ok = ok and lobby2.room_name_input.text == "我的自定义房间"
	lobby2.queue_free()
	await process_frame
	config.set_player_name(old_name, false)
	network.lobby_preferences = old_prefs
	print("[lobby_room_name] ", "passed" if ok else "FAILED")
	quit(0 if ok else 1)
