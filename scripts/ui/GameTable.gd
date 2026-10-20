extends "res://scripts/ui/table/TableViewBridge.gd"

signal quit_to_menu

## 牌局与联机事件协调器。视觉状态由 table/ 组件持有。
## TableViewBridge 保留既有联机和测试接口；视觉参数统一在 TableUiConfig。

var round: RoundState
var human_seat := 0
var net_submit_turn: Callable
var net_submit_response: Callable
var _round_number := 0
var _connection_dialog: AcceptDialog
var _speed_buttons := {}
var _sound_settings: SoundSettings
var _audio_round: RoundState
var _sound_button: Button
var _settings_button: Button
var _voice_button: Button
var _settlement_round_id := 0
var _settlement_session := ""
var _settlement_round_number := -1
var _settlement_phase := -1
var _settlement_immediate := false
var _awaiting_rejoin_snapshot := false
var _quitting := false
var _opening_primed := false
var _ai_service = null
var _voice_diag_label: Label
var _voice_diag_token := 0

func _ready() -> void:
	AudioManager.begin_table(self)
	_build_static_ui()
	_build_voice_diag()
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
	_refresh_voice_button()

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

func _build_voice_diag() -> void:
	_voice_diag_label = Label.new()
	_voice_diag_label.name = "VoiceDiagnostic"
	_voice_diag_label.position = Vector2(24, 92)
	_voice_diag_label.size = Vector2(1040, 90)
	_voice_diag_label.add_theme_font_override("font", TileView._font())
	_voice_diag_label.add_theme_font_size_override("font_size", 22)
	_voice_diag_label.add_theme_color_override("font_color", Color("#ffe6a8"))
	_voice_diag_label.add_theme_color_override("font_outline_color", Color("#102018"))
	_voice_diag_label.add_theme_constant_override("outline_size", 5)
	_voice_diag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_diag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voice_diag_label.z_index = 100
	add_child(_voice_diag_label)
	_voice_diag_label.hide()

func _on_voice_status(_enabled: bool, message: String) -> void:
	if _voice_button != null and message != "":
		_voice_button.tooltip_text = message
	# Update the button before awaiting the diagnostic timer. Otherwise the
	# coroutine suspends here and the button text stays "麦克风 关" for 10s.
	_refresh_voice_button()
	if _voice_diag_label != null and message != "":
		_voice_diag_token += 1
		var token := _voice_diag_token
		_voice_diag_label.text = "语音：%s" % message
		_voice_diag_label.show()
		await get_tree().create_timer(10.0).timeout
		if token == _voice_diag_token:
			_voice_diag_label.hide()

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
	if round != null:
		round.poll_ai()

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
	round.state_update.connect(_refresh)
	var controllers: Array = []
	for seat in 4:
		controllers.append(null if seat == human_seat else AiPlayer.new("AI%d" % seat))
	round.controllers = controllers
	round.ai_delay_seconds = GameConfig.ai_delay_seconds()
	round.ai_response_delay_seconds = GameConfig.ai_response_delay_seconds()
	round.opening_delay_seconds = GameConfig.animation_duration(GameConfig.OPENING_WAIT_SECONDS) if DisplayServer.get_name() != "headless" else 0.0
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
	round.state_update.connect(_refresh)
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
		status_label.text = "连接中断，正在重连（%d/%d）…" % [attempt, maximum]
		status_label.show())
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
	_refresh_walls()
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
	status_label.text = ""
	status_label.hide()

func _on_client_state_updated() -> void:
	# 普通快照保留正在播放的视觉队列；重连回调单独清理并跳过历史。
	if _awaiting_rejoin_snapshot:
		_settlement_immediate = round.phase == RoundState.Phase.SETTLED
		_awaiting_rejoin_snapshot = false
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

func _on_net_prompt(seat: int) -> void:
	if seat != human_seat or seat >= round.players.size():
		return
	var response: Dictionary = round._awaiting_response
	if not response.is_empty():
		if int(response.get("seat", -1)) == human_seat:
			var tile: String = response.tile
			var options := round.legal_response_options(seat, int(response.get("disc_seat", -1)), tile, int(response.get("stage", RoundState.ResponseStage.NONE)))
			_on_require_response(seat, response.disc_seat, tile, options)
	elif round.current_turn == human_seat and round.phase == RoundState.Phase.PLAYING:
		_on_require_turn(seat)
	_update_interactivity()

func _on_round_finished(_result: Dictionary) -> void:
	_selecting = false
	_response_disc = ""
	_clear_actions()
	_refresh()

func _on_connection_error(message: String) -> void:
	_selecting = false
	_clear_actions()
	_connection_dialog = AcceptDialog.new()
	_connection_dialog.dialog_text = message
	_connection_dialog.title = "联机"
	_connection_dialog.confirmed.connect(func(): _on_quit(false))
	add_child(_connection_dialog)
	_connection_dialog.popup_centered()

func _on_input_focus_changed() -> void:
	# Windows may omit the release when Alt-Tab interrupts a click. With
	# emulate_touch_from_mouse enabled, that also leaves a held touch index
	# which suppresses the next mouse AND touch press. Drop only the gesture;
	# preserve prompts, ready selection, and authoritative animation locks.
	_table_actions._reset_press()
	_last_tile_input_ms = -1000
	if is_node_ready(): _update_interactivity()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN,
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		_on_input_focus_changed()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _sound_settings != null and _sound_settings.is_open():
			_sound_settings.close()
		else:
			_confirm_quit()

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
