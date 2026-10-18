extends SceneTree
## 真实出牌/胡牌、公共联机事件去重、离线素材、独立音量和多尺寸设置面板。

const H := preload("res://tests/test_harness.gd")
const HAND13 := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tiao5"]
var t := H.new()
var audio
var played: Array = []
var saved_volumes: Dictionary
var saved_enabled: Dictionary
var rendering := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	audio = root.get_node("AudioManager")
	saved_volumes = audio.volumes.duplicate()
	saved_enabled = audio.enabled.duplicate()
	rendering = DisplayServer.get_name() != "headless"
	audio.event_played.connect(func(event: Dictionary): played.append(event))
	# 自动测试仅静音总线，仍检查各通道的真实播放状态。
	var master := AudioServer.get_bus_index("Master")
	var master_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	_test_assets()
	_test_round_events()
	_test_action_events()
	_test_sync()
	await _test_playback()
	_test_persistence()
	await _test_ui()
	for channel in audio.CHANNELS:
		audio.set_volume(channel, float(saved_volumes[channel]), false)
		audio.set_enabled(channel, bool(saved_enabled[channel]), false)
	AudioServer.set_bus_mute(master, master_muted)
	await H.quit_cleanly(self, t.finish("smoke_audio"))

func _test_assets() -> void:
	for seat in 4:
		for tile in Tiles.all_values():
			var stream: AudioStream = audio._stream(_voice_key(seat, tile))
			t.expect(stream != null, "每个座位每个牌名都有离线语音：%d/%s" % [seat, tile])
			if stream != null:
				t.expect(stream.get_length() > 0.1 and stream.get_length() < 1.0, "牌名语音在快档下一秒内说完：%d/%s" % [seat, tile])
				t.expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "牌名只播放一次，不循环：" + tile)
		for word in ["pong", "kong", "ready", "hu", "zimo"]:
			var stream: AudioStream = audio._stream(_voice_key(seat, word))
			t.expect(stream != null and stream.get_length() > 0.1 and stream.get_length() < 1.0, "每个座位动作语音适配快档：%d/%s" % [seat, word])
	for first in 4:
		for second in range(first + 1, 4):
			for word in ["tong8", "pong", "kong", "ready", "hu", "zimo"]:
				var a: AudioStreamWAV = audio._stream(_voice_key(first, word))
				var b: AudioStreamWAV = audio._stream(_voice_key(second, word))
				t.expect(a != null and b != null and a.data != b.data, "四个玩家对应不同声音素材：" + word)
	var music: AudioStream = audio._stream("music/table")
	var effect: AudioStream = audio._stream("effects/discard")
	t.expect(music != null and music.get_length() > 20.0, "循环音乐可加载")
	t.expect(effect != null and effect.get_length() > 0.1, "落桌音效可加载")
	for cue in audio.SETTLEMENT_CUES:
		var stream: AudioStreamWAV = audio._stream("effects/settlement_" + cue)
		t.expect(stream != null, "结算离线音效可加载：" + cue)
		if stream == null: continue
		t.expect(stream.get_length() >= 0.2 and stream.get_length() <= 0.45, "结算短音效不拖尾：" + cue)
		t.expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "结算音效不循环：" + cue)

func _voice_key(seat: int, word: String) -> String:
	return ("voice/" if seat == 0 else "voice/seat%d/" % seat) + word

func _fixture() -> RoundState:
	var game := RoundState.new()
	game.build_players(0)
	game.controllers = [null, null, null, null]
	game.wall = WallRing.new(TileSetFactory.create_deck())
	game.wall.set_head(0)
	game.phase = RoundState.Phase.PLAYING
	for player in game.players:
		player.concealed = HAND13.duplicate()
	return game

func _test_round_events() -> void:
	var game := _fixture()
	var events: Array = []
	game.audio_event.connect(func(event: Dictionary): events.append(event))
	game._discard(0, "invalid")
	t.expect(events.is_empty(), "失败的出牌不能喊牌")
	for seat in 4:
		game.players[seat].concealed.append("tong8")
		game._discard(seat, "tong8")
		t.expect(events.size() == seat + 1, "四个座位每次实际出牌只触发一次")
		t.expect(events.back().seat == seat and events.back().tile == "tong8" and events.back().action == "discard", "出牌语音对应实际座位和牌名")
	game._remove_from_discards(3, "tong8", 0, "meld", 0)
	t.expect(events.size() == 4, "碰杠移走弃牌不能重播牌名")
	var self_draw := _fixture()
	self_draw.players[0].concealed.append("tiao5")
	self_draw.players[0].just_drew = "tiao5"
	self_draw.audio_event.connect(func(event: Dictionary): events.append(event))
	self_draw._apply_turn_action(0, {"self_win": true})
	t.expect(events.back().action == "zimo" and events.back().seat == 0, "实际自摸应播放自摸")
	var count := events.size()
	self_draw._finish()
	t.expect(events.size() == count, "结算刷新不能重复播放胡牌")
	var discard_win := _fixture()
	discard_win.players[1].concealed.append("tiao5")
	discard_win._discard(1, "tiao5")
	discard_win.audio_event.connect(func(event: Dictionary): events.append(event))
	discard_win._discard_win(0, 1, "tiao5")
	t.expect(events.back().action == "hu", "放炮或抢杠胡播放胡了")
	var draw := _fixture()
	draw.audio_event.connect(func(event: Dictionary): events.append(event))
	count = events.size()
	draw._penzu()
	t.expect(events.size() == count, "流局不能播放胡牌语音")
	for id in 40:
		game._emit_audio_event("discard", id % 4, "wan1")
	t.expect(game.audio_events.size() == RoundState.AUDIO_HISTORY_LIMIT and game.audio_events.back().id == game.audio_event_id, "公共声音历史限长且保留最新事件")
	var public: Dictionary = game.serialize_for_seat(0)
	for event in public.audio_events:
		t.expect(event.keys().size() == 5 and event.action == "discard" and event.tile in ["wan1", "tong8"], "声音事件只包含已公开牌，不能泄露摸牌和暗杠")

func _test_action_events() -> void:
	for seat in 4:
		for action in ["pong", "kong"]:
			var claim := _fixture()
			var count := 2 if action == "pong" else 3
			claim.players[seat].concealed = HAND13.slice(0, 13 - count)
			for index in count:
				claim.players[seat].concealed.append("tong8")
			var source := (seat + 3) % 4
			claim.players[source].concealed.append("tong8")
			claim._discard(source, "tong8")
			t.expect(claim.submit_response(seat, "tong8", {"action": action}), "真实碰杠响应被接受：%s/%d" % [action, seat])
			t.expect(claim.audio_events.size() == 2 and claim.audio_events.back().action == action and claim.audio_events.back().seat == seat, "四家碰和明杠在生效时只喊一次")
			t.expect(not claim.submit_response(seat, "tong8", {"action": action}) and claim.audio_events.size() == 2, "重复碰杠请求不重喊")
		var concealed := _fixture()
		concealed.current_turn = seat
		concealed.awaiting = true
		concealed.players[seat].concealed = HAND13.slice(0, 10) + ["tiao8", "tiao8", "tiao8", "tiao8"]
		concealed.players[seat].just_drew = "tiao8"
		t.expect(concealed.submit_turn(seat, {"kong_declares": ["tiao8"]}), "四家暗杠被接受")
		t.expect(concealed.audio_events.size() == 1 and concealed.audio_events[0].action == "kong", "暗杠喊杠一次")
		var public: Dictionary = concealed.serialize_for_seat((seat + 1) % 4)
		t.expect(public.audio_events[0].tile == "" and public.players[seat].melds[0].tile == "hidden0", "暗杠播报和联机状态都不能泄露牌名")
		var added := _fixture()
		added.current_turn = seat
		added.awaiting = true
		added.players[seat].melds = [{"kind": "pung", "tile": "tong8"}]
		added.players[seat].concealed = HAND13.slice(0, 10) + ["tong8"]
		added.players[seat].just_drew = "tong8"
		t.expect(added.submit_turn(seat, {"add_kong": ["tong8"]}), "四家加杠被接受")
		t.expect(added.players[seat].melds[0].kind == "add_kong" and added.audio_events.size() == 1 and added.audio_events[0].action == "kong", "加杠从宣告到完成只喊一次")
	var robbed := _fixture()
	robbed.awaiting = true
	robbed.players[0].melds = [{"kind": "pung", "tile": "tiao5"}]
	robbed.players[0].concealed = HAND13.slice(0, 10) + ["tiao5"]
	robbed.players[0].just_drew = "tiao5"
	robbed.players[2].concealed.clear()
	robbed.players[3].concealed.clear()
	t.expect(robbed.submit_turn(0, {"add_kong": ["tiao5"]}), "可被抢的加杠宣告被接受")
	t.expect(robbed.audio_events.size() == 1 and robbed.audio_events[0].action == "kong", "被抢前先喊杠")
	t.expect(robbed.submit_response(1, "tiao5", {"action": "win"}), "抢杠胡被接受")
	t.expect(robbed.audio_events.size() == 2 and robbed.audio_events[1].action == "hu", "抢杠接胡了，不重复喊杠")
	var ready := _fixture()
	ready.awaiting = true
	ready.players[0].concealed.append("tong9")
	ready.players[0].just_drew = "tong9"
	t.expect(ready.submit_turn(0, {"discard": "tong9", "ready": true}), "首手合法报听被接受")
	t.expect(ready.audio_events.size() == 2 and ready.audio_events[0].action == "ready" and ready.audio_events[1].action == "discard", "先喊报听，再喊实际打出的牌")
	var invalid := _fixture()
	invalid.awaiting = true
	invalid.players[0].concealed.append("tong9")
	invalid.players[0].just_drew = "tong9"
	t.expect(not invalid.submit_turn(0, {"discard": "wan1", "ready": true}) and invalid.audio_events.is_empty(), "无效报听不能喊报听或牌名")
	t.expect(not invalid.submit_turn(0, {"kong_declares": ["wan1"]}) and invalid.audio_events.is_empty(), "无效杠不能喊杠")

func _test_sync() -> void:
	var host := _fixture()
	var client := RoundState.new()
	var events: Array = []
	client.audio_event.connect(func(event: Dictionary): events.append(event))
	host._emit_audio_event("discard", 1, "tiao1")
	client.apply_sync(host.serialize_for_seat(0))
	t.expect(events.is_empty(), "首次加入只定位当前声音进度")
	host._emit_audio_event("discard", 2, "wan9")
	client.apply_sync(host.serialize_for_seat(0))
	t.expect(events.size() == 1 and events[0].tile == "wan9", "联机后续同步播放新的公开事件")
	client.apply_sync(host.serialize_for_seat(0))
	t.expect(events.size() == 1, "重复同步不重播")
	host._emit_audio_event("discard", 3, "tong8")
	host._emit_audio_event("hu", 0, "tong8")
	client.apply_sync(host.serialize_for_seat(0))
	t.expect(events.size() == 3 and events[1].action == "discard" and events[2].action == "hu", "一个同步里的多个事件按顺序播放")
	var old_session := host.audio_session
	host._reset_audio_events()
	host._emit_audio_event("discard", 0, "wan3")
	client.apply_sync(host.serialize_for_seat(0))
	t.expect(host.audio_session != old_session and events.size() == 4 and events.back().id == 1, "下一局从事件1重新播放")
	var reconnect := RoundState.new()
	reconnect.audio_event.connect(func(event: Dictionary): events.append(event))
	reconnect.apply_sync(host.serialize_for_seat(0))
	t.expect(events.size() == 4, "重连不补播上一轮声音")
	for action in ["pong", "kong", "ready"]:
		host._emit_audio_event(action, 2)
		client.apply_sync(host.serialize_for_seat(0))
		var count := events.size()
		t.expect(events.back().action == action and events.back().tile == "", "联机同步碰杠报听，动作不携带暗牌")
		client.apply_sync(host.serialize_for_seat(0))
		t.expect(events.size() == count, "重复同步不重喊动作")

func _test_playback() -> void:
	# 前面的规则计算耗时不应计入刚开始的音轨和渐变。
	await process_frame
	for channel in audio.CHANNELS:
		audio.set_enabled(channel, true, false)
		audio.set_volume(channel, 0.5, false)
	audio.begin_table()
	t.expect(audio.music_player.playing and audio.music_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "入桌自动播放循环音乐")
	t.expect(audio.music_player.stream.loop_end > 400000, "循环覆盖完整音乐")
	played.clear()
	var event := {"session": "test-a", "id": 1, "action": "discard", "seat": 0, "tile": "tiao1"}
	audio.play_event(event)
	t.expect(audio.voice_player.playing and audio.effects_player.playing, "出牌同时播放牌名和落桌音")
	t.expect(audio.voice_player.stream == audio._stream("voice/tiao1"), "幺鸡使用正确音频")
	audio.play_event(event)
	t.expect(played.size() == 1 and audio._voice_queue.is_empty(), "重复事件不会再次落桌或排队")
	for id in range(2, 7):
		audio.play_event({"session": "test-a", "id": id, "action": "discard", "seat": 1, "tile": "wan2"})
	t.expect(audio._voice_queue.size() <= audio.VOICE_QUEUE_LIMIT, "快进积压语音限长")
	audio.play_event({"session": "test-a", "id": 7, "action": "zimo", "seat": 2, "tile": "wan2"})
	t.expect(audio.voice_player.stream == audio._stream("voice/seat2/zimo") and audio._voice_queue.is_empty() and audio._voice_seat_queue.is_empty(), "胡牌语音优先且使用胡牌者声音")
	audio.play_event({"session": "test-b", "id": 1, "action": "discard", "seat": 1, "tile": "tong8"})
	t.expect(audio.voice_player.stream == audio._stream("voice/seat1/tong8"), "下一局清除上局优先状态并保持座位声音")
	# 首次图形初始化可能超过短语长度；单独测压低渐变时固定语音为播放中。
	audio.voice_player.stream_paused = true
	await audio._duck_tween.finished
	t.expect(audio.music_player.volume_db < -9.0, "喊牌期间自动压低背景音乐：%.1fdB" % audio.music_player.volume_db)
	audio.voice_player.stream_paused = false
	audio.set_enabled("voice", false, false)
	t.expect(not audio.voice_player.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")), "关闭语音立即停止声音")
	t.expect(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "关闭语音不影响音乐开关")
	audio.set_volume("effects", 0, false)
	t.expect(not audio.effects_player.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "音效音量为零立即静音")
	audio.set_volume("music", 0.31, false)
	t.expect(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.31), "独立音量实时应用到总线")
	await audio._duck_tween.finished
	t.expect(is_zero_approx(audio.music_player.volume_db), "关语音后恢复背景音乐")
	audio.set_enabled("voice", true, false)
	audio.set_volume("voice", 0, false)
	audio.preview_voice()
	t.expect(not audio.voice_player.playing, "语音音量零时试听也静音")
	audio.set_volume("voice", 0.5, false)
	audio._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	t.expect(audio.music_player.stream_paused and not audio.voice_player.playing, "安卓切到后台暂停音乐并清空语音")
	var count := played.size()
	audio.play_event({"session": "test-b", "id": 2, "action": "discard", "seat": 1, "tile": "wan3"})
	t.expect(not audio.voice_player.playing and played.size() == count, "后台期间不喊牌")
	audio._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	audio.play_event({"session": "test-b", "id": 2, "action": "discard", "seat": 1, "tile": "wan3"})
	t.expect(not audio.music_player.stream_paused and not audio.voice_player.playing, "恢复前台继续音乐、不补喊后台牌名")
	audio.play_event({"session": "test-b", "id": 3, "action": "hu", "seat": 1, "tile": "wan3"})
	await audio.voice_player.finished
	await audio._duck_tween.finished
	t.expect(not audio.voice_player.playing and is_zero_approx(audio.music_player.volume_db), "真实语音播放完毕后自动恢复音乐")
	for index in 3:
		var action: String = ["pong", "kong", "ready"][index]
		audio.play_event({"session": "test-b", "id": index + 4, "action": action, "seat": index, "tile": ""})
		t.expect(audio.voice_player.playing and audio.voice_player.stream == audio._stream(_voice_key(index, action)), "真实播放动作语音：" + action)
		await audio.voice_player.finished
		await audio._duck_tween.finished
	audio.play_event({"session": "test-b", "id": 7, "action": "discard", "seat": 0, "tile": "wan1"})
	for index in 3:
		audio.play_event({"session": "test-b", "id": index + 8, "action": ["pong", "kong", "ready"][index], "seat": index, "tile": ""})
	for id in range(11, 18):
		audio.play_event({"session": "test-b", "id": id, "action": "discard", "seat": 0, "tile": "wan2"})
	t.expect(audio._voice_queue == ["pong", "kong", "ready"], "出牌积压不能挤掉碰、杠、报听播报")
	t.expect(audio._voice_seat_queue == [0, 1, 2], "排队时保留每条动作的玩家声音")
	for seat in 3:
		await audio.voice_player.finished
		t.expect(audio._playing_voice_seat == seat and audio.voice_player.stream == audio._stream(_voice_key(seat, ["pong", "kong", "ready"][seat])), "队列按原动作座位继续播放")
	await audio.voice_player.finished
	await audio._duck_tween.finished
	for seat in 4:
		for action in ["discard", "pong", "kong", "ready", "hu", "zimo"]:
			audio.reset_round()
			audio.play_event({"session": "seat-routing", "id": 1, "action": action, "seat": seat, "tile": "tong8" if action == "discard" else ""})
			t.expect(audio.voice_player.stream == audio._stream(_voice_key(seat, "tong8" if action == "discard" else action)), "所有动作使用实际玩家声音：%d/%s" % [seat, action])
	var older := Node.new()
	var newer := Node.new()
	audio.begin_table(older)
	audio.begin_table(newer)
	audio.set_enabled("effects", true, false)
	audio.set_volume("effects", 0.65, false)
	t.expect(audio.play_settlement_cue("coins", newer) and audio.settlement_player.playing, "当前牌桌可以播放金币到账音效")
	t.expect(not audio.play_settlement_cue("win", older), "旧牌桌不能抢播新牌桌结算音效")
	audio.stop_settlement_cue(older)
	t.expect(audio.settlement_player.playing, "旧牌桌清理不能停止当前牌桌音效")
	audio.end_table(older)
	t.expect(audio.table_active and audio.music_player.playing, "旧牌桌释放不停止新牌桌音乐")
	audio.end_table(newer)
	t.expect(not audio.settlement_player.playing and not audio.play_settlement_cue("coins", newer), "离桌停止结算音效且不能再次播放")
	t.expect(not audio.music_player.playing and not audio.voice_player.playing and not audio.effects_player.playing, "离桌停止所有音轨")
	count = played.size()
	audio.play_event(event)
	t.expect(played.size() == count, "离桌后不响应上局音频事件")
	older.free()
	newer.free()

func _test_persistence() -> void:
	const TEMP := "user://audio_test_settings.cfg"
	audio.set_volume("music", 0.37, false)
	audio.set_enabled("voice", false, false)
	t.expect(audio.save_settings(TEMP) == OK, "设置可以保存")
	audio.set_volume("music", 0.8, false)
	audio.set_enabled("voice", true, false)
	audio._load_settings(TEMP)
	audio._apply_settings()
	t.expect(is_equal_approx(float(audio.volumes.music), 0.37) and not audio.enabled.voice, "设置重载后保留音量和开关")
	var legacy := ConfigFile.new()
	legacy.set_value("music", "volume", 0.28)
	legacy.set_value("voice", "volume", 0.9)
	legacy.save(TEMP)
	audio._load_settings(TEMP)
	t.expect(is_equal_approx(float(audio.volumes.music), 0.28) and is_equal_approx(float(audio.volumes.voice), 0.9), "更新保留旧版已保存音量，不用新版默认值覆盖")
	legacy.set_value("music", "volume", 0.06)
	legacy.set_value("voice", "volume", 0.7)
	legacy.save(TEMP)
	audio._load_settings(TEMP)
	t.expect(is_equal_approx(float(audio.volumes.music), 0.06) and is_equal_approx(float(audio.volumes.voice), 0.7), "音量升级保留用户已经调整过的值")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	if FileAccess.file_exists(TEMP + ".bak"): DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP + ".bak"))

func _test_ui() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(900, 950)
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var menu_sound: Button
	for button in menu.content.get_children():
		if button is Button and button.text == "声音设置":
			menu_sound = button
	t.expect(menu_sound != null, "主菜单有声音设置入口")
	menu_sound.pressed.emit()
	t.expect(menu.sound_settings.is_open(), "主菜单入口打开同一设置面板")
	menu.sound_settings.close(false)
	menu.queue_free()
	await process_frame
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	var sound = table._sound_settings
	sound.persist_changes = false
	table.surface.get_node("SoundButton").pressed.emit()
	t.expect(sound.is_open() and audio.table_active, "牌桌入口可以打开设置且音乐继续")
	for channel in audio.CHANNELS:
		sound.sliders[channel].value = 42
		t.expect(is_equal_approx(float(audio.volumes[channel]), 0.42) and sound.percentages[channel].text == "42%", "滑块即时调整音量和百分比")
		sound.switches[channel].button_pressed = false
		t.expect(not audio.enabled[channel], "开关即时关闭对应通道")
		sound.switches[channel].button_pressed = true
	t.expect(not sound.preview_button.disabled, "语音开启后允许试听")
	for seat in 4:
		sound.voice_selector.select(seat)
		sound.preview_button.pressed.emit()
		t.expect(audio.voice_player.stream == audio._stream(_voice_key(seat, "tong8")), "设置面板可以试听四位玩家声音")
	for dimensions in [Vector2i(900, 950), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(360, 640), Vector2i(640, 360), Vector2i(1080, 1920)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var bounds: Rect2 = sound.panel.get_global_rect()
		t.expect(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(bounds), "声音面板完整位于视口内：" + str(dimensions))
		for control in sound.panel.get_children():
			if control is Control:
				t.expect(bounds.encloses(control.get_global_rect()), "音量控件不溢出面板：" + str(dimensions))
		if rendering and dimensions == Vector2i(900, 950):
			await RenderingServer.frame_post_draw
			t.expect(root.get_texture().get_image().save_png("res://docs/audio_settings.png") == OK, "保存声音面板实际截图")
	# 再用工程真实的画布拉伸设置验证，防止桌面截图正确但手机二次缩小。
	root.content_scale_size = Vector2i(2280, 1280)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for dimensions in [Vector2i(900, 950), Vector2i(360, 640), Vector2i(640, 360)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var visible: Rect2 = root.get_visible_rect()
		t.expect(visible.encloses(sound.panel.get_global_rect()), "游戏拉伸模式下设置面板完整显示：" + str(dimensions))
		var screen_scale := root.get_screen_transform().get_scale().abs()
		var physical_width: float = sound.panel.size.x * sound.panel.scale.x * screen_scale.x
		var expected_width: float = sound.panel.size.x * minf(1.0, minf((dimensions.x - 32.0) / sound.panel.size.x, (dimensions.y - 32.0) / sound.panel.size.y))
		t.expect(absf(physical_width - expected_width) < 2.0, "手机声音面板按真实屏幕放大：" + str(dimensions))
		if rendering and dimensions == Vector2i(360, 640):
			await RenderingServer.frame_post_draw
			t.expect(root.get_texture().get_image().save_png("res://docs/audio_settings_mobile.png") == OK, "保存实际拉伸模式手机截图")
	sound.close(false)
	# 使用生产牌桌信号连接，验证本机和三个 AI 座位的声音入口。
	table.round.phase = RoundState.Phase.IDLE
	table.round = _fixture()
	table._connect_audio_round()
	played.clear()
	for seat in 4:
		table.round.players[seat].concealed.append("tong8")
		table.round._discard(seat, "tong8")
	t.expect(played.size() == 4, "牌桌实际转发四个座位出牌事件")
	table._refresh()
	table._refresh()
	t.expect(played.size() == 4, "UI刷新不能重复出牌声音")
	var position: float = audio.music_player.get_playback_position()
	table.round.players[0].concealed.append("tiao5")
	table.round.players[0].just_drew = "tiao5"
	table.round._do_self_win(0)
	table._table_animation_controller.reset()
	table._settlement_animation_controller.reset()
	table._refresh()
	table._settlement_animation_controller.skip()
	var settled_events := played.size()
	table._refresh()
	table._refresh_next_round_controls()
	t.expect(table._settlement_animation_controller.is_completed() and table._settlement_card._post_controls.visible, "胡牌后直接显示桌面结算和下一局按钮")
	t.expect(played.size() == settled_events, "结算刷新与下一局准备控件不重复播放声音")
	t.expect(audio.music_player.playing and audio.music_player.get_playback_position() >= position, "桌面结算及刷新期间音乐持续播放")
	table.queue_free()
	await process_frame
	t.expect(not audio.table_active and not audio.music_player.playing, "删除牌桌时停止音乐")
