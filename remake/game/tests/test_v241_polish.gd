extends SceneTree

const MahjongNames := preload("res://src/domain/MahjongNames.gd")
const Room := preload("res://src/session/RoomSession.gd")
const ProfileSetup := preload("res://src/app/ProfileSetup.gd")
const SettlementView := preload("res://src/app/SettlementView.gd")
const FlipChickenReveal := preload("res://src/app/FlipChickenReveal.gd")
const GameClient := preload("res://src/network/GameClient.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL v241 polish: " + message)


func _is_tile_name(text: String) -> bool:
	var forbidden := ["幺鸡", "红中", "发财", "白板", "东风", "南风", "西风", "北风"]
	if forbidden.has(text):
		return true
	var nums := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
	var suits := ["万", "条", "筒"]
	for n in nums:
		for s in suits:
			if text == n + s:
				return true
	return false


func _run() -> void:
	# 1. 100 Mahjong-themed nicknames: exact count, unique, valid, zero tile names.
	check(MahjongNames.POOL.size() == 100, "MahjongNames pool has exactly 100 entries (got %d)" % MahjongNames.POOL.size())
	var unique := {}
	var all_valid := true
	var no_tile_names := true
	for entry in MahjongNames.POOL:
		unique[entry] = true
		if not Room.is_valid_nickname(entry):
			all_valid = false
			printerr("  invalid nickname: " + entry)
		if _is_tile_name(entry):
			no_tile_names = false
			printerr("  tile name found: " + entry)
	check(unique.size() == 100, "all 100 Mahjong nicknames are unique")
	check(all_valid, "all 100 Mahjong nicknames pass RoomSession.is_valid_nickname")
	check(no_tile_names, "none of the 100 nicknames is a tile name")

	# 2. RoomSession AI nicknames: non-tile, 4 distinct, deduplicated against joining humans and leaving humans.
	var room := Room.new("8841")
	var snap := room.snapshot(100)
	var seen_ai := {}
	var ai_clean := true
	for seat_row in snap.seats:
		var nick := str(seat_row.nickname)
		seen_ai[nick] = true
		if _is_tile_name(nick) or not MahjongNames.POOL.has(nick):
			ai_clean = false
	check(seen_ai.size() == 4 and ai_clean, "new room assigns 4 unique MahjongNames AI nicknames with zero tile names")
	var collision_target := str(snap.seats[0].nickname)
	var joined := room.join("p1", collision_target, "c1", 101, {}, "", 1)
	check(joined.get("joined", false), "human joins seat 1 with an existing AI's nickname")
	var after_join := room.snapshot(102)
	var join_names := {}
	for seat_row in after_join.seats:
		join_names[str(seat_row.nickname)] = true
	check(after_join.seats[1].nickname == collision_target and join_names.size() == 4, "AI seat colliding with human nickname is automatically renamed without duplicates")
	room.join("p2", "测友二", "c2", 103, {}, "", 2)
	check(room.leave_human("c2", 104), "second human leaves cleanly")
	var after_leave := room.snapshot(105)
	var leave_names := {}
	for seat_row in after_leave.seats:
		leave_names[str(seat_row.nickname)] = true
	check(leave_names.size() == 4 and MahjongNames.POOL.has(after_leave.seats[2].nickname), "replacement AI seat draws a non-duplicate nickname from MahjongNames")

	# 3. ProfileSetup 100-name picker UI.
	var editor := ProfileSetup.new()
	root.add_child(editor)
	editor.build({"nickname": "测试", "avatar": 1}, true)
	await process_frame
	check(editor._name_buttons.size() == 100 and not editor._name_picker_section.visible, "ProfileSetup builds all 100 preset name buttons hidden by default")
	editor._name_picker_btn.pressed.emit()
	await process_frame
	check(editor._name_picker_section.visible and not editor._avatar_section.visible, "clicking 挑昵称 opens the 100-name picker")
	editor._name_buttons[42].pressed.emit()
	await process_frame
	check(editor._nickname.text == MahjongNames.POOL[42] and not editor._name_picker_section.visible and editor._avatar_section.visible, "selecting a preset name fills nickname and returns to avatar view")
	editor._name_picker_btn.pressed.emit()
	editor.fit(Vector2(800, 200), true)
	await process_frame
	check(not editor._name_picker_section.visible and not editor._gallery.visible, "opening keyboard closes name picker and compacts panel")
	editor.queue_free()

	# 4. SettlementView shows specific win pattern label (e.g. 大对子+14) in overlay mode.
	var sv := SettlementView.new()
	root.add_child(sv)
	var settlement := {
		"viewer_seat": 1,
		"round_meta": {"self_draw": true, "die": 3, "die_white": 5, "flip_tile": "tiao2"},
		"scores": [182, 254, 182, 182],
		"seats": [
			{"nickname": MahjongNames.POOL[1]},
			{"nickname": MahjongNames.POOL[0]},
			{"nickname": MahjongNames.POOL[2]},
			{"nickname": MahjongNames.POOL[3]},
		],
		"ledger": {
			"multiplier": 1,
			"winners": [1],
			"status": ["叫牌", "叫牌", "未叫牌", "未叫牌"],
			"deltas": [-18, 54, -18, -18],
			"pairwise": [[0, -18, 0, 0], [18, 0, 18, 18], [0, -18, 0, 0], [0, -18, 0, 0]],
			"items": [
				[],
				[
					{"kind": "pattern", "label": "大对子", "amount": 14, "opponents": [0, 2, 3], "tiles": ["wan5"], "tile_ids": [12]},
					{"kind": "charge", "label": "冲锋鸡", "amount": 4, "opponents": [0, 2, 3], "tiles": ["tiao1"], "tile_ids": [34]},
				],
				[],
				[],
			],
		},
	}
	sv.show_result(settlement, "solo", func(): pass, func(): pass, null, true)
	await process_frame
	var texts := PackedStringArray()
	for lbl in sv.find_children("*", "Label", true, false):
		texts.append((lbl as Label).text)
	check(texts.has("大对子+14"), "settlement overlay explicitly renders win pattern label 大对子+14 next to winning tile (found: %s)" % ", ".join(texts))
	check(sv._headings[0].get_child(2).get_child_count() == 1 and texts.has("翻鸡"), "settlement overlay renders the flip chicken badge in the top-right header")
	var found_sideways := false
	for p in sv.find_children("*", "PanelContainer", true, false):
		var c := p as PanelContainer
		if is_equal_approx(c.custom_minimum_size.x, 32.0) and is_equal_approx(c.custom_minimum_size.y, 24.0):
			found_sideways = true
	check(found_sideways, "settlement overlay preserves sideways charge chicken tile orientation")
	sv.queue_free()

	# 5. FlipChickenReveal renders flip tile + 3 related tiles + gold chicken hint + emits finished.
	var reveal := FlipChickenReveal.new()
	root.add_child(reveal)
	var finished_keys: Array[String] = []
	reveal.finished.connect(func(k: String): finished_keys.append(k))
	var presented := reveal.present("r1/1", {"flip_tile": "tiao2", "winners": [1], "self_draw": true}, settlement.seats)
	await process_frame
	check(presented and reveal.visible and reveal.flip_tile_value == "tiao2", "FlipChickenReveal presents valid flip tile")
	check(reveal._related_row.get_child_count() == 3 and reveal._gold_hint_label.visible, "FlipChickenReveal displays 3 related tiles and gold chicken highlight when tiao1 is included")
	check(reveal.find_children("*", "Button", true, false).is_empty(), "FlipChickenReveal auto-advances without requiring a manual button click")
	reveal._tween.custom_step(5.0)
	await process_frame
	check(not reveal.visible and finished_keys == ["r1/1"], "FlipChickenReveal auto-completes after flip animation and emits finished with exact key")
	reveal.queue_free()

	# 6. GameClient allows PCM voice relay over real connected online & LAN sessions, never solo.
	var solo := GameClient.new()
	root.add_child(solo)
	solo.mode = "solo"
	check(not solo.voice_chat_allowed(), "voice relay disabled in solo mode")
	solo.queue_free()
	var srv := GameClient.new()
	var cli := GameClient.new()
	root.add_child(srv)
	root.add_child(cli)
	var started := srv.start_server("7741", 0, {}, "online")
	check(started, "real online GameClient server starts for voice relay check")
	if started:
		var connected := cli.connect_room("127.0.0.1", srv.local_port, {"mode": "online", "room_number": "7741", "player_id": "v241p1", "nickname": MahjongNames.POOL[0], "avatar": 1})
		var deadline := Time.get_ticks_msec() + 3000
		while connected and not cli.voice_chat_allowed() and Time.get_ticks_msec() < deadline:
			await process_frame
			OS.delay_msec(2)
		check(cli.voice_chat_allowed(), "connected online GameClient allows ENet PCM voice relay fallback")
	cli._reset()
	srv._reset()
	cli.queue_free()
	srv.queue_free()
	await process_frame

	print("v241 polish: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
