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

func _ready() -> void:
	AudioManager.begin_table(self)
	_build_static_ui()
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
	AudioManager.reset_round(round.audio_session, round.audio_event_id)
	_table_animation_controller.reset()
	_last_tile_input_ms = -1000
	round.audio_event.connect(_on_audio_event)
	if not round.visual_event.is_connected(_on_visual_event):
		round.visual_event.connect(_on_visual_event)

func _on_audio_event(event: Dictionary) -> void:
	AudioManager.play_event(event)

func _exit_tree() -> void:
	if round != null and _net_mode() == "": round.cancel_opening()
	if _audio_round != null and _audio_round.audio_event.is_connected(_on_audio_event):
		_audio_round.audio_event.disconnect(_on_audio_event)
	if _audio_round != null and _audio_round.visual_event.is_connected(_on_visual_event):
		_audio_round.visual_event.disconnect(_on_visual_event)
	_audio_round = null
	_table_animation_controller.cancel()
	AudioManager.end_table(self)

func _net_mode() -> String:
	var network := get_node_or_null("/root/Network")
	return network.mode if network != null else ""

func _net_node():
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
	_result_shown = false
	_declaring_ready = false
	_selected_tile = null
	if result_layer != null:
		result_layer.hide()
	if _result_restore != null and is_instance_valid(_result_restore):
		_result_restore.hide()
	_round_number += 1
	round = RoundState.new()
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
	round.opening_delay_seconds = GameConfig.OPENING_WAIT_SECONDS if DisplayServer.get_name() != "headless" else 0.0
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
		_on_net_prompt(human_seat)
		_refresh()
	network.connection_error.connect(_on_connection_error)
	network.lobby_updated.connect(_on_net_lobby_updated)
	_prime_opening_visuals()

func _setup_client_view() -> void:
	var network = _net_node()
	round = network.game
	_connect_audio_round()
	_round_number = 1
	network.room_ready.connect(func(seat):
		human_seat = seat
		_refresh())
	network.state_updated.connect(_on_client_state_updated)
	network.prompted.connect(_on_net_prompt)
	network.connection_error.connect(_on_connection_error)
	network.reconnecting.connect(func(attempt, maximum):
		_table_animation_controller.cancel()
		round._presentation.sync_initialized = false
		_selecting = false
		_clear_actions()
		status_label.text = "连接中断，正在重连（%d/%d）…" % [attempt, maximum]
		status_label.show())
	network.lobby_updated.connect(_on_net_lobby_updated)
	enable_net(network.submit_client_turn, network.submit_client_response)
	if network.my_seat >= 0:
		human_seat = network.my_seat
	_refresh()
	_on_net_prompt(human_seat)
	_prime_opening_visuals()

func _prime_opening_visuals() -> void:
	# The lobby may hand us the first snapshot before the table has connected.
	# Only replay an untouched opening; live reconnects retain their baseline.
	if round == null or round.phase not in [RoundState.Phase.DEALING, RoundState.Phase.PLAYING] or round.players.size() != 4: return
	for player in round.players:
		if player.discard_count > 0 or not player.melds.is_empty(): return
	for event in round.visual_events: _on_visual_event(event)

func _refresh() -> void:
	if round == null:
		return
	if not _landscape:
		_layout()
	if round.phase != RoundState.Phase.SETTLED:
		_result_shown = false
		result_layer.hide()
		if _result_restore != null and is_instance_valid(_result_restore):
			_result_restore.hide()
		# 新一局开始前把结算层的状态复位，避免遮罩残留挡住牌桌。
		result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_actions()
	for seat in 4: _player_tile_areas._refresh_identity(seat)
	_prepare_exposed_layouts()
	for seat in 4:
		_refresh_seat(seat)
	_refresh_walls()
	_refresh_center()
	_refresh_status()
	_update_interactivity()
	_table_animation_controller.refresh_masks()
	queue_redraw()
	if round.phase == RoundState.Phase.SETTLED and not _result_shown and not _animation_busy and _animation_queue.is_empty():
		_result_shown = true
		_show_result.call_deferred()

func _refresh_center() -> void:
	center_info.text = str(_sum_wall()) if not round.players.is_empty() else "--"
	var number: int = _round_number if _net_mode() == "" else _net_node().round_number
	round_label.text = "第 %02d 局    ·    %s" % [maxi(1, number), "单机对局" if _net_mode() == "" else "联机对局"]
	_table_layout.refresh_turn_indicator()
	_update_speed_buttons()

func _set_ai_speed(speed_key: String) -> void:
	if _net_mode() == "":
		GameConfig.set_ai_speed(speed_key)
		if round != null: round.ai_delay_seconds = GameConfig.ai_delay_seconds()
	elif _net_node().is_room_owner():
		GameConfig.set_ai_speed(speed_key)
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
	_selecting = false
	_response_disc = ""
	_clear_actions()
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
	_connection_dialog.confirmed.connect(_on_quit)
	add_child(_connection_dialog)
	_connection_dialog.popup_centered()

func _notification(what: int) -> void:
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

func _on_quit() -> void:
	if round != null: round.export_replay()
	quit_to_menu.emit()
	if _net_mode() != "":
		Network.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _export_current_replay() -> void:
	var path := round.export_replay() if round != null else ""
	_sound_settings.replay_status.text = "已保存到本机对局记录目录" if path != "" else "完整记录保存在房主或服务器上"

func _confirm_quit() -> void:
	_sound_settings.confirm_exit()
