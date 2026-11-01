extends "res://scripts/ui/table/TableViewBridge.gd"

signal quit_to_menu

const CONNECTION_OVERLAY := preload("res://scripts/ui/ConnectionOverlay.gd")
const TEST_PATTERNS := preload("res://scripts/core/TestPatterns.gd")


## 牌局与联机事件协调器。视觉状态由 table/ 组件持有。
## TableViewBridge 保留既有联机和测试接口；视觉参数统一在 TableUiConfig。

var round: RoundState
var human_seat := 0
var net_submit_turn: Callable
var net_submit_response: Callable
var _round_number := 0
var _connection_overlay: Control
var _speed_buttons := {}
var _sound_settings: SoundSettings
var _audio_round: RoundState
var _sound_button: Button
var _settings_button: Button
var _voice_button: Button
var _ai_proxy_button: Button
var _test_pattern_button: Button
var _ai_teach_button: Button
var _test_choice_panel: Panel
var _test_choice_box: VBoxContainer
var _test_vote_panel: Panel
var _test_vote_label: Label
var _test_vote_buttons: HBoxContainer
var _test_vote_id := ""
var _test_mode_ui := false

var _ai_teach_token := 0
var _ai_teach_task := 0
var _ai_teach_worker = null
var _ai_teach_message := ""
var _refresh_queued := false
var _ai_assist_enabled := false
var _auto_test_rounds := 0
var _auto_test_completed := 0
var _auto_test_online_ai: AiPlayer
var _auto_test_prompt_seen := -1
var _auto_test_settled_round := -1
var _ai_proxy_active := false
var _ai_proxy_ai: AiPlayer
var _ai_proxy_worker = null
var _ai_proxy_task := 0
var _ai_proxy_response_tile := ""
var _ai_proxy_response_pending := false
var _voice_pack_dialog: Control
var _voice_pack_layer: CanvasLayer
var _settlement_round_id := 0
var _settlement_session := ""
var _settlement_round_number := -1
var _settlement_phase := -1
var _settlement_immediate := false
var _awaiting_rejoin_snapshot := false
var _quitting := false
var _opening_primed := false
var _ai_service = null
var _return_vote_overlay: Control
var _return_vote_panel: Panel
var _return_vote_message: Label
var _return_vote_token := -1
var _return_vote_status: Label
var _resume_generation := 0

func _ready() -> void:
	AudioManager.begin_table(self)
	_build_static_ui()
	_build_table_overlays()
	_connection_overlay = CONNECTION_OVERLAY.new()
	add_child(_connection_overlay)
	_connection_overlay.retry_requested.connect(_retry_connection)
	_connection_overlay.leave_requested.connect(func(): _on_quit(true))
	_connect_voice_ui()
	get_window().focus_exited.connect(_on_input_focus_changed)
	get_window().focus_entered.connect(_on_input_focus_changed)
	resized.connect(_layout)
	_layout()
	var mode := _net_mode()
	if mode == "host":
		_setup_host_view()
	elif mode == "client":
		_setup_client_view()
	else:
		new_game()

func _connect_audio_round() -> void:
	if _audio_round != null and _audio_round.audio_event.is_connected(_on_audio_event):
		_audio_round.audio_event.disconnect(_on_audio_event)
	if _audio_round != null and _audio_round.visual_event.is_connected(_on_visual_event):
		_audio_round.visual_event.disconnect(_on_visual_event)
	_audio_round = round
	_opening_primed = false
	AudioManager.reset_round(round.audio_session, round.audio_event_id)
	_table_animation_controller.reset()
	_settlement_animation_controller.reset()
	_settlement_card.hide_post_settlement_controls()
	_settlement_round_id = 0
	_settlement_phase = -1
	_last_tile_input_ms = -1000
	round.audio_event.connect(_on_audio_event)
	if not round.visual_event.is_connected(_on_visual_event):
		round.visual_event.connect(_on_visual_event)

func _on_audio_event(event: Dictionary) -> void:
	AudioManager.play_event(event, _table_animation_controller.defers_discard_sound())

func _connect_voice_ui() -> void:
	var net = _net_node()
	if net == null:
		return
	if net.has_signal("voice_status") and not net.voice_status.is_connected(_on_voice_status):
		net.voice_status.connect(_on_voice_status)
	if net.has_signal("game_started") and not net.game_started.is_connected(_refresh_voice_button):
		net.game_started.connect(_refresh_voice_button)
	if net.has_signal("host_game_started") and not net.host_game_started.is_connected(_refresh_voice_button):
		net.host_game_started.connect(_refresh_voice_button)
	if net.has_signal("returned_to_lobby") and not net.returned_to_lobby.is_connected(_on_returned_to_lobby):
		net.returned_to_lobby.connect(_on_returned_to_lobby)
	if net.has_signal("return_vote_updated") and not net.return_vote_updated.is_connected(_on_return_vote_updated):
		net.return_vote_updated.connect(_on_return_vote_updated)
	_refresh_voice_button()

func _ensure_return_vote_ui() -> void:
	if _return_vote_overlay != null:
		return
	_return_vote_overlay = Control.new()
	_return_vote_overlay.name = "ReturnRoomVote"
	_return_vote_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_return_vote_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_return_vote_overlay.z_index = 400
	add_child(_return_vote_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.04, 0.03, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_return_vote_overlay.add_child(shade)
	_return_vote_panel = Panel.new()
	_return_vote_panel.size = Vector2(820, 360)
	_return_vote_panel.add_theme_stylebox_override("panel", _style(Color("#1e4234"), Color("#cbb279"), 24, 2))
	_return_vote_overlay.add_child(_return_vote_panel)
	var title := _label(_return_vote_panel, "返回房间", Vector2(52, 30), Vector2(716, 54), 40, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_return_vote_message = _label(_return_vote_panel, "", Vector2(52, 96), Vector2(716, 120), 28, UI.INK)
	_return_vote_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_return_vote_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var agree := _button("同意", _answer_return_vote.bind(true), Vector2(300, 92), true)
	agree.position = Vector2(80, 238)
	agree.name = "ReturnVoteAgree"
	_return_vote_panel.add_child(agree)
	var reject := _button("拒绝", _answer_return_vote.bind(false), Vector2(300, 92))
	reject.position = Vector2(440, 238)
	reject.name = "ReturnVoteReject"
	_return_vote_panel.add_child(reject)
	_return_vote_overlay.hide()

func _answer_return_vote(value: bool) -> void:
	var net = _net_node()
	if net != null and net.has_method("answer_return_vote"):
		net.answer_return_vote(value)
	if _return_vote_overlay != null:
		_return_vote_overlay.hide()

func _on_return_vote_updated(data: Dictionary) -> void:
	_ensure_return_vote_ui()
	if not bool(data.get("active", false)):
		_return_vote_overlay.hide()
		_return_vote_status.hide()
		_return_vote_token = -1
		return
	var humans: Array = data.get("humans", [])
	var yes: Dictionary = data.get("yes", {})
	var agree_count := 0
	for seat_value in humans:
		if bool(yes.get(int(seat_value), false)): agree_count += 1
	_return_vote_status.text = "返回房间同意 %d/%d" % [agree_count, humans.size()]
	_return_vote_status.show()
	if human_seat not in humans or bool(yes.get(human_seat, false)):
		_return_vote_overlay.hide()
		return
	var initiator := int(data.get("initiator", -1))
	var who := "其他玩家" if initiator < 0 or initiator == human_seat else _seat_name(initiator)
	var token := initiator * 10 + int(data.get("rejecter", -1))
	if _return_vote_overlay.visible and _return_vote_token == token:
		return
	_return_vote_token = token
	_return_vote_message.text = "%s 发起返回房间。\n全部真人同意后，大家一起回到选座等待。" % who
	var design := _design_size()
	_return_vote_panel.position = (design - _return_vote_panel.size) * 0.5
	_return_vote_overlay.show()

func _on_returned_to_lobby() -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _toggle_voice_chat() -> void:
	var net = _net_node()
	if net == null or not net.has_method("toggle_voice_chat"):
		return
	net.toggle_voice_chat()
	_refresh_voice_button()

func _build_table_overlays() -> void:
	_return_vote_status = Label.new()
	_return_vote_status.name = "ReturnVoteStatus"
	_return_vote_status.position = Vector2(24, 154)
	_return_vote_status.size = Vector2(1040, 40)
	_return_vote_status.add_theme_font_override("font", TileView._font())
	_return_vote_status.add_theme_font_size_override("font_size", 24)
	_return_vote_status.add_theme_color_override("font_color", Color("#ffe6a8"))
	_return_vote_status.add_theme_color_override("font_outline_color", Color("#102018"))
	_return_vote_status.add_theme_constant_override("outline_size", 4)
	_return_vote_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_return_vote_status.z_index = 100
	add_child(_return_vote_status)
	_return_vote_status.hide()
	_build_test_pattern_ui()

func _build_test_pattern_ui() -> void:
	_test_vote_panel = Panel.new()
	_test_vote_panel.name = "TestPatternVote"
	_test_vote_panel.size = Vector2(760, 170)
	_test_vote_panel.position = Vector2((_design_size().x - 760.0) / 2.0, 130.0)
	_test_vote_panel.z_index = 210
	_test_vote_panel.add_theme_stylebox_override("panel", _style(Color("#102018f2"), UI.GOLD, 16, 2))
	add_child(_test_vote_panel)
	_test_vote_label = Label.new()
	_test_vote_label.position = Vector2(24, 18)
	_test_vote_label.size = Vector2(712, 64)
	_test_vote_label.add_theme_font_override("font", TileView._font())
	_test_vote_label.add_theme_font_size_override("font_size", 26)
	_test_vote_label.add_theme_color_override("font_color", UI.INK)
	_test_vote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_vote_panel.add_child(_test_vote_label)
	_test_vote_buttons = HBoxContainer.new()
	_test_vote_buttons.position = Vector2(24, 96)
	_test_vote_buttons.size = Vector2(712, 64)
	_test_vote_buttons.add_theme_constant_override("separation", 20)
	_test_vote_panel.add_child(_test_vote_buttons)
	var agree := _button("同意", func(): _answer_test_vote(true), Vector2(220, 60), true)
	agree.name = "AgreeTestPattern"
	var reject := _button("拒绝", func(): _answer_test_vote(false), Vector2(220, 60))
	reject.name = "RejectTestPattern"
	_test_vote_buttons.add_child(agree)
	_test_vote_buttons.add_child(reject)
	_test_vote_panel.hide()

func _on_test_pattern_pressed() -> void:
	if not GameConfig.debug_enabled:
		return
	var net = _net_node()
	if net == null or net.mode == "":
		return
	if _test_choice_panel == null:
		_test_choice_panel = Panel.new()
		_test_choice_panel.name = "TestPatternChooser"
		_test_choice_panel.size = Vector2(620, 390)
		_test_choice_panel.position = Vector2((_design_size().x - 620.0) / 2.0, 150.0)
		_test_choice_panel.z_index = 220
		_test_choice_panel.add_theme_stylebox_override("panel", _style(Color("#102018f5"), UI.GOLD, 18, 2))
		add_child(_test_choice_panel)
		var title := Label.new()
		title.text = "选择测试牌型"
		title.position = Vector2(24, 18)
		title.size = Vector2(572, 44)
		title.add_theme_font_override("font", TileView._font())
		title.add_theme_font_size_override("font_size", 30)
		title.add_theme_color_override("font_color", UI.GOLD)
		_test_choice_panel.add_child(title)
		_test_choice_box = VBoxContainer.new()
		_test_choice_box.position = Vector2(24, 74)
		_test_choice_box.size = Vector2(572, 300)
		_test_choice_box.add_theme_constant_override("separation", 8)
		_test_choice_panel.add_child(_test_choice_box)
		for entry in TEST_PATTERNS.CATALOG:
			var pattern := str(entry.id)
			var button := _button(str(entry.name),
				func(): _choose_test_pattern(pattern), Vector2(572, 68))
			button.tooltip_text = str(entry.description)
			button.add_theme_font_size_override("font_size", 26)
			_test_choice_box.add_child(button)
		var cancel := _button("取消", func(): _test_choice_panel.hide(), Vector2(572, 48))
		cancel.add_theme_font_size_override("font_size", 20)
		_test_choice_box.add_child(cancel)
	_test_choice_panel.show()

func _choose_test_pattern(pattern: String) -> void:
	if _test_choice_panel != null:
		_test_choice_panel.hide()
	var net = _net_node()
	if net != null:
		net.propose_test_pattern(pattern)

func _answer_test_vote(agree: bool) -> void:
	var net = _net_node()
	if net != null:
		net.answer_test_vote(agree, _test_vote_id)
	_refresh_test_pattern_ui()

func _refresh_test_pattern_ui() -> void:
	if _test_vote_panel == null:
		return
	if not GameConfig.debug_enabled:
		_test_vote_panel.hide()
		return
	var net = _net_node()
	var vote: Dictionary = net.lobby.get("test_vote", {}) if net != null else {}
	if vote.is_empty():
		_test_vote_id = ""
		_test_vote_panel.hide()
		return
	_test_vote_id = str(vote.get("proposal_id", ""))
	var pattern := str(vote.get("pattern", ""))
	var entry: Dictionary = TEST_PATTERNS.get_entry(pattern)
	var humans: Array = vote.get("humans", [])
	var yes: Array = vote.get("yes", [])
	var me := int(net.my_seat)
	if me in yes:
		_test_vote_label.text = "测试牌型：%s\n已同意，等待其他真人同意（%d/%d）" % [entry.get("name", pattern), yes.size(), humans.size()]
	else:
		_test_vote_label.text = "有玩家申请测试牌型：%s\n是否同意立即重开本局并给发起者发这套牌？" % entry.get("name", pattern)
	_test_vote_buttons.visible = me not in yes
	_test_vote_panel.show()

func _on_voice_status(_enabled: bool, _message: String) -> void:
	_refresh_voice_button()

func _on_ai_assist_pressed() -> void:
	if _ai_teach_button == null:
		return
	_ai_assist_enabled = _ai_teach_button.button_pressed
	_ai_teach_button.text = "AI教学 开" if _ai_assist_enabled else "AI教学"
	if not _ai_assist_enabled:
		_clear_ai_teach()
		return
	# 非出牌回合打开开关只记录状态，不弹“不是你的回合”；下一次
	# 自己摸牌出牌时会自动提示。
	if _is_ai_turn_now():
		request_ai_teach()

func open_voice_packs() -> void:
	if _voice_pack_dialog == null:
		_voice_pack_layer = CanvasLayer.new()
		_voice_pack_layer.layer = 30
		add_child(_voice_pack_layer)
		_voice_pack_dialog = load("res://scripts/ui/VoicePackDialog.gd").new()
		_voice_pack_layer.add_child(_voice_pack_dialog)
		_voice_pack_dialog.pack_selected.connect(_on_voice_pack_selected)
		_voice_pack_dialog.preview_requested.connect(_on_voice_pack_preview)
		_voice_pack_dialog.test_all_requested.connect(func(): AudioManager.start_voice_test())
	var net = _net_node()
	var seat := human_seat
	var is_host := false
	if net != null and _net_mode() != "":
		for index in 4:
			AudioManager.set_seat_voice_pack(index, str(net.voice_packs[index]), false)
		seat = net.my_seat
		is_host = net.is_room_owner()
	else:
		is_host = true
	var packs: Array = []
	for index in 4:
		packs.append(AudioManager.get_seat_voice_pack(index))
	_voice_pack_dialog.open(packs, seat, is_host)

func _on_voice_pack_selected(seat: int, pack_id: String) -> void:
	# 本地先立即生效并保存，联机再交给房主权威同步。
	AudioManager.set_seat_voice_pack(seat, pack_id, seat == human_seat)
	AudioManager.save_settings()
	var net = _net_node()
	if net != null and _net_mode() != "":
		net.request_voice_pack(seat, pack_id)

func _on_voice_pack_preview(seat: int, pack_id: String) -> void:
	AudioManager.preview_voice_pack(seat, pack_id)

func _is_ai_turn_now() -> bool:
	return round != null and round.players.size() == 4 \
		and round.phase == RoundState.Phase.PLAYING \
		and round.awaiting and round.current_turn == human_seat

func _refresh_ai_assist() -> void:
	if not _ai_assist_enabled:
		return
	# 把教打分析从摸牌/刷新手牌那一帧挪开，避免 120Hz 下多一次主线程尖峰。
	await get_tree().create_timer(0.10).timeout
	if not _ai_assist_enabled or not _is_ai_turn_now():
		return
	request_ai_teach()

func _clear_ai_teach() -> void:
	_ai_teach_token += 1
	_ai_teach_message = ""
	var pending := _ai_teach_task
	_ai_teach_task = 0
	if pending > 0 and _ai_teach_worker != null:
		_ai_teach_worker.cancel(pending)
	if _player_tile_areas != null:
		_player_tile_areas.clear_ai_teach_highlight()

func request_ai_teach() -> void:
	if round == null or round.players.size() != 4:
		return
	if not _is_ai_turn_now():
		return
	_clear_ai_teach()
	# 轻量向听/进张分析在主线程完成，不再为一次教打启动线程和整局快照。
	_apply_ai_teach_result(AiTeaching.recommend_fast(round, human_seat))

func _apply_ai_teach_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	var tile := str(result.get("tile", ""))
	if _player_tile_areas != null:
		_player_tile_areas.clear_ai_teach_highlight()
		if tile != "":
			_player_tile_areas.highlight_ai_teach(tile)
	if result.has("message"):
		_ai_teach_message = str(result.message)
		if status_label != null:
			status_label.text = _ai_teach_message
			status_label.show()

func _poll_ai_teach() -> void:
	if _ai_teach_task <= 0 or _ai_teach_worker == null:
		return
	var result: Dictionary = _ai_teach_worker.take_result(_ai_teach_task)
	if result.is_empty():
		return
	_ai_teach_task = 0
	_apply_ai_teach_result(result)

func _refresh_voice_button() -> void:
	if _voice_button == null:
		return
	var net = _net_node()
	var online: bool = _net_mode() != "" and net != null and net.has_method("voice_chat_enabled")
	_voice_button.visible = online
	if not online:
		return
	_voice_button.text = "麦克风 开" if net.voice_chat_enabled() else "麦克风 关"
	_voice_button.disabled = not net.voice_chat_allowed()

func _toggle_remote_voice(seat: int) -> void:
	var net = _net_node()
	var chat = net.get("voice_chat") if net != null else null
	if chat == null or not chat.has_method("speaker_enabled"):
		return
	chat.set_speaker_enabled(seat, not bool(chat.speaker_enabled(seat)))
	if _player_tile_areas != null:
		_player_tile_areas._refresh_identity(seat)

func _remote_voice_enabled(seat: int) -> bool:
	var net = _net_node()
	var chat = net.get("voice_chat") if net != null else null
	return chat != null and chat.has_method("speaker_enabled") and bool(chat.speaker_enabled(seat))

func _process(_delta: float) -> void:
	if round == null:
		return
	_poll_ai_teach()
	_poll_ai_proxy()

	# Online authority and clients already poll in NetGameNode._process.
	var network = get_node_or_null("/root/Network")
	if network == null or network.net_node == null or str(network.mode) == "":
		round.poll_ai()
	elif _auto_test_rounds > 0 or _ai_proxy_active:
		_auto_test_poll_online()

func _exit_tree() -> void:
	var net = _net_node()
	if net != null:
		var chat = net.get("voice_chat")
		if chat != null and chat.has_method("set_enabled"):
			chat.set_enabled(false)
		if net.has_signal("voice_status") and net.voice_status.is_connected(_on_voice_status):
			net.voice_status.disconnect(_on_voice_status)
	if _ai_service != null:
		var tree := get_tree()
		if tree != null:
			_ai_service.stop_async(tree)
		else:
			_ai_service.stop()
		_ai_service = null
	if _ai_teach_worker != null:
		var teach_tree := get_tree()
		if teach_tree != null:
			_ai_teach_worker.stop_async(teach_tree)
		else:
			_ai_teach_worker.stop()
		_ai_teach_worker = null
	if _ai_proxy_worker != null:
		var proxy_tree := get_tree()
		if proxy_tree != null:
			_ai_proxy_worker.stop_async(proxy_tree)
		_ai_proxy_worker = null
	_ai_proxy_active = false
	_ai_proxy_task = 0
	if round != null and _net_mode() == "": round.cancel_opening()
	if _audio_round != null and _audio_round.audio_event.is_connected(_on_audio_event):
		_audio_round.audio_event.disconnect(_on_audio_event)
	if _audio_round != null and _audio_round.visual_event.is_connected(_on_visual_event):
		_audio_round.visual_event.disconnect(_on_visual_event)
	_audio_round = null
	_table_animation_controller.cancel()
	_table_animation_controller.dispose_pool()
	_settlement_animation_controller.reset()
	AudioManager.end_table(self)

func _net_mode() -> String:
	# Some UI smoke tests construct the table before attaching it to the scene
	# tree.  Absolute lookups are invalid in that state; treat it as offline
	# until the node has a tree owner, matching the normal standalone mode.
	if not is_inside_tree():
		return ""
	var network := get_node_or_null("/root/Network")
	return network.mode if network != null else ""

func _net_node():
	if not is_inside_tree():
		return null
	var network := get_node_or_null("/root/Network")
	return network.net_node if network != null else null

func enable_net(turn_cb: Callable, response_cb: Callable) -> void:
	net_submit_turn = turn_cb
	net_submit_response = response_cb

func _emit_turn(decision: Dictionary) -> void:
	if net_submit_turn.is_valid():
		net_submit_turn.call(decision)
	else:
		round.submit_turn(human_seat, decision)

func _emit_response(tile: String, decision: Dictionary) -> void:
	if net_submit_response.is_valid():
		net_submit_response.call(tile, decision)
	else:
		round.submit_response(human_seat, tile, decision)

func start_auto_test(rounds: int = 100) -> void:
	var online := _net_mode() != ""
	if online:
		var net = _net_node()
		if net == null or net.game == null or net.game.phase == RoundState.Phase.IDLE:
			return
	_auto_test_rounds = maxi(1, rounds)
	_auto_test_completed = 0
	_auto_test_prompt_seen = -1
	_auto_test_settled_round = -1
	if online:
		# 真实速度：不修改任何动画/人机延迟，只代替玩家点击。
		_auto_test_online_ai = null
		print("[auto-test] start rounds=%d mode=online real-speed" % _auto_test_rounds)
		return
	GameConfig.set_ai_speed("fast", false)
	GameConfig.animation_speed = "instant"
	GameConfig.draw_animation_speed = "instant"
	GameConfig.discard_animation_speed = "instant"
	GameConfig.settlement_speed = "fast"
	GameConfig.opening_animation_speed = "fast"
	_auto_test_online_ai = null
	print("[auto-test] start rounds=", _auto_test_rounds)
	new_game()

func _auto_test_poll_online() -> void:
	if round == null or (_auto_test_rounds <= 0 and not _ai_proxy_active):
		return
	if round.phase == RoundState.Phase.SETTLED:
		var settled_round := int(_net_node().round_number) if _net_node() != null else 0
		if _ai_proxy_active and _auto_test_rounds <= 0:
			if _auto_test_settled_round != settled_round:
				_auto_test_settled_round = settled_round
				_auto_test_prompt_seen = -1
				if _net_node() != null:
					_net_node().next_round()
			return
		if _auto_test_settled_round != settled_round:
			_auto_test_settled_round = settled_round
			_auto_test_prompt_seen = -1
			_auto_test_completed += 1
			print("[auto-test] round=%d fps=%.1f nodes=%d static_mb=%.1f mode=online" % [
				_auto_test_completed,
				Performance.get_monitor(Performance.TIME_FPS),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				float(OS.get_static_memory_usage()) / (1024.0 * 1024.0),
			])
			if _auto_test_completed >= _auto_test_rounds:
				print("[auto-test] done rounds=", _auto_test_completed)
				_auto_test_rounds = 0
				_auto_test_online_ai = null
			else:
				get_tree().create_timer(0.15).timeout.connect(_auto_test_next)
		return
	if round.phase != RoundState.Phase.PLAYING:
		return
	if not round._awaiting_response.is_empty():
		var response_seat := int(round._awaiting_response.get("seat", -1))
		if response_seat == human_seat and _auto_test_prompt_seen != round.prompt_id:
			_auto_test_prompt_seen = round.prompt_id
			_auto_test_online_response(response_seat, int(round._awaiting_response.get("disc_seat", -1)),
				str(round._awaiting_response.get("tile", "")), round.legal_response_options(response_seat,
					int(round._awaiting_response.get("disc_seat", -1)), str(round._awaiting_response.get("tile", "")),
					int(round._awaiting_response.get("stage", RoundState.ResponseStage.NONE))))
	elif round.awaiting and round.current_turn == human_seat and _auto_test_prompt_seen != round.prompt_id:
		_auto_test_prompt_seen = round.prompt_id
		_auto_test_online_turn(human_seat)

func toggle_ai_proxy() -> void:
	if _net_mode() == "":
		return
	_ai_proxy_active = not _ai_proxy_active
	if _ai_proxy_active:
		var level: String = {"weak": "low", "medium": "medium", "strong": "high"}.get(GameConfig.ai_strength, "medium")
		_ai_proxy_ai = AiPlayer.new("AI代打", level)
		_ai_proxy_worker = load("res://scripts/core/AiTurnWorker.gd").new()
		_ai_proxy_task = 0
		_ai_proxy_response_pending = false
		_auto_test_prompt_seen = -1
		_auto_test_settled_round = -1
	else:
		_ai_proxy_ai = null
		if _ai_proxy_worker != null:
			var tree := get_tree()
			if tree != null:
				_ai_proxy_worker.stop_async(tree)
			_ai_proxy_worker = null
		_ai_proxy_task = 0
	_refresh_ai_proxy_button()

func _refresh_ai_proxy_button() -> void:
	if _ai_proxy_button == null:
		return
	_ai_proxy_button.text = "AI代打 开" if _ai_proxy_active else "AI代打"
	_ai_proxy_button.tooltip_text = "点击关闭 AI 代打" if _ai_proxy_active else "AI 代替你操作当前座位"

func _submitted_proxy_level() -> String:
	return {"weak": "low", "medium": "medium", "strong": "high"}.get(GameConfig.ai_strength, "medium")

func _poll_ai_proxy() -> void:
	if _ai_proxy_task <= 0 or _ai_proxy_worker == null:
		return
	var decision: Dictionary = _ai_proxy_worker.take_result(_ai_proxy_task)
	if decision.is_empty():
		return
	_ai_proxy_task = 0
	if _ai_proxy_response_pending:
		var tile := _ai_proxy_response_tile
		_ai_proxy_response_pending = false
		_ai_proxy_response_tile = ""
		_emit_response(tile, decision)
	else:
		_emit_turn(decision)

func _auto_test_online_turn(seat: int) -> void:
	if round == null:
		return
	if _ai_proxy_active and _ai_proxy_worker != null:
		if _ai_proxy_task > 0:
			_ai_proxy_worker.cancel(_ai_proxy_task)
		_ai_proxy_response_pending = false
		_ai_proxy_task = int(_ai_proxy_worker.submit_turn(round, seat, _submitted_proxy_level()))
		return
	var options: Dictionary = round.legal_turn_options(seat)
	if options.get("self_win", false):
		_emit_turn({"self_win": true})
		return
	var player: PlayerState = round.players[seat]
	var tile := str(player.just_drew)
	if not options.get("discards", []).has(tile):
		if options.get("discards", []).is_empty():
			if _auto_test_online_ai != null:
				_emit_turn(_auto_test_online_ai.decide_turn(round, seat))
			return
		tile = str(options.discards[0])
	_emit_turn({"discard": tile})

func _auto_test_online_response(seat: int, discarded_seat: int, tile: String, options: Dictionary) -> void:
	if _ai_proxy_active and _ai_proxy_worker != null:
		if _ai_proxy_task > 0:
			_ai_proxy_worker.cancel(_ai_proxy_task)
		_ai_proxy_response_pending = true
		_ai_proxy_response_tile = tile
		_ai_proxy_task = int(_ai_proxy_worker.submit_response(round, seat, discarded_seat, tile, options, _submitted_proxy_level()))
		return
	# Auto-play only measures the online/UI frame budget; human input is not AI work.
	_emit_response(tile, {"action": "win"} if options.get("can_win", false) else {"action": "pass"})

func new_game() -> void:
	var scores: Array = []
	var chicken_multiplier := round.next_chicken_multiplier if round != null else 1
	var next_dealer := round.next_dealer_seat if round != null else 0
	if round != null:
		for player in round.players:
			scores.append(player.score)
		round.cancel_opening()
	_clear_actions()
	_settlement_animation_controller.reset()
	_settlement_card.hide_post_settlement_controls()
	_settlement_immediate = false
	_declaring_ready = false
	_selected_tile = null
	_round_number += 1
	round = RoundState.new()
	round.opening_speed = GameConfig.opening_animation_speed
	if _net_mode() == "" and DisplayServer.get_name() != "headless":
		if _ai_service == null:
			_ai_service = load("res://scripts/ai/AiDecisionService.gd").new()
		round.ai_service = _ai_service
	round._recorder.auto_save = true
	_connect_audio_round()
	round.next_chicken_multiplier = chicken_multiplier
	round.next_dealer_seat = next_dealer
	round.require_turn.connect(_on_require_turn)
	round.require_response.connect(_on_require_response)
	round.round_finished.connect(_on_round_finished)
	round.state_update.connect(_queue_refresh)
	var controllers: Array = []
	var ai_level: String = {"weak": "low", "medium": "medium", "strong": "high"}.get(GameConfig.ai_strength, "low")
	for seat in 4:
		var table_ai := AiPlayer.new("AI%d" % seat, ai_level) if _auto_test_rounds > 0 or seat != human_seat else null
		controllers.append(table_ai)
	round.controllers = controllers
	round.ai_delay_seconds = 0.0 if _auto_test_rounds > 0 else GameConfig.ai_delay_seconds()
	round.ai_response_delay_seconds = 0.0 if _auto_test_rounds > 0 else GameConfig.ai_response_delay_seconds()
	round.opening_delay_seconds = 0.0 if _auto_test_rounds > 0 else (
		GameConfig.OPENING_WAIT_SECONDS * GameConfig.opening_animation_scale() \
		if DisplayServer.get_name() != "headless" else 0.0)
	round.randomize_seed()
	# 先带入累计分数，再让新庄家开始行动（AI 庄家也可能马上结算）。
	if scores.size() == 4:
		round.build_players(human_seat)
		round.apply_scores(scores)
	round.start_round(human_seat)
	_refresh()

func _setup_host_view() -> void:
	var network = _net_node()
	human_seat = network.my_seat
	round = network.game
	_connect_audio_round()
	_round_number = network.round_number
	round.require_turn.connect(_on_require_turn)
	round.require_response.connect(_on_require_response)
	round.round_finished.connect(_on_round_finished)
	round.state_update.connect(_queue_refresh)
	if round.phase != RoundState.Phase.IDLE:
		_prime_opening_visuals()
		_on_net_prompt(human_seat)
		_refresh()
	network.connection_error.connect(_on_connection_error)
	network.lobby_updated.connect(_on_net_lobby_updated)

func _setup_client_view() -> void:
	var network = _net_node()
	round = network.game
	_connect_audio_round()
	_round_number = network.round_number
	_awaiting_rejoin_snapshot = round.phase == RoundState.Phase.IDLE
	network.room_ready.connect(func(seat):
		human_seat = seat
		if _awaiting_rejoin_snapshot:
			if _connection_overlay != null: _connection_overlay.show_syncing()
		elif _connection_overlay != null:
			_connection_overlay.close()
		_refresh())
	network.state_updated.connect(_on_client_state_updated)
	network.prompted.connect(_on_net_prompt)
	network.connection_error.connect(_on_connection_error)
	network.reconnecting.connect(func(attempt, maximum):
		_awaiting_rejoin_snapshot = true
		_table_animation_controller.cancel()
		_settlement_animation_controller.reset()
		_settlement_card.hide_post_settlement_controls()
		round._presentation.sync_initialized = false
		_selecting = false
		_clear_actions()
		status_label.hide()
		if _connection_overlay != null: _connection_overlay.show_reconnecting(attempt, maximum))
	network.lobby_updated.connect(_on_net_lobby_updated)
	enable_net(network.submit_client_turn, network.submit_client_response)
	if network.my_seat >= 0:
		human_seat = network.my_seat
	_prime_opening_visuals()
	_refresh()
	_on_net_prompt(human_seat)

func _prime_opening_visuals() -> void:
	# The lobby may hand us the first snapshot before the table has connected.
	# Prime the opening before the first hand refresh; otherwise the final hand
	# is painted for one frame and immediately replaced by the deal animation.
	if _opening_primed or round == null: return
	if round.phase not in [RoundState.Phase.DEALING, RoundState.Phase.PLAYING] or round.players.size() != 4: return
	for player in round.players:
		if player.discard_count > 0 or not player.melds.is_empty():
			_opening_primed = true
			return
	_opening_primed = true
	for event in round.visual_events: _on_visual_event(event)

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_flush_refresh")

func _flush_refresh() -> void:
	_refresh_queued = false
	_refresh()

func _refresh() -> void:
	if round == null or _awaiting_rejoin_snapshot:
		return
	_sync_settlement_round()
	if not _landscape:
		_layout()
	if round.phase != RoundState.Phase.SETTLED:
		_settlement_card.hide_post_settlement_controls()
	elif _settlement_immediate:
		# A restored settlement is a final snapshot, including any queued play
		# visuals received before this table connected to the network.
		_table_animation_controller.cancel()
	_layout_actions()
	for seat in 4: _player_tile_areas._refresh_identity(seat)
	_prepare_exposed_layouts()
	for seat in 4:
		if _table_animation_controller.holds_seat_refresh(seat) or _table_animation_controller.sorting_active():
			# The discard target must exist immediately, but the hand and draw
			# boxes stay on their pre-discard snapshot until the animation ends.  A
			# sorting pass also owns the physical hand nodes until it completes.
			_player_tile_areas._refresh_exposed(seat)
			_player_tile_areas._refresh_discards(seat)
			continue
		_refresh_seat(seat)
	_player_tile_areas.refresh_ready_frames()
	_refresh_center()
	_refresh_status()
	_update_interactivity()
	_table_animation_controller.refresh_masks()
	queue_redraw()
	if round.phase == RoundState.Phase.SETTLED and round.players.size() == 4 \
		and not _settlement_animation_controller.has_started() \
		and not _table_animation_controller.has_pending():
		var immediate := _settlement_immediate
		_settlement_immediate = false
		_start_settlement_animation(immediate)
	_settlement_animation_controller.apply_displays()
	_refresh_next_round_controls()

func _sync_settlement_round() -> void:
	# Clients and hosts reuse RoundState between rounds. Object identity alone
	# would leave the previous completed animation (and invisible rivers) alive.
	var number: int = _round_number if _net_mode() == "" else _net_node().round_number
	var changed := _settlement_round_id != round.get_instance_id() \
		or _settlement_session != round.audio_session \
		or _settlement_round_number != number \
		or (_settlement_phase == RoundState.Phase.SETTLED and round.phase != RoundState.Phase.SETTLED)
	if changed:
		_settlement_animation_controller.reset()
		_settlement_card.hide_post_settlement_controls()
		_seat_visual_keys.clear()
		_settlement_immediate = round.phase == RoundState.Phase.SETTLED
	elif _settlement_phase == RoundState.Phase.IDLE and round.phase == RoundState.Phase.SETTLED:
		_settlement_immediate = true
	_settlement_round_id = round.get_instance_id()
	_settlement_session = round.audio_session
	_settlement_round_number = number
	_settlement_phase = round.phase

func _refresh_center() -> void:
	center_info.text = str(_sum_wall()) if not round.players.is_empty() else "--"
	var number: int = _round_number if _net_mode() == "" else _net_node().round_number
	round_label.text = "第 %02d 局    ·    %s" % [maxi(1, number), "单机对局" if _net_mode() == "" else "联机对局"]
	_table_layout.refresh_turn_indicator()
	_update_speed_buttons()

func _set_ai_speed(speed_key: String) -> void:
	var persist := _sound_settings == null or _sound_settings.persist_changes
	if _net_mode() == "":
		GameConfig.set_ai_speed(speed_key, persist)
		if round != null:
			round.ai_delay_seconds = GameConfig.ai_delay_seconds()
			round.ai_response_delay_seconds = GameConfig.ai_response_delay_seconds()
	elif _net_node().is_room_owner():
		GameConfig.set_ai_speed(speed_key, persist)
		_net_node().set_ai_speed(speed_key)
	_update_speed_buttons()

func _update_speed_buttons() -> void:
	var selected: String = GameConfig.ai_speed if _net_mode() == "" else str(_net_node().lobby.get("ai_speed", "fast"))
	for speed_key in _speed_buttons:
		var button: Button = _speed_buttons[speed_key]
		button.modulate = UI.BUTTON_PRIMARY_HOVER if speed_key == selected else Color.WHITE
		button.disabled = _net_mode() != "" and not _net_node().is_room_owner()
		button.tooltip_text = "联机房间人机速度由房主设置" if button.disabled else ""

func _sum_wall() -> int:
	var count := 0
	for seat in 4:
		count += _wall_remain(seat)
	return count

func _wall_remain(seat: int) -> int:
	if round != null and round.wall != null:
		return round.wall.wall_remaining(seat)
	return int(round.wall_remain.get(seat, 0)) if round != null else 0

func _seat_name(seat: int) -> String:
	if seat < 0 or seat > 3:
		return "-"
	if _net_mode() != "" and round != null and seat < round.players.size():
		var player_name := str(round.players[seat].name_label).strip_edges()
		if player_name != "": return player_name
	return ["你", "下家", "对家", "上家"][_relative_seat(seat)]

func _refresh_status() -> void:
	if _ai_assist_enabled and _ai_teach_message != "":
		status_label.text = _ai_teach_message
		status_label.show()
		return
	status_label.text = ""
	status_label.hide()

func _on_client_state_updated() -> void:
	# 普通快照保留正在播放的视觉队列；重连回调单独清理并跳过历史。
	if _awaiting_rejoin_snapshot:
		_settlement_immediate = round.phase == RoundState.Phase.SETTLED
		_awaiting_rejoin_snapshot = false
		if _connection_overlay != null: _connection_overlay.close()
		status_label.hide()
	_selecting = false
	_response_disc = ""
	_clear_actions()
	# The first client snapshot can arrive after the table scene is ready. Prime
	# its untouched opening before the hand refresh exposes the final deal.
	_prime_opening_visuals()
	_refresh()

func _on_net_lobby_updated() -> void:
	_update_speed_buttons()
	_refresh_next_round_controls()
	var net = _net_node()
	if net != null and bool(net.test_mode) != _test_mode_ui:
		_test_mode_ui = bool(net.test_mode)
		_layout()

	if net != null and net.lobby is Dictionary and net.lobby.has("return_vote"):
		_on_return_vote_updated(net.lobby.get("return_vote", {}))
	_refresh_test_pattern_ui()

func _on_net_prompt(seat: int) -> void:
	if seat != human_seat or seat >= round.players.size():
		return
	var response: Dictionary = round._awaiting_response
	if not response.is_empty():
		if int(response.get("seat", -1)) == human_seat:
			var tile: String = response.tile
			var options := round.legal_response_options(seat, int(response.get("disc_seat", -1)), tile, int(response.get("stage", RoundState.ResponseStage.NONE)))
			_on_require_response(seat, response.disc_seat, tile, options)
	elif round.awaiting and round._awaiting_response.is_empty() \
		and round.current_turn == human_seat and round.phase == RoundState.Phase.PLAYING \
		and str(round.allowed_actions(seat).get("kind", "")) == "turn":
		_on_require_turn(seat)
	_update_interactivity()

func _on_round_finished(_result: Dictionary) -> void:
	_clear_ai_teach()
	_selecting = false
	_response_disc = ""
	_clear_actions()
	_refresh()
	if _auto_test_rounds > 0 and _net_mode() == "":
		_auto_test_prompt_seen = -1
		_auto_test_completed += 1
		print("[auto-test] round=%d fps=%.1f nodes=%d static_mb=%.1f mode=%s" % [
			_auto_test_completed,
			Performance.get_monitor(Performance.TIME_FPS),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			float(OS.get_static_memory_usage()) / (1024.0 * 1024.0),
			"online" if _net_mode() != "" else "offline",
		])
		if _auto_test_completed < _auto_test_rounds:
			get_tree().create_timer(0.15).timeout.connect(_auto_test_next)
		else:
			print("[auto-test] done rounds=", _auto_test_completed)
			_auto_test_rounds = 0
			_auto_test_completed = 0
			_auto_test_online_ai = null

func _auto_test_next() -> void:
	if _auto_test_rounds > 0 and is_inside_tree():
		if _net_mode() != "":
			var net = _net_node()
			if net != null:
				net.next_round()
		else:
			new_game()

func _on_connection_error(message: String) -> void:
	_selecting = false
	_clear_actions()
	status_label.hide()
	if _connection_overlay != null:
		_connection_overlay.show_error(message)

func _retry_connection() -> void:
	var net = _net_node()
	if net == null or not net.retry_connection():
		if _connection_overlay != null:
			_connection_overlay.show_error("当前没有可恢复的原房间，请返回大厅重新加入。")
		return
	if _connection_overlay != null:
		_connection_overlay.show_reconnecting(0, 5)

func _on_input_focus_changed() -> void:
	# Windows may omit the release when Alt-Tab interrupts a click. With
	# emulate_touch_from_mouse enabled, that also leaves a held touch index
	# which suppresses the next mouse AND touch press. Drop only the gesture;
	# preserve prompts, ready selection, and authoritative animation locks.
	_table_actions._reset_press()
	_last_tile_input_ms = -1000
	if is_node_ready(): _update_interactivity()

func _notification(what: int) -> void:
	if GameConfig.debug_enabled and what in [NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_PAUSED,
		NOTIFICATION_APPLICATION_RESUMED]:
		print("[debug] GameTable notification=", what, " turn=", human_seat,
			" selecting=", _selecting, " locked=", _table_actions != null and _table_actions.input_locked())
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN,
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		_on_input_focus_changed()
	if what == NOTIFICATION_APPLICATION_RESUMED and not _quitting and round != null:
		# Android can lose the pressed-touch/UI prompt while backgrounded.
		# Re-arm the current authoritative prompt after returning to foreground,
		# then safely skip any animation that did not resume within a short
		# grace period (Tweens may be frozen while the process is stopped).
		call_deferred("_on_net_prompt", human_seat)
		_resume_generation += 1
		_arm_resume_animation_recovery(_resume_generation)
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _sound_settings != null and _sound_settings.is_open():
			_sound_settings.close()
		else:
			_confirm_quit()

func _arm_resume_animation_recovery(generation: int) -> void:
	await get_tree().create_timer(0.45).timeout
	if generation != _resume_generation or _quitting or round == null:
		return
	if _awaiting_rejoin_snapshot:
		return
	if _table_animation_controller.input_locked():
		_table_animation_controller.cancel()
		_refresh()
		_on_net_prompt(human_seat)
		_update_interactivity()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _sound_settings.is_open(): _sound_settings.close()
		else: _confirm_quit()
		get_viewport().set_input_as_handled()

func _on_quit(forget_connection: bool = true) -> void:
	if _quitting: return
	_quitting = true
	if round != null: round.export_replay()
	quit_to_menu.emit()
	if _net_mode() != "":
		if forget_connection: await Network.leave_room()
		else: Network.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _export_current_replay() -> void:
	_sound_settings.export_replay(round, human_seat)

func _confirm_quit() -> void:
	_sound_settings.confirm_exit()

