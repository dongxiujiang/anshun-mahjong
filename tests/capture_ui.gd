extends SceneTree
## Rendered visual review; deliberately excluded from headless regression.
var directory := "res://build/ui_review/current"
var scene: Node

func _initialize() -> void:
	call_deferred("_run")

func _capture(label: String) -> void:
	await create_timer(0.38).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	print("[capture] " + label)

func _load_scene(path: String) -> Node:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load(path).instantiate()
	root.add_child(scene)
	await process_frame
	return scene

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): directory = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	root.get_node("UpdateManager").auto_check = false
	root.get_node("GameConfig").ai_speed = "medium"
	root.get_node("UpdateManager")._automatic_checked = true
	var network = root.get_node("Network")
	var menu = await _load_scene("res://scenes/MainMenu.tscn")
	await _capture("01_menu")
	menu.sound_settings.open()
	await _capture("02_sound")
	menu.sound_settings.close(false)
	menu.rule_guide.open()
	for index in 5:
		menu.rule_guide.page = index
		menu.rule_guide._refresh()
		await _capture("03_rules_%d" % index)
	menu.rule_guide.close()
	menu.update_panel.open()
	await _capture("04_update")
	var manager = root.get_node("UpdateManager")
	manager.state = "available"
	manager.latest = {"version": "1.0.5", "kind": "patch", "platform": "windows", "notes": "界面与动效优化\n优化横屏布局、触控反馈和摸打牌动画。"}
	manager.message = "发现小版本补丁 · 1.0.5"
	menu.update_panel._sync()
	await _capture("04_update_available")
	manager.state = "downloading"
	manager.downloaded_bytes = 524288
	manager.total_bytes = 1048576
	menu.update_panel._sync()
	await _capture("04_update_downloading")
	manager.state = "idle"
	manager.latest = {}
	menu.update_panel.close()
	var lobby = await _load_scene("res://scenes/Lobby.tscn")
	await _capture("05_lan_empty")
	network.discovery.stop_search()
	network.discovery.rooms = {"fixture": {"number": "123456", "name": "周末朋友局", "players": 2, "started": false}}
	lobby._render_rooms()
	await _capture("06_rooms")
	lobby.online = true
	lobby.server_button.show()
	network.directory.rooms = []
	lobby._render_rooms()
	await _capture("07_online")
	lobby._open_server()
	await _capture("08_server")
	lobby.server_dialog.hide()
	var net := NetGameNode.new()
	root.add_child(net)
	network.net_node = net
	net.my_seat = 0
	net.lobby = {"name": "周末朋友局", "number": "123456", "owner": 1, "started": false, "countdown": -1, "swap": {}, "seats": []}
	for seat in 4:
		net.lobby.seats.append({"peer": 1 if seat == 0 else -1, "name": "小修" if seat == 0 else "人机%d" % seat, "ready": seat != 0, "wants_dealer": false, "ai": seat != 0})
	lobby._in_room = true
	lobby.browser.hide()
	lobby.waiting.show()
	lobby._render_waiting()
	await _capture("09_waiting")
	net.lobby.seats[1].peer = 2
	net.lobby.seats[1].name = "小江"
	net.lobby.seats[1].ai = false
	net.lobby.swap = {"from": 2, "to": 1}
	lobby._render_waiting()
	await _capture("09_swap_request")
	network.net_node = null
	net.queue_free()
	network.mode = ""
	var table = await _load_scene("res://scenes/GameTable.tscn")
	table.round.controllers = [null, null, null, null]
	while table.round.phase == RoundState.Phase.DEALING or table._table_animation_controller.input_locked():
		await process_frame
	table._table_animation_controller.cancel()
	await _capture("10_table")
	for seat in 4:
		table.round.players[seat].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": posmod(seat+1,4)}, {"kind": "kong", "tile": "tong8", "from_seat": posmod(seat+1,4)}]
		table.round.players[seat].concealed = ["wan1", "wan2", "wan3", "tong2", "tong3", "tong4", "tong5"]
		table.round.players[seat].discards = ["wan5", "wan6", "tong7", "tiao4", "tiao5", "tiao6", "tong9", "wan8", "tiao9", "tong1"]
		table.round.players[seat].just_drew = "tong5" if seat == 0 else ""
	table._refresh()
	table._clear_actions()
	for title in ["碰", "杠", "胡", "过"]: table._add_action(title, func(): pass)
	await _capture("11_meld_actions")
	table.round.round_meta.winner = 1
	table.round.round_meta.winners = [1]
	table.round.round_meta.self_draw = true
	table.round.players[1].concealed = ["wan1", "wan2", "wan3", "tong2", "tong3", "tong4", "tong5", "tong5"]
	table.round.players[1].just_drew = "tong5"
	table.round.wall._ring[table.round.wall._head] = "tong3"
	table.round._finish()
	table._table_animation_controller.reset()
	table._settlement_animation_controller.reset()
	table._refresh()
	table._settlement_animation_controller.skip()
	await _capture("12_settlement")
	# A separate all-called draw uses a fresh ledger and retains the settled UI.
	table.round.phase = RoundState.Phase.PLAYING
	table.round.last_result.clear()
	table.round.round_meta.winner = -1
	table.round.round_meta.winners = []
	table.round.round_meta.self_draw = false
	table.round.round_meta.flip_tile = ""
	for player in table.round.players:
		player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
		player.just_drew = ""
		player.melds.clear()
		player.discards.clear()
	while table.round.wall.remaining > 0: table.round.wall.draw_head()
	table._settlement_animation_controller.reset()
	table.round._penzu()
	table._refresh()
	table._settlement_animation_controller.skip()
	await _capture("12_draw_settlement")
	table._sound_settings.open()
	await _capture("13_table_settings")
	table._sound_settings.confirm_exit()
	await _capture("14_exit_confirmation")
	table._sound_settings.close(false)
	root.size = Vector2i(960, 540)
	table._sound_settings.open()
	await _capture("15_small_settings")
	table._sound_settings.close(false)
	root.size = Vector2i(1600,720)
	await _capture("15_wide_table")
	table._sound_settings.close(false)
	table.queue_free()
	await process_frame
	var small_menu = await _load_scene("res://scenes/MainMenu.tscn")
	small_menu.rule_guide.open()
	await _capture("16_small_rules")
	small_menu.queue_free()
	await create_timer(0.2).timeout
	quit()

