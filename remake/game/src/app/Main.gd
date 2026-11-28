extends Control

const MainLobbyBuilder := preload("res://src/app/MainLobbyBuilder.gd")
const LeaveConfirmOverlay := preload("res://src/app/LeaveConfirmOverlay.gd")
const UpdateManager := preload("res://src/app/UpdateManager.gd")
const UpdateDialog := preload("res://src/app/UpdateDialog.gd")
const UI := preload("res://src/app/AppTheme.gd")
const AppBackdrop := preload("res://src/app/AppBackdrop.gd")
const CharacterArt := preload("res://src/app/CharacterArt.gd")
const ReconnectOverlay := preload("res://src/app/ReconnectOverlay.gd")
const Preferences := preload("res://src/app/AppSettings.gd")
const SettingsPanel := preload("res://src/app/SettingsPanel.gd")
const ProfileSetup := preload("res://src/app/ProfileSetup.gd")
const PlayerBadge := preload("res://src/app/PlayerBadge.gd")
const TableActionButton := preload("res://src/app/TableActionButton.gd")
const WinFeedback := preload("res://src/app/WinFeedback.gd")
const FlipChickenReveal := preload("res://src/app/FlipChickenReveal.gd")
const ActionEffectsStage := preload("res://src/app/ActionEffectsStage.gd")
const TingAssistantOverlay := preload("res://src/app/TingAssistantOverlay.gd")
const StatusTelemetryBar := preload("res://src/app/StatusTelemetryBar.gd")
const PlayerProgress := preload("res://src/app/PlayerProgress.gd")
const CareerPanel := preload("res://src/app/CareerPanel.gd")
const TitleTile := preload("res://src/app/TitleTile.gd")
const Seats := preload("res://src/domain/Seats.gd")
const TurnClockView := preload("res://src/app/TurnClockView.gd")
const SettlementView := preload("res://src/app/SettlementView.gd")
const SettlementNames := preload("res://src/app/SettlementNames.gd")
const HandOrder := preload("res://src/presentation/HandOrder.gd")
const HandArrangement := preload("res://src/presentation/HandArrangement.gd")
const HandSortController := preload("res://src/presentation/HandSortController.gd")
const HandSort := preload("res://src/presentation/HandSort.gd")
const HudLayout := preload("res://src/presentation/HudLayout.gd")
const PageLayout := preload("res://src/presentation/PageLayout.gd")
const SettlementPlacement := preload("res://src/presentation/SettlementPlacement.gd")
const Room := preload("res://src/session/RoomSession.gd")
const Dice := preload("res://src/runtime/DiceRoll.gd")
const GameClient := preload("res://src/network/GameClient.gd")
const LanDiscovery := preload("res://src/network/LanDiscovery.gd")
const RoomDirectory := preload("res://src/network/RoomDirectory.gd")
const RoomBrowser := preload("res://src/app/RoomBrowser.gd")
const TableTransition := preload("res://src/presentation/TableTransition.gd")
const TableView := preload("res://src/presentation/TableView.gd")
const TileArt := preload("res://src/presentation/TileArt.gd")
const VoiceController := preload("res://src/audio/VoiceController.gd")
const SoundStage := preload("res://src/audio/SoundStage.gd")
const TeachingController := preload("res://src/ai/TeachingController.gd")
const WINDS := ["东", "南", "西", "北"]
const MODE_NAMES := {"solo": "单机", "lan": "局域网", "online": "在线"}
const RECOVERY_RETRY_SECONDS := [1.0, 3.0]
const ACTION_NAMES := {
	"discard": "出牌", "ready": "报听", "concealed_kong": "暗杠", "add_kong": "加杠",
	"self_win": "自摸", "win": "胡", "pong": "碰", "kong": "杠", "pass": "过",
}
const ACTION_ORDER := ["pong","kong","concealed_kong","add_kong","ready","self_win","win","pass"]
const HIDDEN_HUD := ["teaching","notice","advice","arrangement"]
var _client: GameClient
var _discovery: LanDiscovery
var _directory: RoomDirectory
var _update_manager: UpdateManager
var _update_dialog: UpdateDialog
var _lobby_update_button: Button
var _startup_update_prompted := false
var _voice: VoiceController
var _sound: SoundStage
var _teaching: TeachingController
var _teaching_enabled := false
var _table: TableView
var _dice: Dice
var _settings: Preferences
var _progress: PlayerProgress
var _before_career := "connect"
var _before_profile := "connect"
var _last_back_ms := 0
var _order := HandOrder.new()
var _arrangement := HandArrangement.new()
var _hud_controls := {}
var _page_key := ""
var _page_controls := {}
var _page_panel: PanelContainer
var _page_content: VBoxContainer
var _page_width := 680.0
var _modal_page_key:=""
var _modal_page_controls:={}
var _restore_button: Button
var _hud_layout_queued := false
var _sorter: HandSortController
var _sort_button: Button
var _sort_status: Label
var _sort_plans := []
var _sort_index := -1
var _sort_scope_cache := {}
var _sort_busy := false
var _sort_wait_ack := false
var _sort_decline_prompt := -1
var _sort_decline_ready := false
var _restore_scope := {}
var _auto_quality_done := false
var _auto_quality_samples: Array[float] = []
var _auto_quality_timer: Timer
var _screen := "home"
var table_layout_review:=OS.get_cmdline_user_args().has("--table-layout-review")
var table_play_only:bool=OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--table-play")
var _mode := "solo"
var _view := {}
var _round_projection := {}
var _clock := {}
var _result_seen := ""
var _before_settings := "home"
var _settings_shade: ColorRect
var _settings_exit: Control
var _settings_draft := {}
var _room_settings_panel: SettingsPanel
var _profile_setup: ProfileSetup
var _settlement_names: SettlementNames
var _next_round_button: Button
var _peek_return_button: Button
var _settlement_peeking := false
var _settlement_area := Rect2()
var _leave_overlay: Control
var _leave_focus: Control
var _board_mouse_filter := Control.MOUSE_FILTER_STOP
var _keyboard_height := 0
var _restoring := false
enum TableRecovery { NONE, RETRYING, CLOSED }
var _table_recovery := TableRecovery.NONE
var _live_ticket := {}
var _recovery_ticket := {}
var _recovery_retries := 0
var _recovery_timer := Timer.new()
var _application_paused := false
var _foreground_shade: ReconnectOverlay
var _leaving := false
var _status_text := ""
var _tile_action := ""
var _action_key := {}
var _insert_plan := {}
var _layout_warning := ""
var _restore_display_next := false
var _published_display := []
var _drag_position := []
var _published_motion_at := -50
var _last_drag_sound_ms := 0
var _last_drag_sound_slot := -1
var _shown_cues := {}
var _completed_presentation := {}
var _backdrop: Control
var _board: SubViewportContainer
var _board_world: SubViewport
var _safe: Control
var _frame: CenterContainer
var _hud: Control
var _status: Label
var _table_message: Label
var _timer: Label
var _clock_face: TurnClockView
var _wall_pill: PanelContainer
var _wall_count_label: Label
var _navigation: HBoxContainer
var _teaching_button: Button
var _auto_play_button: Button
var _auto_play_banner: Button
var _auto_play_style_active := false
var _teaching_status: Label
var _voice_status_text := ""
var _last_voice_toast := ""
var _speaker_error := ""
var _buttons: HBoxContainer
var _win_feedback: WinFeedback
var _flip_reveal: FlipChickenReveal
var _pending_settlement_key := ""
var _fx_stage: ActionEffectsStage
var _ting_overlay: TingAssistantOverlay
var _telemetry_bar: StatusTelemetryBar
var _chicken_reveal_tween: Tween
var _identities: Array[PlayerBadge] = []
var _seat_choices: Array[Button] = []
var _room_name: Label
var _ready_button: Button
var _record_button: Button
var _record_status: Label
var _room_number: LineEdit
var _discard_seconds: SpinBox
var _response_seconds: SpinBox
var _lan_name: LineEdit
var _lan_filter: LineEdit
var _lan_results: RoomBrowser
var _lan_address: LineEdit
var _lan_options: MainLobbyBuilder.Drawer
var _room_inspector: GameClient
var _transition: TableTransition
var _board_fade_from := 0.0
var _hud_fade: Tween
var _directory_url: LineEdit
var _online_name: LineEdit
var _online_filter: LineEdit
var _online_results: RoomBrowser
var _online_options: MainLobbyBuilder.Drawer
var _lobby_home: CenterContainer
var _lobby_tools: HBoxContainer
var _online_count: Label
var _join_dialog: MainLobbyBuilder.JoinDialog
var _closing_leave: Control
var _lobby_preference := ""
var _lobby_backdrop: Control
var _entry_origin := {}
var _online_rooms: Array = []


func _ready() -> void:
	get_tree().auto_accept_quit = false
	theme = UI.build()
	if _settings == null:
		_settings = Preferences.new()
	if _progress == null:
		_progress = PlayerProgress.new(_settings._path.get_base_dir().path_join("dongxiu-career-v1.cfg"))
	_transition = TableTransition.new()
	add_child(_transition)
	_transition.finished.connect(_transition_finished)
	_transition.crossfade_progress.connect(_fade_board)
	_order.set_suit_order(_settings.profile().suit_order)
	_teaching_enabled = _settings.profile().get("teaching_enabled", false)
	_setup_services()
	_setup_sound()
	_apply_quality(_settings.profile().quality)
	_apply_power_save(_settings.profile().power_save)
	get_viewport().gui_focus_changed.connect(_keyboard_focus_changed)
	_auto_quality_timer = Timer.new()
	_auto_quality_timer.wait_time = 0.5
	_auto_quality_timer.timeout.connect(_sample_auto_quality)
	add_child(_auto_quality_timer)
	_apply_table_theme(_settings.profile())
	_backdrop = AppBackdrop.new()
	add_child(_backdrop)
	move_child(_backdrop, 0)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe = Control.new()
	_safe.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_safe)
	_safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = CenterContainer.new()
	_frame.mouse_filter = MOUSE_FILTER_IGNORE
	_safe.add_child(_frame)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hud()
	_sorter = HandSortController.new(); add_child(_sorter)
	_sorter.completed.connect(_sort_completed)
	_settlement_names = SettlementNames.new()
	_safe.add_child(_settlement_names)
	for badge in _settlement_names.badges:badge.resized.connect(_queue_hud_layout)
	_settlement_names.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settlement_names.anchor_left = 0.59
	_settlement_names.hide()
	_win_feedback = WinFeedback.new()
	_safe.add_child(_win_feedback)
	_win_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flip_reveal = FlipChickenReveal.new()
	_safe.add_child(_flip_reveal)
	_flip_reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flip_reveal.finished.connect(_flip_reveal_finished)
	_fx_stage = ActionEffectsStage.new()
	_safe.add_child(_fx_stage)
	_fx_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ting_overlay = TingAssistantOverlay.new()
	_safe.add_child(_ting_overlay)
	_ting_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_telemetry_bar = StatusTelemetryBar.new()
	_safe.add_child(_telemetry_bar)
	_foreground_shade = ReconnectOverlay.new()
	add_child(_foreground_shade)
	_foreground_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_foreground_shade.retry_requested.connect(_retry_table)
	_foreground_shade.return_requested.connect(_back_home.bind("connect"))
	_update_dialog = UpdateDialog.new()
	add_child(_update_dialog)
	_update_dialog.closed.connect(_close_update_dialog)
	_update_dialog.check_requested.connect(_update_manager.check_updates)
	_update_dialog.download_requested.connect(_update_manager.start_download)
	_update_dialog.cancel_download_requested.connect(_update_manager.cancel_download)
	_update_dialog.apply_requested.connect(_update_manager.apply_and_restart)
	_update_dialog.rollback_requested.connect(_update_manager.rollback_and_restart)
	_confirm_patch_boot.call_deferred()
	resized.connect(_fit_safe_area)
	_safe.resized.connect(_fit_profile_setup)
	_fit_safe_area()
	if _settings.profile_complete():
		_enter_home()
	else:
		_show("profile_setup")


func _setup_services() -> void:
	_update_manager = UpdateManager.new()
	add_child(_update_manager)
	_update_manager.configure(_online_url(), str(_settings.profile().get("update_manifest_url", "")))
	_update_manager.can_restart_callback = func(): return _view.is_empty() and _screen in ["home", "connect", "settings"]
	_update_manager.state_changed.connect(_update_state_changed)
	_update_manager.check_finished.connect(_update_check_finished)
	_setup_client()
	_discovery = LanDiscovery.new()
	add_child(_discovery)
	_discovery.rooms_updated.connect(_refresh_lan)
	_discovery.discovery_error.connect(_set_status)
	_directory = RoomDirectory.new()
	add_child(_directory)
	_directory.rooms_received.connect(_refresh_online)
	_directory.room_received.connect(_join_online)
	_directory.failed.connect(_directory_failed)
	_directory.room_verified.connect(_recover_online_endpoint)
	_directory.verification_failed.connect(_recovery_failed)
	_recovery_timer.one_shot = true
	_recovery_timer.timeout.connect(_recovery_timeout)
	add_child(_recovery_timer)
	_setup_teaching()
	_setup_table()

func _setup_client()->void:
	_client = GameClient.new()
	add_child(_client)
	_client.view_changed.connect(_view_changed)
	_client.status_changed.connect(_set_status)
	_client.dice_updated.connect(_dice_changed)
	_client.presentation_required.connect(_presentation_required)
	_client.session_ended.connect(_session_ended)
	_client.ticket_changed.connect(_remember_ticket)
	_client.record_submission_status.connect(_record_changed)

func _setup_teaching()->void:
	_teaching = TeachingController.new()
	add_child(_teaching)
	_teaching.recommendation_changed.connect(_receive_teaching)

func _setup_table() -> void:
	_board = SubViewportContainer.new()
	_board.stretch = true
	add_child(_board)
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_world = SubViewport.new()
	_board_world.own_world_3d = true
	_board_world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_board.add_child(_board_world)
	_board_world.size_changed.connect(func():
		if _screen == "settlement":
			_fit_settlement.call_deferred()
			_queue_hud_layout())
	_table = TableView.new()
	_board_world.add_child(_table)
	_table.tile_clicked.connect(_tile_clicked)
	_table.blank_tapped.connect(_cancel_table_selection)
	_table.wall_center_requested.connect(_center_wall)
	_table.presentation_finished.connect(_presentation_finished)
	_table.hand_stability_changed.connect(_update_hand_actions)
	_table.layout_conflict.connect(_layout_conflict)
	_table.drag_started.connect(_drag_started)
	_table.drag_slot_changed.connect(_drag_slot_changed)
	_table.drag_finished.connect(_drag_finished)
	_table.hand_drag_position.connect(_drag_moved)
	_table.swipe_discard.connect(_swipe_discard)
	_table.discard_drag_state_changed.connect(_on_discard_drag_state_changed)
	_dice = Dice.new()
	_dice.authoritative = false
	_dice.scale = Vector3.ONE * 2.25
	_board_world.add_child(_dice)
	_dice.hide()


func _setup_sound() -> void:
	_voice = VoiceController.new(_settings._path.get_base_dir().path_join("dongxiu-muted-players-v1.cfg"))
	add_child(_voice)
	_voice.bind_client(_client)
	_voice.status_changed.connect(_voice_status)
	_voice.speaker_preference_failed.connect(_speaker_preference_failed)
	_voice.name_mic_changed.connect(_refresh_identity_voice)
	_voice.speaker_changed.connect(func(_seat: int, _audible: bool):
		_speaker_error = ""
		_refresh_voice_status())
	_voice.set_directory_url(_online_url())
	_sound = SoundStage.new()
	add_child(_sound)
	_sound.dice_visual_requested.connect(_queue_dice_visual_ready)
	_sound.bind_client(_client, _voice)
	_apply_sound(_settings.profile())


func _apply_sound(profile: Dictionary) -> void:
	_sound.configure({"music_enabled": profile.music, "music_volume": profile.music_volume,
		"voice_enabled": profile.voice_enabled, "voice_volume": profile.voice_volume,
		"effects_enabled": profile.effects_enabled, "effects_volume": profile.effects_volume})
	_voice.set_gains(profile.microphone_gain, profile.speaker_gain)


func _apply_quality(value: String) -> void:
	const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
	var quality := MotionConfig.set_quality(value)
	_sound.defer_dice_until_visual_ready = DisplayServer.get_name() != "headless" and bool(MotionConfig.value("transition", "dice_audio_wait_visual", true))
	_board_world.msaa_3d = Viewport.MSAA_2X if quality == "detail" else Viewport.MSAA_DISABLED
	var targets := [_table, _backdrop, _clock_face, _buttons, _settlement_names, _fx_stage,
		_win_feedback, _flip_reveal, _ting_overlay, _online_results, _lan_results]
	targets.append_array(_identities)
	if is_instance_valid(_settlement_names):
		targets.append_array(_settlement_names.badges)
	if is_instance_valid(_buttons):
		targets.append_array(_buttons.get_children())
	if is_instance_valid(_frame):
		for child in _frame.find_children("*", "", true, false):
			if child.has_method("apply_quality") and not targets.has(child):
				targets.append(child)
	for target in targets:
		if is_instance_valid(target) and not target.is_queued_for_deletion() and target.has_method("apply_quality"):
			# RoomBrowser already updates each of its preview tables.
			if target is TableView and target != _table and target.quality == quality:
				continue
			target.apply_quality(quality)


func _apply_power_save(enabled: bool) -> void:
	Engine.max_fps = 30 if enabled else 0


func _sample_auto_quality() -> void:
	_auto_quality_samples.append(float(Engine.get_frames_per_second()))
	if _auto_quality_samples.size() >= 6:
		_auto_quality_timer.stop()
		_evaluate_auto_quality(_auto_quality_samples, OS.has_feature("mobile"))
		_auto_quality_done = true


func _evaluate_auto_quality(samples: Array, is_mobile: bool) -> bool:
	var profile := _settings.profile()
	if not is_mobile or samples.is_empty() or profile.quality != "detail" or profile.quality_manual or profile.power_save:
		return false
	var total := 0.0
	for sample in samples:
		total += float(sample)
	if total / samples.size() >= 34.0 or not _settings.update({"quality": "smooth"}):
		return false
	_apply_quality("smooth")
	_auto_quality_done = true
	if is_instance_valid(_ting_overlay):
		_ting_overlay.show_toast("帧率偏低，已自动切换至流畅画质（可在设置中调回）", 3.0)
	return true


func _apply_table_theme(profile: Dictionary) -> void:
	if is_instance_valid(_table):
		_table.apply_theme(str(profile.get("table_theme", "jade_classic")), str(profile.get("tile_back", "jade")))


func _fit_safe_area() -> void:
	var insets := Vector4(18, 14, 18, 14)
	if OS.has_feature("mobile"):
		var physical := Vector2(get_window().size)
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if physical.x > 0.0 and physical.y > 0.0 and safe.has_area():
			var scale_to_ui := size / physical
			insets.x += maxf(0.0, safe.position.x) * scale_to_ui.x
			insets.y += maxf(0.0, safe.position.y) * scale_to_ui.y
			insets.z += maxf(0.0, physical.x - safe.end.x) * scale_to_ui.x
			insets.w += maxf(0.0, physical.y - safe.end.y) * scale_to_ui.y
			insets.w = maxf(insets.w, 14.0 + _keyboard_height * scale_to_ui.y)
	_safe.offset_left = insets.x
	_safe.offset_top = insets.y
	_safe.offset_right = -insets.z
	_safe.offset_bottom = -insets.w
	if is_instance_valid(_table) and _table.has_method("set_safe_insets"):
		if (table_layout_review or table_play_only) and _screen in ["play","settlement","home","room"]: _table.set_safe_insets(insets-Vector4(14,10,14,10))
		else: _table.set_safe_insets(insets + Vector4(10, 56, 10, 20) if _screen != "settlement" else insets + _settlement_names.table_insets())
	_fit_action_buttons.call_deferred()
	if table_play_only:
		_fit_play_badges(_identities)
		if _screen=="settlement":_fit_play_badges(_settlement_names.badges)
	if _screen == "settlement":
		_fit_settlement()
	_fit_profile_setup()
	_fit_menu_panel.call_deferred()
	_queue_hud_layout()


func _show(screen: String) -> void:
	if screen == "settings" and _screen == "connect":
		var browser: RoomBrowser = _lan_results if _mode=="lan" else _online_results
		if is_instance_valid(browser) and browser.is_visible_in_tree() and is_instance_valid(browser._container):
			_lobby_backdrop = Control.new()
			_lobby_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_safe.add_child(_lobby_backdrop)
			_safe.move_child(_lobby_backdrop,0)
			_lobby_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var rect := browser._container.get_global_rect()
			browser._container.reparent(_lobby_backdrop)
			browser._container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			browser._container.position = rect.position-_safe.global_position
			browser._container.size = rect.size
	elif screen != "settings" and is_instance_valid(_lobby_backdrop):
		_lobby_backdrop.queue_free()
		_lobby_backdrop = null
	if screen!="connect" and is_instance_valid(_room_inspector):
		_room_inspector._reset()
		_room_inspector.queue_free()
		_room_inspector = null
	if is_instance_valid(_settings_exit):
		_settings_exit.hide()
		_settings_exit.queue_free()
		_settings_exit = null
	if _screen == "settings" and is_instance_valid(_settings_shade):
		if screen == "settings":
			_settings_shade.hide()
			_settings_shade.queue_free()
			_settings_shade = null
		else:
			_retire_settings_panel()
	_retire_next_round()
	if screen != "play":
		_cancel_sort()
		_sort_wait_ack = false
	_cancel_identity_presses()
	_dismiss_leave(true)
	if is_instance_valid(_closing_leave):
		_closing_leave.hide()
		_closing_leave.queue_free()
	if is_instance_valid(_join_dialog):
		_frame.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		_frame.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
		_join_dialog.hide()
		_join_dialog.queue_free()
		_join_dialog = null
	_lobby_preference = ""
	_screen = screen
	if screen != "play":
		_clear_tile_action()
		_on_discard_drag_state_changed(false, false)
		if is_instance_valid(_auto_play_banner):
			_auto_play_banner.hide()
	_page_key = ""
	_page_controls.clear()
	_page_panel = null
	_page_content = null
	if is_instance_valid(_win_feedback) and screen not in ["play","settlement"]: _win_feedback.cancel()
	if screen != "play": _cancel_flip_reveal()
	if is_instance_valid(_fx_stage) and screen != "play":
		_fx_stage.clear_all()
		if screen != "settlement":
			_cancel_chicken_reveal()
	if is_instance_valid(_ting_overlay) and screen != "play":
		_ting_overlay.clear_all()
		if is_instance_valid(_table):
			_table.set_match_highlight("")
			_table.set_hint_tile(-1)
	if screen == "play":
		_cancel_chicken_reveal()
	_profile_setup = null
	_keyboard_focus_changed(get_viewport().gui_get_focus_owner())
	if is_instance_valid(_auto_quality_timer):
		_auto_quality_timer.stop()
		if screen == "play" and OS.has_feature("mobile") and not _auto_quality_done and _settings.profile().quality == "detail" and not _settings.profile().quality_manual and not _settings.profile().power_save:
			_auto_quality_samples.clear()
			_auto_quality_timer.start()
	if OS.has_feature("mobile"):
		get_tree().quit_on_go_back = false
	if is_instance_valid(_directory) and screen != "connect":
		_directory.cancel()
	if is_instance_valid(_discovery) and _discovery.searching and (screen != "connect" or _mode != "lan"):
		_discovery.stop_search()
	for child in _frame.get_children():
		_frame.remove_child(child)
		child.queue_free()
	_status = null
	_record_button = null
	_record_status = null
	var settings_over_table := screen == "settings" and not _view.is_empty()
	var show_table := settings_over_table or screen in ["play", "settlement"] or (table_play_only and screen == "room") or (is_instance_valid(_transition) and _transition.active)
	if screen != "play" and is_instance_valid(_teaching):
		_teaching.cancel()
	_backdrop.visible = screen != "play" and not (table_play_only and show_table)
	_board.visible = show_table
	if not _transition.active:
		_board.modulate.a = 1.0
		_board_world.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if show_table else SubViewport.UPDATE_DISABLED
	_board.anchor_left = 0.0 if table_play_only else (0.59 if screen == "settlement" else 0.0)
	_frame.anchor_right = 1.0 if table_play_only else (0.59 if screen == "settlement" else 1.0)
	_frame.anchor_top=0.20 if table_play_only and screen=="settlement" else 0.0
	_frame.anchor_bottom=0.76 if table_play_only and screen=="settlement" else 1.0
	_hud.visible = screen == "play" and not table_layout_review
	if _hud.visible and not _transition.active:
		_fade_in_hud()
	_settlement_names.visible = screen == "settlement"
	if table_play_only:
		_settlement_names.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_navigation.visible=screen=="play" and not table_layout_review
	if is_instance_valid(_table):
		_table.visible = show_table
	if not show_table:
		_dice.hide()
	match screen:
		"home":
			_build_home()
		"profile_setup", "profile_edit":
			_build_profile_setup(screen == "profile_setup")
		"connect":
			_build_connection()
		"settings":
			_build_settings()
		"career":
			_build_career()
		"room":
			_table.prewarm_visuals()
			_build_room()
		"settlement":
			_build_settlement()
	if screen in ["home", "connect", "room", "career", "profile_setup", "profile_edit", "settings"]:
		if screen == "settings":
			_settings_shade = ColorRect.new()
			_settings_shade.color = Color.BLACK
			_safe.add_child(_settings_shade)
			_safe.move_child(_settings_shade, _frame.get_index())
			_settings_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			UI.MotionFX.animate_modal_in(_page_panel, _settings_shade)
			UI.MotionFX.animate_screen_in(_page_content)
		else:
			UI.MotionFX.animate_screen_in(_frame.get_child(0))
	if screen not in ["play","settlement"] and not (table_play_only and screen in ["home","room","connect"]):
		_page_key = _mode if screen=="connect" else PageLayout.canonical(screen)
		if PageLayout.PAGES.has(_page_key):
			_register_page(_frame,_page_key)
	_sync_foreground_controls()
	_sync_transition_view()
	_sync_telemetry()
	_fit_safe_area()


func _sync_telemetry() -> void:
	if not is_instance_valid(_telemetry_bar):
		return
	var active := _screen in ["play", "settlement", "room"] and not table_layout_review
	_telemetry_bar.configure(active, _telemetry_metrics)


func _telemetry_metrics() -> Dictionary:
	if is_instance_valid(_client) and _client.mode in ["lan", "online"]:
		var metrics := _client.connection_metrics()
		if _table_recovery != TableRecovery.NONE:
			metrics.state = "reconnecting"
			metrics.rtt_ms = -1
		return metrics
	if _mode in ["lan", "online"] and not _view.is_empty():
		var state := "reconnecting" if _table_recovery != TableRecovery.NONE else "disconnected"
		return {"active": true, "mode": _mode, "state": state, "rtt_ms": -1, "local_host": false}
	return {"active": false, "mode": _mode, "state": "local", "rtt_ms": -1, "local_host": false}

func _register_page(root:Control,page:String)->void:
	_page_key=page;_page_controls={}
	PageLayout.collect(root,_page_controls)
	for control in _page_controls.values():
		if not control.resized.is_connected(_queue_hud_layout):control.resized.connect(_queue_hud_layout)
	for scroll in PageLayout.scrolls(root):
		if scroll.has_meta("page_scroll_connected"):continue
		scroll.set_meta("page_scroll_connected",true)
		scroll.get_v_scroll_bar().value_changed.connect(func(_value):_queue_hud_layout())
		scroll.get_h_scroll_bar().value_changed.connect(func(_value):_queue_hud_layout())
	_queue_hud_layout()

func _register_modal(root:Control,page:String)->void:
	if _page_key==page:return
	_modal_page_key=_page_key;_modal_page_controls=_page_controls.duplicate()
	_register_page(root,page)

func _restore_modal_page()->void:
	_page_key=_modal_page_key;_page_controls=_modal_page_controls;_modal_page_controls={};_modal_page_key=""
	_queue_hud_layout()


func _panel(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	_page_panel=panel;_page_width=width
	panel.theme = MainLobbyBuilder.menu_theme()
	panel.add_theme_stylebox_override("panel", UI.elevated_card(Color("#102821f2"), 18, 22, Color("#b8954c"), 2,
		12 if UI.MotionFX.MotionConfig.value("panel", "shadow_enabled") else 0))
	_frame.add_child(panel)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_page_content=content
	content.minimum_size_changed.connect(_fit_menu_panel)
	_fit_menu_panel.call_deferred()
	return content

func _retire_settings_panel() -> void:
	_settings_exit = Control.new()
	_safe.add_child(_settings_exit)
	_settings_exit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_exit.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	_settings_exit.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_settings_shade.reparent(_settings_exit)
	_page_panel.reparent(_settings_exit)
	UI.MotionFX.animate_modal_out(_page_panel, _settings_shade, _settings_exit.queue_free)
	_settings_shade = null


func _fit_menu_panel() -> void:
	if not is_instance_valid(_page_content):
		return
	if not is_instance_valid(_page_panel):
		_page_content.get_parent().custom_minimum_size = _safe.size
		return
	var extent:=Vector2(minf(_page_width,_safe.size.x),minf(_page_content.get_combined_minimum_size().y+56,_safe.size.y))
	if not _page_panel.custom_minimum_size.is_equal_approx(extent):_page_panel.custom_minimum_size=extent
	_queue_hud_layout()


func _enter_home() -> void:
	_mode = "online"
	_show("connect")
	_restore_recent_room.call_deferred()
	_update_manager.maybe_auto_check()

func _confirm_patch_boot() -> void:
	var boot := get_node_or_null("/root/PatchBoot")
	if boot == null: return
	boot.confirm_boot()
	if not str(boot.boot_message).is_empty():
		_ting_overlay.show_toast(str(boot.boot_message))
		if _screen in ["home", "connect"]:
			_set_status(str(boot.boot_message))

func _open_update_dialog(check_now: bool = false) -> void:
	if is_instance_valid(_join_dialog) and _join_dialog.opened:
		_join_dialog.close()
	_update_manager.configure(_online_url(), str(_settings.profile().get("update_manifest_url", "")))
	_update_dialog.open_dialog(_update_manager.snapshot())
	_frame.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_frame.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	_register_modal(_update_dialog, "update")
	if check_now and _update_manager.state not in ["available", "downloading", "ready"]:
		_update_manager.check_updates()

func _close_update_dialog() -> void:
	if _update_dialog.visible:
		_update_dialog.close_dialog()
		return
	_frame.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	_frame.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	if _page_key == "update": _restore_modal_page()

func _update_state_changed(snap: Dictionary) -> void:
	if is_instance_valid(_update_dialog): _update_dialog.apply_snapshot(snap)
	if is_instance_valid(_lobby_update_button):
		var available: bool = snap.state in ["available", "ready"]
		_lobby_update_button.text = "有新版" if available else "更新"
		_lobby_update_button.theme_type_variation = "PrimaryButton" if available else ""

func _update_check_finished(has_update: bool, snap: Dictionary) -> void:
	_update_state_changed(snap)
	if has_update and snap.automatic and not _startup_update_prompted and _screen in ["home", "connect"] and _view.is_empty() and DisplayServer.get_name() != "headless":
		_startup_update_prompted = true
		_open_update_dialog()

func _online_url() -> String:
	var configured:String=_settings.profile().directory_url
	if configured.is_empty() or configured.trim_suffix("/")=="https://dongxiu.fun":
		configured=str(ProjectSettings.get_setting("dongxiu/online_directory_url",""))
	return configured.strip_edges().trim_suffix("/")

func _fit_play_badges(badges:Array) -> void:
	MainLobbyBuilder.fit_play_badges(self, badges)


func _build_profile_setup(first: bool) -> void:
	MainLobbyBuilder.build_profile_setup(self, first)

func _fit_profile_setup() -> void:
	if is_instance_valid(_profile_setup):
		_profile_setup.fit(_safe.size, _keyboard_height > 0)


func _keyboard_focus_changed(control: Control) -> void:
	set_process(OS.has_feature("mobile") and (control is LineEdit or control is TextEdit or _keyboard_height > 0))


func _process(_delta: float) -> void:
	var height := DisplayServer.virtual_keyboard_get_height()
	if height != _keyboard_height:
		_keyboard_height = height
		_fit_safe_area()
	if height == 0:
		_keyboard_focus_changed(get_viewport().gui_get_focus_owner())


func _build_home() -> void:
	MainLobbyBuilder.build_home(self)

func _open_career() -> void:
	_before_career = _screen if _screen in ["home", "connect"] else "connect"
	_show("career")

func _open_profile_from_lobby() -> void:
	_before_profile = "connect"
	_show("profile_edit")

func _build_career() -> void:
	MainLobbyBuilder.build_career(self)

func _choose_mode(mode: String) -> void:
	_entry_origin = {}
	if is_instance_valid(_room_inspector):
		_room_inspector._reset()
		_room_inspector.queue_free()
		_room_inspector = null
	_stop_room_recovery()
	_mode = mode
	_restoring = false
	_set_status("")
	if mode == "solo":
		if not _require_service():
			return
		var profile := _profile()
		if not _client.start_solo(profile, _host_settings(profile)):
			_set_status("暂时无法开始单机牌局。")
		else:
			_start_seating()
	else:
		_show("connect")


func _build_connection() -> void:
	MainLobbyBuilder.build_connection(self)

func _build_lan_lobby() -> void:
	MainLobbyBuilder.build_lan_lobby(self)

func _search_lan() -> void:
	if is_instance_valid(_discovery):
		_discovery.search()
	_refresh_lan()


func _refresh_lan() -> void:
	if _screen != "connect" or _mode != "lan" or not is_instance_valid(_lan_results): return
	var available: Array = _discovery.rooms.values() if is_instance_valid(_discovery) else []
	var filter := _lan_filter.text.strip_edges()
	_lan_results.set_rooms(available.filter(func(room):return filter.is_empty() or room.number.contains(filter) or room.name.containsn(filter)))
	if _page_key=="lan":_register_page(_frame,"lan")


func _join_lan(discovered: Dictionary) -> void:
	_inspect_endpoint(discovered)


func _entry(fields: GridContainer, label: String, hint: String) -> LineEdit:
	return MainLobbyBuilder.entry(self, fields, label, hint)

func _add_host_clocks(fields: GridContainer) -> void:
	MainLobbyBuilder.add_host_clocks(self, fields)

func _seconds_field(fields: GridContainer, title: String, seconds: int) -> SpinBox:
	return MainLobbyBuilder.seconds_field(self, fields, title, seconds)

func _room_clocks() -> Dictionary:
	var values := {"discard_seconds": int(_discard_seconds.value), "response_seconds": int(_response_seconds.value)}
	_settings.update(values)
	return {"discard_ms": values.discard_seconds * 1000, "response_ms": values.response_seconds * 1000}


func _valid_room_number(number: String) -> bool:
	if number.length() < 4 or number.length() > 8:
		return false
	for code in number.to_utf8_buffer():
		if code < 48 or code > 57:
			return false
	return true


func _host_lan() -> void:
	if not _require_service():
		return
	var number := _room_number.text.strip_edges()
	if number.is_empty():
		number = "%04d" % (randi() % 10000)
	if not _valid_room_number(number):
		_set_status("房间号须为 4–8 位数字。")
		return
	if is_instance_valid(_discovery) and _discovery.has_number(number):
		_set_status("局域网内已有同号房间。")
		return
	var profile := _profile()
	var settings := _host_settings(profile)
	settings.merge(_room_clocks())
	var name := _lan_name.text.strip_edges()
	settings.room_name = name if not name.is_empty() else profile.nickname + "麻将局"
	if not _client.host_lan(profile, number, 0, settings):
		_set_status("未能创建局域网房间。")


func _configure_directory() -> bool:
	var address := _directory_url.text.strip_edges()
	if address.is_empty():
		_set_status("请填写在线房间服务地址。")
		return false
	if not is_instance_valid(_directory) or not _directory.configure(address):
		_set_status("在线服务地址无效或暂不可用。")
		return false
	if address != _settings.profile().directory_url:
		if not _settings.update({"directory_url": address}):
			_set_status("服务地址未能保存。")
			return false
	if is_instance_valid(_voice):
		_voice.set_directory_url(address)
	return true


func _search_online() -> void:
	if _configure_directory():
		_set_status("正在读取房间列表…")
		_directory.list_rooms()


func _create_online() -> void:
	if _configure_directory():
		var profile := _profile()
		var name := _online_name.text.strip_edges()
		var number := _room_number.text.strip_edges()
		if not number.is_empty() and not _valid_room_number(number):
			_set_status("请填写 4–8 位数字房间号。")
			return
		_set_status("正在创建房间…")
		var settings := _room_clocks()
		settings.difficulty = profile.difficulty
		_directory.create_room(name if not name.is_empty() else profile.nickname + "麻将局", settings, number)


func _open_join_dialog() -> void:
	if not _room_number.text.strip_edges().is_empty():
		_find_online()
		return
	if not is_instance_valid(_join_dialog):
		_join_dialog = MainLobbyBuilder.JoinDialog.new()
		_join_dialog.theme = MainLobbyBuilder.menu_theme()
		_join_dialog.background = _frame
		_join_dialog.valid_number = _valid_room_number
		_join_dialog.submitted.connect(func(number):
			_room_number.text = number
			_find_online())
		_safe.add_child(_join_dialog)
	_join_dialog.open()


func _set_browser_visible(active: bool, manual := true) -> void:
	if manual:
		_lobby_preference = "tables" if active else ("home" if not _online_rooms.is_empty() else "")
	_lobby_home.visible = not active
	_lobby_tools.visible = active
	_online_results.visible = active
	_online_options.toggles.back().visible = not active
	if active:
		UI.MotionFX.animate_screen_in(_online_results)
		if _lobby_tools.get_child(0).get_focus_mode_with_override() != Control.FOCUS_NONE:
			_lobby_tools.get_child(0).grab_focus()
	else:
		var solo: Button = _lobby_home.find_children("*", "Button", true, false)[0]
		if solo.get_focus_mode_with_override() != Control.FOCUS_NONE:
			solo.grab_focus()


func _find_online() -> void:
	if not _configure_directory():
		return
	var number := _room_number.text.strip_edges()
	if number.is_empty():
		_open_join_dialog()
		return
	if not _valid_room_number(number):
		_set_status("请填写 4–8 位数字房间号。")
		return
	_set_status("正在查找房间…")
	_directory.find_room(number)


func _refresh_online(rooms: Array) -> void:
	if _screen not in ["home", "connect"] or _mode != "online" or not is_instance_valid(_online_results):
		return
	_online_rooms = rooms.duplicate(true)
	_online_count.text = "当前开放 %d 桌" % rooms.size()
	if rooms.is_empty() and _lobby_preference == "home":
		_lobby_preference = ""
	var browse := _lobby_preference == "tables" or (_lobby_preference != "home" and not rooms.is_empty())
	if browse != _online_results.visible:
		_set_browser_visible(browse, false)
	_draw_online_rooms()
	_set_status("")


func _draw_online_rooms() -> void:
	if not is_instance_valid(_online_results): return
	var filter := _online_filter.text.strip_edges()
	_online_results.set_rooms(_online_rooms.filter(func(room):return filter.is_empty() or room.number.contains(filter) or room.name.containsn(filter)))
	if _page_key=="online":_register_page(_frame,"online")


func _join_online(room: Dictionary) -> void:
	if _screen not in ["home", "connect"] or _mode != "online" or not _require_service(): return
	if room.has("owner_token"):
		_entry_origin = {}
		var own := room.duplicate(true)
		own.requested_seat = 1
		_join_endpoint(own)
	else: _inspect_endpoint(room)


func _select_room_seat(room: Dictionary, seat: int) -> void:
	if not _require_service(): return
	var selection := room.duplicate(true)
	var browser: RoomBrowser = _lan_results if _mode=="lan" else _online_results
	_entry_origin = browser.transition_origin(str(room.number)) if is_instance_valid(browser) else {}
	selection.requested_seat = seat
	_join_endpoint(selection)

func _inspect_lan_address() -> void:
	var address := _lan_address.text.strip_edges()
	if address.is_empty():
		_lan_options.set_expanded(true)
		_lan_address.grab_focus()
		return
	var separator := address.rfind(":")
	if separator < 1 or not address.substr(separator+1).is_valid_int():
		_set_status("请填写房主显示的地址和端口，例如192.168.1.8:7499。")
		return
	_inspect_endpoint({"host":address.left(separator),"port":int(address.substr(separator+1))})

func _inspect_endpoint(room: Dictionary) -> void:
	if not room.get("host") is String or not room.get("port") is float and not room.get("port") is int: return
	if is_instance_valid(_room_inspector):
		_room_inspector._reset()
		_room_inspector.queue_free()
	_room_inspector = GameClient.new()
	add_child(_room_inspector)
	_room_inspector.status_changed.connect(_set_status)
	_room_inspector.room_inspected.connect(_show_inspected_room)
	_room_inspector.inspect_room(room.host,int(room.port))

func _show_inspected_room(room: Dictionary) -> void:
	if _screen not in ["home", "connect"]: return
	room.room_instance_id = room.get("instance", "")
	if _mode == "online":
		_refresh_online([room])
		if not _online_results.visible:
			_set_browser_visible(true)
	else:
		_lan_results.set_rooms([room])
	_set_status("请选择空座；暂离玩家的座位不能加入。")

func _join_endpoint(room: Dictionary) -> void:
	var profile := _profile()
	profile.room_number = room.number
	if room.has("requested_seat"): profile.requested_seat = room.requested_seat
	if room.has("owner_token"): profile.owner_token = room.owner_token
	var ticket := _settings.remembered_room()
	if ticket.get("mode") != _mode or ticket.get("room_number") != room.number:
		ticket = {}
	elif room.has("room_instance_id") and room.room_instance_id != ticket.room_instance_id:
		ticket = {}
	elif not room.has("room_instance_id") and (ticket.address != room.host or ticket.port != int(room.port)):
		ticket = {}
	_restoring = not ticket.is_empty()
	if not _client.connect_room(room.host, int(room.port), profile, ticket):
		_restoring = false
		_set_status("未能连接到该房间。")


func _directory_failed(message: String) -> void:
	if _screen in ["connect","home"] and _mode == "online":
		_set_status(message)


func _profile() -> Dictionary:
	var profile := _settings.profile()
	profile.player_id = _settings.player_id()
	profile.mode = _mode
	return profile


func _host_settings(profile: Dictionary) -> Dictionary:
	var settings := {"difficulty": profile.difficulty, "external_presentation": true}
	var directory := str(profile.directory_url).strip_edges().trim_suffix("/")
	if not directory.is_empty():
		settings.record_url = directory + "/v1/records"
	return settings


func _require_service() -> bool:
	if not is_instance_valid(_client):
		_set_status("游戏服务未启动。")
		return false
	if _settings.player_id().is_empty():
		_set_status("本机玩家资料无法创建。")
		return false
	return true


func _add_status(parent: Container) -> void:
	_status = UI.label(_status_text, 17, UI.MUTED)
	_status.set_meta("page_label","页面提示")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_status)


func _set_status(message: String) -> void:
	_status_text = message
	if is_instance_valid(_status):
		_status.text = message
	elif _screen == "play" and _table_recovery == TableRecovery.NONE and not message.is_empty():
		_table_message.text = message


func _open_settings() -> void:
	if is_instance_valid(_leave_overlay) or _waiting_for_foreground():
		return
	_stop_room_recovery()
	_before_settings = _screen
	if _screen == "play":
		_cancel_table_input()
	_pause_solo(true)
	_show("settings")


func _can_edit_profile() -> bool:
	return _before_settings in ["home","connect"] and _view.is_empty()


func _build_settings() -> void:
	MainLobbyBuilder.build_settings(self)

func _sync_settings_operation()->void:
	if _screen=="settings" and is_instance_valid(_room_settings_panel):
		_room_settings_panel.show_operation_reminder(_mode!="solo" and not _waiting_for_foreground() and not _auto_play_active() and not _choices().get("actions",[]).is_empty())

func _can_edit_room_settings() -> bool:
	var room: Dictionary = _view.get("room", {})
	var seat: int = _view.get("seat", -1)
	return not room.is_empty() and seat in range(4) and room.get("owner_player_id", "") == room.seats[seat].player_id

func _sync_room_settings() -> void:
	if is_instance_valid(_room_settings_panel) and not _view.is_empty():
		_room_settings_panel.apply_room(_view.room, _can_edit_room_settings())


func _close_settings() -> void:
	_show(_before_settings)
	_pause_solo(false)
	if not _view.is_empty():
		_update_screen()
		_request_teaching()


func _pause_solo(value: bool) -> void:
	if _mode != "solo" or not is_instance_valid(_client):
		return
	value = value or _application_paused or _screen in ["settings", "profile_edit"]
	_client.set_paused(value)
	if is_instance_valid(_table):
		_table.process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(_client): await _client.leave()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		if _application_paused: return
		_application_paused = true
		if not _view.is_empty() and _mode in ["lan", "online"]:
			_cancel_table_input()
		_client.set_application_away(true)
		_sync_foreground_controls()
		_stop_room_recovery(true)
		_pause_solo(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		var wake_recovery := _application_paused
		_application_paused = false
		if _transition.active:
			_transition.finish_on_resume()
			if _hud_fade:
				_hud_fade.kill()
			_hud.modulate.a = 1.0
		_client.set_application_away(false)
		_sync_foreground_controls()
		if wake_recovery:
			_verify_recent_room()
		if _screen != "settings":
			_pause_solo(false)


func _waiting_for_foreground() -> bool:
	return _table_recovery != TableRecovery.NONE or (not _view.is_empty() and _client.waiting_for_foreground_view())


func _cancel_table_input() -> void:
	_cancel_identity_presses()
	_table._cancel_press()
	_clear_tile_action()
	_order.cancel_drag()
	_order.clear_selection()
	_drag_position = []
	if _screen == "play": _apply_order()
	# A button held before loss of input must not activate after the table reopens.
	for button: BaseButton in find_children("*", "BaseButton", true, false):
		if button.is_visible_in_tree() and not button.disabled and button.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]:
			button.disabled = true
			button.disabled = false


func _sync_foreground_controls() -> void:
	var waiting := _waiting_for_foreground()
	_foreground_shade.display(waiting, _table_recovery != TableRecovery.NONE, _table_recovery == TableRecovery.CLOSED,
		_screen in ["home", "connect"] and _view.is_empty())
	if waiting:_register_modal(_foreground_shade,"reconnect")
	elif _page_key=="reconnect":_restore_modal_page()
	_safe.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED if waiting else Control.FOCUS_BEHAVIOR_INHERITED
	var flip_active := is_instance_valid(_flip_reveal) and _flip_reveal.visible
	var table_input := _screen=="play" and not waiting and not is_instance_valid(_leave_overlay) and not _transition.active and not flip_active
	_table.set_process_input(table_input)
	_table.set_process_unhandled_input(table_input)
	if _screen == "play": _refresh_actions()
	if is_instance_valid(_telemetry_bar) and _telemetry_bar.visible:
		_telemetry_bar.refresh_now()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and _screen not in ["home", "profile_setup"]:
		get_viewport().set_input_as_handled()
		_go_back()


func _go_back() -> void:
	if is_instance_valid(_join_dialog) and _join_dialog.opened:
		_join_dialog.close()
		return
	if is_instance_valid(_update_dialog) and _update_dialog.visible:
		_close_update_dialog()
		return
	if _table_recovery != TableRecovery.NONE:
		return
	if is_instance_valid(_leave_overlay):
		_dismiss_leave()
		return
	if is_instance_valid(_flip_reveal) and _flip_reveal.visible:
		_flip_reveal.finish_now()
		return
	match _screen:
		"play": _request_leave()
		"profile_setup":
			if _keyboard_height > 0:
				DisplayServer.virtual_keyboard_hide()
			elif is_instance_valid(_profile_setup) and is_instance_valid(_profile_setup._nickname) and _profile_setup._nickname.has_focus():
				_profile_setup._nickname.release_focus()
			elif OS.has_feature("mobile"):
				var now := Time.get_ticks_msec()
				if now - _last_back_ms < 2000:
					get_tree().quit()
				else:
					_last_back_ms = now
					if is_instance_valid(_ting_overlay):
						_ting_overlay.show_toast("再按一次返回键退出游戏", 1.8)
		"profile_edit":
			if _keyboard_height > 0:
				DisplayServer.virtual_keyboard_hide()
			elif is_instance_valid(_profile_setup) and is_instance_valid(_profile_setup._nickname) and _profile_setup._nickname.has_focus():
				_profile_setup._nickname.release_focus()
			else:
				_show(_before_profile)
		"settings": _close_settings()
		"career": _show(_before_career)
		"settlement":
			if _settlement_peeking:
				_toggle_settlement_peek()
			else:
				_request_leave()
		"room": _back_home()
		"connect":
			if _mode == "lan":
				_choose_mode("online")
			elif is_instance_valid(_online_results) and _online_results.visible:
				_set_browser_visible(false)
			elif OS.has_feature("mobile"):
				var now := Time.get_ticks_msec()
				if now - _last_back_ms < 2000:
					if is_instance_valid(_client): await _client.leave()
					get_tree().quit()
				else:
					_last_back_ms = now
					if is_instance_valid(_ting_overlay):
						_ting_overlay.show_toast("再按一次返回键退出游戏", 1.8)
					else:
						_set_status("再按一次返回键退出游戏")


func _request_leave() -> void:
	if is_instance_valid(_leave_overlay):
		return
	_cancel_identity_presses()
	var room: Dictionary = _view.get("room", {})
	if not room.get("rolling", false) and int(room.get("phase", -1)) != Room.Phase.IN_ROUND:
		_back_home()
		return
	_leave_focus = get_viewport().gui_get_focus_owner()
	_order.cancel_drag()
	_drag_position = []
	_apply_order()
	_table._cancel_press()
	_table.set_process_input(false)
	_table.set_process_unhandled_input(false)
	_board_mouse_filter = _board.mouse_filter
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_build_leave_overlay()

func _build_leave_overlay()->void:
	if is_instance_valid(_closing_leave):
		_closing_leave.hide()
		_closing_leave.queue_free()
	LeaveConfirmOverlay.build(self)

func _dismiss_leave(immediate := false) -> void:
	if not is_instance_valid(_leave_overlay):
		return
	_closing_leave = _leave_overlay
	if immediate:
		_closing_leave.hide()
		_closing_leave.queue_free()
	else:
		_leave_overlay.dismiss()
	_leave_overlay = null
	if _page_key=="leave":_restore_modal_page()
	_board.mouse_filter = _board_mouse_filter
	_hud.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	_sync_foreground_controls()
	var focus_ref: WeakRef = weakref(_leave_focus) if is_instance_valid(_leave_focus) else null
	(func():
		var previous_focus: Control = focus_ref.get_ref() if focus_ref else null
		if _screen == "play" and not is_instance_valid(_leave_overlay) and is_instance_valid(previous_focus) and previous_focus.is_inside_tree() and previous_focus.is_visible_in_tree():
			if not previous_focus is BaseButton or not previous_focus.disabled:
				previous_focus.grab_focus()
	).call_deferred()
	_leave_focus = null


func _build_room() -> void:
	MainLobbyBuilder.build_room(self)

func _refresh_room() -> void:
	MainLobbyBuilder.refresh_room(self)

func _move_seat(seat: int) -> void:
	if not _client.move_to_empty_seat(seat):
		_set_status("暂时无法换座。")


func _toggle_ready() -> void:
	if _view.room.get("requires_start",false):
		if not _client.start_first_round(): _set_status("只有房主可以开始第一局。")
		return
	var ready: bool = _view.room.seats[int(_view.seat)].ready
	if not _client.set_ready(not ready):
		_set_status("无法更改准备状态。")


func _build_hud() -> void:
	MainLobbyBuilder.build_hud(self)

func _view_changed(view: Dictionary) -> void:
	if view.is_empty() or not view.has("room"):
		return
	var hot := _table_recovery != TableRecovery.NONE
	if hot:
		if _table_recovery != TableRecovery.RETRYING or not _restoring:
			return
		if _client.waiting_for_foreground_view():
			if view.get("presence", {}).get("needs_ack", false) and _recovery_timer.is_stopped():
				_recovery_timer.start(GameClient.CONNECT_TIMEOUT_MS / 1000.0)
			return
		var seat: int = view.get("seat", -1)
		if view.room.room_instance_id != _recovery_ticket.get("room_instance_id") or seat not in range(4) or view.room.seats[seat].player_id != _recovery_ticket.get("player_id"):
			return
		if int(view.room.phase) == Room.Phase.IN_ROUND and view.get("round", {}).get("viewer_seat", -1) != seat:
			return
		_table_recovery = TableRecovery.NONE
	if _view.get("room", {}).get("room_instance_id") != view.room.room_instance_id:
		_speaker_error = ""
		# Each room's authority starts numbering its visible throws from one.
		_dice.hide()
		_dice.roll_id = 0
	var entering_room: bool = _mode in ["lan","online"] and is_instance_valid(_client) and _client.mode in ["lan","online"] and not _client.ticket.is_empty() and not _restoring and _view.get("room",{}).get("room_instance_id") != view.room.room_instance_id
	_view = view.duplicate(true)
	_sync_room_settings()
	var was_waiting := _foreground_shade.waiting_for_room
	_sync_foreground_controls()
	if _waiting_for_foreground(): return
	if was_waiting:
		_restore_display_next = true
		_published_display = []
		if hot or _round_projection != view.get("round", {}):
			_table.apply_view({})
	if _auto_play_active():
		_clear_tile_action()
	if _restoring:
		_restore_display_next = true
		_recovery_timer.stop()
		_recovery_ticket.clear()
	_restoring = false
	_clock = _view.get("clock", {})
	var round_view: Dictionary = _view.get("round", {})
	var presentation: Dictionary = _view.get("presentation", {})
	if not presentation.is_empty():
		_presentation_required(presentation)
	var dice: Dictionary = _view.get("dice", {})
	if not dice.is_empty():
		_dice_changed(dice)
	if round_view != _round_projection or was_waiting:
		var prev_round := _round_projection
		var won_now: bool = round_view.get("phase") == "settled" and prev_round.get("phase", "") not in ["", "settled"] and not was_waiting
		var new_prompt: bool = round_view.get("prompt_id") != prev_round.get("prompt_id")
		_round_projection = round_view.duplicate(true)
		if not _sort_scope_cache.is_empty() and _sort_scope_cache != _sort_scope(): _cancel_sort()
		if new_prompt:
			_teaching_status.text = ""
			if _tile_action.is_empty() and is_instance_valid(_table):
				_table.set_hint_tile(-1)
		_render_table(round_view)
		if not _tile_action.is_empty():
			var choices: Dictionary = round_view.get("choices", {})
			var ids: Array = choices.get(_tile_action + "_ids", [])
			if not choices.get("actions", []).has(_tile_action) or ids.is_empty():
				_clear_tile_action()
			else:
				_table.set_hint_tiles(ids)
		_refresh_smart_assist()
		if not was_waiting and not prev_round.is_empty():
			_trigger_action_fx(prev_round, round_view)
		if won_now:
			var finish_key := str(view.room.room_instance_id) + "/" + str(view.room.round_number)
			var round_result: Dictionary = round_view.get("result", {})
			if not _view.get("settlement", {}).is_empty() and is_instance_valid(_flip_reveal) and _flip_reveal.present(finish_key, round_result, _view.room.seats):
				_pending_settlement_key = finish_key
				_cancel_table_input()
				if is_instance_valid(_hud):
					_hud.hide()
				if is_instance_valid(_ting_overlay):
					_ting_overlay.clear_all()
				_sync_foreground_controls()
			_show_win_feedback.call_deferred(round_result, finish_key)
	_update_screen()
	if _sort_wait_ack and not _choices().get("actions",[]).has("self_win"):
		_sort_wait_ack = false
		if _screen == "play" and (int(_round_projection.get("prompt_id",-1)) == _sort_decline_prompt or _sort_decline_ready): _start_sort()
	if _screen == "play":
		_request_teaching()
	_sync_settings_operation()
	if entering_room: _start_seating()
	_sync_transition_view()

func _start_seating() -> void:
	if _view.is_empty() or _transition.active or _application_paused: return
	_begin_table_transition(true)
	_cancel_table_input()
	_sync_foreground_controls()

func _begin_table_transition(entering: bool) -> void:
	_table.prewarm_visuals()
	_board_fade_from = 0.0 if entering else _board.modulate.a
	_transition.begin(_table,_view.room.seats,int(_view.seat),entering,_entry_origin,_board.get_global_rect())
	_sync_transition_view()
	_fade_board(0.0)

func _fade_board(amount: float) -> void:
	_board.modulate.a = lerpf(_board_fade_from, 1.0 if _transition.entering else 0.0, amount)
	# An entirely transparent container can be culled during its GPU warmup frame.
	_board_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _transition.entering and _board.modulate.a == 0.0 else SubViewport.UPDATE_WHEN_VISIBLE
	_queue_dice_visual_ready()

func _fade_in_hud() -> void:
	if _hud_fade:
		_hud_fade.kill()
	_hud.modulate.a = 0.0
	_hud_fade = _hud.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hud_fade.tween_property(_hud, "modulate:a", 1.0, UI.MotionFX.MotionConfig.section("transition").crossfade_duration)

func _sync_transition_view() -> void:
	if not is_instance_valid(_transition) or not _transition.active:return
	_board.show()
	_table.show()
	_backdrop.show()
	_frame.visible = _screen == "settings"
	_hud.hide()
	_settlement_names.hide()

func _transition_finished(entering: bool) -> void:
	if not entering or _leaving:return
	_frame.show()
	_update_screen()
	_hud.visible = _screen=="play" and not table_layout_review
	if _hud.visible:
		_fade_in_hud()
	_backdrop.visible = _screen != "play" and not table_play_only
	_sync_foreground_controls()


func _update_screen() -> void:
	if _screen == "settings":
		return
	var room: Dictionary = _view.room
	var result: Dictionary = _view.get("settlement", {})
	if room.get("rolling", false) or int(room.phase) == Room.Phase.IN_ROUND:
		_cancel_flip_reveal()
		if _screen != "play":
			_show("play")
		_refresh_hud()
	elif not result.is_empty():
		var key := "%s/%d" % [room.room_instance_id, int(result.round_number)]
		if _pending_settlement_key == key and is_instance_valid(_flip_reveal) and _flip_reveal.is_active_for(key):
			if _screen != "play":
				_show("play")
			if is_instance_valid(_hud):
				_hud.hide()
			return
		_cancel_flip_reveal()
		if _result_seen != key or _screen in ["home", "connect"]:
			_result_seen = key
			_show("settlement")
		elif _screen == "room":
			_refresh_room()
		elif _screen == "settlement":
			_refresh_settlement_names()
	elif _screen != "room":
		_cancel_flip_reveal()
		_show("room")
	else:
		_cancel_flip_reveal()
		_refresh_room()


func _render_table(round_view: Dictionary) -> void:
	if not is_instance_valid(_table) or round_view.is_empty():
		return
	if round_view.get("phase") == "settled" and _view.has("settlement"):
		var final_view := round_view.duplicate(true)
		final_view.viewer_seat = _settlement_viewer()
		_table.apply_view(final_view, {})
		return
	if round_view.get("phase") == "dice":
		_table.show_full_wall(int(_view.seat))
		_queue_dice_visual_ready()
		_update_restore_button()
		return
	if int(round_view.get("prompt_id", -1)) < 0:
		return
	var mine: Dictionary = round_view.players[int(_view.seat)]
	_order.sync_hand(_view.room.room_instance_id, int(_view.room.round_number), int(round_view.prompt_id), mine.hand, int(mine.draw_id))
	if _restore_display_next and mine.get("display", {}).has("own_keys"):
		_order.restore_shared(mine.display)
		_restore_display_next = false
	_arrange_hand(round_view)
	if not round_view.get("last_discard", {}).is_empty() or round_view.phase == "settled":
		_dice.hide()
	_layout_warning = ""
	_table.apply_view(round_view, _take_display_order())
	_publish_display()


func _arrange_hand(round_view: Dictionary) -> void:
	_insert_plan = {}
	if int(round_view.get("prompt_id", -1)) < 0 or round_view.get("phase") == "settled":
		return
	var display := _order.view()
	if display.get("draw_merged",false) or (not _restore_scope.is_empty() and _restore_scope == _sort_scope()): return
	if int(display.dragged_id) >= 0:
		return
	var profile := _settings.profile()
	var result := _arrangement.arrange(round_view, display, profile.hand_priority, profile.novice)
	if result.has("slots"):
		if display.manual:
			if not result.get("insertion", {}).is_empty(): _order.apply_manual_insertion(result.slots)
		else: _order.apply_auto_slots(result.slots)
		_insert_plan = result.get("insertion", {})


func _dice_changed(pose: Dictionary) -> void:
	if _waiting_for_foreground(): return
	if not _dice.apply_snapshot(pose):
		return
	var round_view: Dictionary = _view.get("round", {})
	var first_discard_pending: bool = round_view.get("last_discard", {}).is_empty() and round_view.get("phase", "") != "settled"
	_dice.visible = (_screen in ["play","settings"] or _view.get("room", {}).get("rolling", false)) and first_discard_pending and pose.get("phase", "") in ["rolling", "settled"]
	_queue_dice_visual_ready()

func _dice_drawable() -> bool:
	return (not _leaving and not _application_paused
		and _board.is_visible_in_tree() and _board.modulate.a > 0.0
		and _table.is_visible_in_tree() and _dice.is_visible_in_tree())

func _queue_dice_visual_ready() -> void:
	if _sound._pending_dice_roll and _dice_drawable() and not RenderingServer.frame_post_draw.is_connected(_dice_frame_drawn):
		RenderingServer.frame_post_draw.connect(_dice_frame_drawn, CONNECT_ONE_SHOT)

func _dice_frame_drawn() -> void:
	if _dice_drawable():
		_sound.notify_dice_visual_ready()


func _refresh_hud() -> void:
	var round_view: Dictionary = _round_projection
	var room: Dictionary = _view.room
	var turn := int(round_view.get("turn", -1))
	var mine := int(_view.seat)
	var phase: String = str(round_view.get("phase", ""))
	var auto_play := _auto_play_active()
	var active_round := phase in ["dealt", "turn", "response", "ready_draw"]
	var auto_on := auto_play and active_round
	_auto_play_button.text = "取消代打" if auto_play else "AI代打"
	_auto_play_button.disabled = not active_round
	if is_instance_valid(_auto_play_banner):
		var banner := _auto_play_banner
		# The passive face finishes fading after the live shortcut has left the HUD.
		var face := banner.get_parent() as Button
		if face == null:
			face = banner.duplicate(0) as Button
			face.focus_mode = Control.FOCUS_NONE
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_hud.add_child(face)
			banner.reparent(face, false)
			banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			banner.z_index = 0
			UI.MotionFX.bind_button(banner)
			_hud.visibility_changed.connect(func():
				if _screen != "play":
					UI.MotionFX.stop(face)
					face.hide())
		if _screen != "play":
			UI.MotionFX.stop(face)
			face.hide()
			banner.hide()
		elif auto_on != banner.visible:
			banner.visible = auto_on
			face.self_modulate.a = 0.0 if auto_on else 1.0
			if auto_on:
				UI.MotionFX.animate_popup_show(face)
			else:
				UI.MotionFX.animate_popup_hide(face)
	if _auto_play_style_active != auto_play:
		_auto_play_style_active = auto_play
		if auto_play:
			_auto_play_button.add_theme_stylebox_override("normal", UI.card(Color("#59421e"), 11, 12, Color("#e6b85b"), 2))
			_auto_play_button.add_theme_stylebox_override("hover", UI.card(Color("#705022"), 11, 12, Color("#ffe195"), 2))
			_auto_play_button.add_theme_stylebox_override("pressed", UI.card(Color("#463216"), 11, 12, Color("#d9aa54"), 2))
		else:
			for state in ["normal", "hover", "pressed"]:
				_auto_play_button.remove_theme_stylebox_override(state)
	if is_instance_valid(_wall_pill) and is_instance_valid(_wall_count_label):
		var show_wall := phase in ["dealt", "turn", "response", "ready_draw"]
		_wall_pill.visible = show_wall
		if show_wall:
			var remain := maxi(0, int(round_view.get("wall_remaining", round_view.get("wall_slots", []).size())))
			_wall_count_label.text = "余 %d 张" % remain
			_wall_count_label.add_theme_color_override("font_color", Color("#ffae78") if remain <= 10 else Color("#f4e5bc"))
	_refresh_voice_status()
	var dealer := int(round_view.get("dealer", -1))
	for position in 4:
		var seat := posmod(mine - position, 4)
		var member: Dictionary = room.seats[seat]
		var flags := PackedStringArray()
		var rows: Array = round_view.get("players", [])
		var seat_ready := rows.size() == 4 and bool(rows[seat].ready)
		if int(member.ai_id) < 0 and member.get("away", not member.connected):
			flags.append("暂离")
		var context := {"room_instance_id": room.room_instance_id, "seat": seat, "player_id": member.player_id}
		var interactive := _mode != "solo" and not VoiceController.remote_player_id(member).is_empty()
		_identities[position].show_player(member, flags, seat == turn and phase == "turn", context, interactive)
		_identities[position].set_role_seals(seat == dealer, seat_ready)
		_identities[position].tooltip_text = "点击名字或分数开关麦克风" if seat == mine else "点击名字或分数切换收听/静音"
	_refresh_identity_voice()
	var remaining := int(_clock.get("remaining_ms", -1))
	_timer.text = str(int(ceilf(remaining / 1000.0))) if remaining >= 0 else ""
	_timer.modulate = Color("#ffd0c1") if _clock.get("reminder", false) else Color.WHITE
	var clock_suppressed := _auto_play_active() or _waiting_for_foreground() or is_instance_valid(_leave_overlay) or _transition.active
	_clock_face.show_clock(_clock, round_view, mine, clock_suppressed)
	_refresh_actions()
	_show_table_notice()
	_update_restore_button()
	_queue_hud_layout()


func _auto_play_active() -> bool:
	return not _view.is_empty() and _view.room.seats[int(_view.seat)].get("auto_play", false)


func _toggle_auto_play() -> void:
	if _screen != "play" or is_instance_valid(_leave_overlay) or _waiting_for_foreground():
		return
	if not _client.set_auto_play(not _auto_play_active()):
		_set_status("代打状态暂时无法更改，请重试。")


func _toggle_microphone() -> void:
	if _screen != "play" or is_instance_valid(_leave_overlay) or _waiting_for_foreground() or not is_instance_valid(_voice) or _mode == "solo":
		return
	_speaker_error = ""
	if _mode == "online":
		_voice.set_directory_url(_online_url())
	var want_on: bool = not _voice.microphone_requested()
	_voice.set_microphone(want_on)
	_refresh_voice_status()
	if is_instance_valid(_ting_overlay):
		var msg := _voice.message if not _voice.message.is_empty() else ("麦克风已开启" if want_on else "麦克风已关闭")
		_last_voice_toast = msg
		_ting_overlay.show_toast(msg, 1.8)


func _voice_status(_recording: bool, message: String) -> void:
	_refresh_voice_status()
	_refresh_identity_voice()
	if _screen == "play" and is_instance_valid(_ting_overlay) and not message.is_empty() and message != _last_voice_toast:
		if message != "麦克风已关闭" or _last_voice_toast == "麦克风已开启":
			_last_voice_toast = message
			_ting_overlay.show_toast(message, 1.8)


func _speaker_preference_failed(message: String) -> void:
	_speaker_error = message
	_refresh_voice_status()


func _cancel_identity_presses() -> void:
	for badge in _identities:
		badge.cancel_press()


func _identity_pressed(context: Dictionary) -> void:
	if _screen != "play" or is_instance_valid(_leave_overlay) or _waiting_for_foreground() or _mode == "solo" or _view.is_empty():
		return
	var seat: int = context.seat
	var room: Dictionary = _view.room
	if room.room_instance_id != context.room_instance_id or seat not in range(room.seats.size()):
		return
	if VoiceController.remote_player_id(room.seats[seat]) != context.player_id:
		return
	if seat == int(_view.seat):
		_toggle_microphone()
	else:
		var next_enabled: bool = not _voice.speaker_enabled(seat)
		if _voice.set_speaker_enabled(seat, next_enabled, context.player_id):
			_speaker_error = ""
			_refresh_voice_status()
			if is_instance_valid(_ting_overlay):
				var nick := str(room.seats[seat].get("nickname", "该玩家"))
				_ting_overlay.show_toast(("已恢复收听 %s" if next_enabled else "已取消收听 %s") % nick, 1.5)


func _refresh_identity_voice() -> void:
	if not is_instance_valid(_voice):
		return
	var multiplayer_active := _mode != "solo" and not _view.is_empty()
	var seats: Array = _view.get("room", {}).get("seats", []) if multiplayer_active else []
	for badge in _identities:
		var seat: int = badge.context.get("seat", -1)
		var local: bool = seat == _view.get("seat", -2)
		var pid := str(badge.context.get("player_id", ""))
		var has_human := multiplayer_active and seat in range(seats.size()) and not VoiceController.remote_player_id(seats[seat]).is_empty()
		var mic_on: bool = _voice.name_mic_active(seat)
		var mic_pending: bool = local and not mic_on and _voice.microphone_requested()
		var muted: bool = not local and not _voice.speaker_enabled_for(pid)
		badge.set_mic_active(mic_on, muted)
		badge.set_voice_indicator(has_human, local, mic_on, muted, mic_pending)
		if local:
			badge.tooltip_text = ("麦克风已开启（点击关闭）\n" if mic_on else "麦克风已关闭（点击开启）\n") + _voice_status_text
		elif has_human:
			badge.tooltip_text = "已取消收听，点击恢复收听" if muted else "正在收听，点击取消收听"
		else:
			badge.tooltip_text = ""


func _refresh_voice_status() -> void:
	if not is_instance_valid(_voice):
		return
	_voice_status_text = _speaker_error if not _speaker_error.is_empty() else _voice.message
	_refresh_identity_voice()


func _toggle_teaching() -> void:
	if is_instance_valid(_leave_overlay) or _waiting_for_foreground():
		return
	_teaching_enabled = not _teaching_enabled
	_teaching_button.text = "关闭教打" if _teaching_enabled else "开启教打"
	if _teaching_enabled:
		_request_teaching()
	else:
		_teaching.cancel()
		_teaching_status.text = ""


func _request_teaching() -> void:
	if not _teaching_enabled or _screen != "play" or not is_instance_valid(_teaching):
		return
	if _choices().is_empty():
		_teaching.cancel()
		_teaching_status.text = "等待你的操作"
	elif _teaching.recommend(_view, _settings.profile().difficulty):
		if _teaching_status.text.is_empty() or _teaching_status.text == "等待你的操作":
			_teaching_status.text = "正在分析"


func _receive_teaching(result: Dictionary) -> void:
	if not is_instance_valid(_teaching_status) or not _tile_action.is_empty():
		return
	if not _teaching_enabled or _screen != "play" or result.is_empty():
		_teaching_status.text = ""
		if is_instance_valid(_table):
			_table.set_hint_tile(-1)
		return
	if _view.is_empty() or result.room_instance_id != _view.room.room_instance_id or int(result.round_number) != int(_view.room.round_number) or int(result.prompt_id) != int(_round_projection.get("prompt_id", -1)):
		return
	_teaching_status.text = result.message
	if is_instance_valid(_table):
		var rec_id := int(result.get("tile_id", -1))
		_table.set_hint_tile(rec_id if str(result.get("action", "")) in ["discard", "ready", "concealed_kong", "add_kong"] else -1)
	if is_instance_valid(_ting_overlay) and not str(result.get("message", "")).is_empty():
		_ting_overlay.show_toast("参谋建议：" + str(result.message), 2.2)

func _refresh_smart_assist() -> void:
	var enabled: bool = bool(_settings.profile().get("smart_hints", true)) and _screen == "play" and not _round_projection.is_empty() and not _view.is_empty()
	if not enabled:
		if is_instance_valid(_ting_overlay):
			_ting_overlay.clear_all()
		if is_instance_valid(_table):
			_table.set_match_highlight("")
		return
	var viewer := int(_view.get("seat", -1))
	var selected_id := int(_order.view().selected_id)
	if is_instance_valid(_ting_overlay):
		var badge_anchor := Rect2()
		if _identities.size() > 0 and is_instance_valid(_identities[0]):
			var r := _identities[0].get_global_rect()
			badge_anchor = Rect2(r.position - _ting_overlay.global_position, r.size)
		var lifted_pt := Vector2(-1.0, -1.0)
		if selected_id >= 0 and is_instance_valid(_table) and _table.tiles.has(selected_id):
			var node: MeshInstance3D = _table.tiles[selected_id]
			var top_y := INF
			var sum_x := 0.0
			for c in 8:
				var pt := _table_screen_point(node.global_transform * node.get_aabb().get_endpoint(c))
				top_y = minf(top_y, pt.y)
				sum_x += pt.x
			lifted_pt = Vector2(sum_x / 8.0, top_y) - _ting_overlay.global_position
		_ting_overlay.sync_state(_round_projection, viewer, selected_id, true, badge_anchor, lifted_pt)
	var match_value := ""
	if selected_id >= 0 and viewer >= 0 and viewer < _round_projection.get("players", []).size():
		for face in _round_projection.players[viewer].get("hand", []):
			if int(face.get("id", -1)) == selected_id:
				match_value = str(face.get("value", ""))
				break
	if is_instance_valid(_table):
		_table.set_match_highlight(match_value)


func _show_table_notice() -> void:
	var phase: String = _round_projection.get("phase", "")
	if _tile_action != "":
		_table_message.text = "请选择要%s的牌" % ACTION_NAMES[_tile_action]
	elif phase == "dice":
		_table_message.text = "正在掷骰"
	elif phase == "dealt":
		_table_message.text = "正在发牌"
	elif _clock.get("phase") == "grace":
		_table_message.text = "额外出牌时间"
	else:
		_table_message.text = _layout_warning


func _layout_conflict(_seat: int, _group: String) -> void:
	_layout_warning = "当前布局没有安全位置，已保留原牌位置"
	_show_table_notice()


func _refresh_actions() -> void:
	if is_instance_valid(_clock_face): _clock_face.apply_quality(_table.quality)
	var choices := _choices()
	var key := choices.duplicate(true)
	key["auto_play"] = _auto_play_active()
	key["own_hand_moving"] = _own_turn_hand_moving()
	if key == _action_key:
		for button in _buttons.get_children():
			if button.has_method("apply_quality"): button.apply_quality(_table.quality)
		return
	_action_key = key
	var disabled: bool = key.auto_play or key.own_hand_moving
	for button in _buttons.get_children():
		_buttons.remove_child(button)
		button.queue_free()
	for action in ACTION_ORDER:
		if not choices.get("actions",[]).has(action):continue
		if action in ["concealed_kong", "add_kong"]:
			var ids: Array = choices.get(action + "_ids", [])
			for face in _round_projection.players[int(_view.seat)].hand:
				if not ids.has(face.id):
					continue
				var button := TableActionButton.new();button.configure(action,ACTION_NAMES[action], _pick_kong.bind(action, int(face.id), int(choices.prompt_id)))
				button.apply_quality(_table.quality)
				button.icon = TileArt.face(face.value)
				button.add_theme_constant_override("icon_max_width", 24)
				button.accessibility_name = "%s%s" % [SettlementView.tile_name(face.value), button.text]
				button.tooltip_text = button.accessibility_name
				button.disabled = disabled
				_buttons.add_child(button)
		elif ACTION_NAMES.has(action):
			var button := TableActionButton.new();button.configure(action,ACTION_NAMES[action], _pick_action.bind(action))
			button.apply_quality(_table.quality)
			button.disabled = disabled
			_buttons.add_child(button)
	const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
	for index_from_right in _buttons.get_child_count():
		var button := _buttons.get_child(-1 - index_from_right) as TableActionButton
		button.start_entrance(index_from_right * float(MotionConfig.value("action_button", "enter_stagger")))
	_fit_action_buttons()

func _fit_action_buttons(queue_layout: bool = true) -> void:
	if not is_instance_valid(_buttons) or not _page_key.is_empty(): return
	var count:=_buttons.get_child_count()
	if count==0: return
	var area:=capture_hud_item("actions")
	var width:float=float(area.width)*_safe.size.x
	var height:float=float(area.height)*_safe.size.y
	var slots := maxi(4, count)
	var sep := 10 if count <= 4 else 8
	var wanted:float=float(area.get("button_scale",1))*90*_safe.size.y/692.0 if area.has("button_scale") else 90
	var diameter := clampf(minf(wanted, minf(height, (width - (slots - 1) * sep) / slots)), 52.0, 120.0)
	for button in _buttons.get_children(): button.custom_minimum_size=Vector2(diameter,diameter);button.queue_redraw()
	_buttons.add_theme_constant_override("separation", sep)
	_buttons.offset_right=-8
	_buttons.offset_left=-8-count*diameter-(count-1)*sep
	_buttons.offset_bottom=-maxf(144,_safe.size.y*0.23)
	_buttons.offset_top=_buttons.offset_bottom-diameter
	if queue_layout:_queue_hud_layout()

func _hud_items() -> Dictionary:
	if not _page_key.is_empty():return _editable_items()
	var items:Dictionary=_table.custom_profile.data.get("hud",{}).duplicate(true) if _table.custom_profile else {}
	if not items.has("actions"):items.actions=_default_action_row()
	for key in HIDDEN_HUD:
		if not items.has(key):items[key]=HudLayout.capture(_hud_controls[key],_safe)
		if not items[key].has("visible"):items[key].visible=false
	return items

func _editable_items() -> Dictionary:
	if not _table.custom_profile:return {}
	var data:Dictionary=_table.custom_profile.data
	if _page_key.is_empty():
		if not data.has("hud"):data.hud={}
		return data.hud
	if not data.has("pages"):data.pages={}
	if not data.pages.has(_page_key):data.pages[_page_key]={}
	return data.pages[_page_key]

func set_hud_item(key:String,row:Dictionary) -> void:
	_editable_items()[key]=row

func clear_hud_item(key:String) -> void:
	_editable_items().erase(key)
func _default_action_row() -> Dictionary:
	var width:=minf(600,_safe.size.x-16)
	return {"x":1-(8+width*0.5)/_safe.size.x,"y":1-(maxf(144,_safe.size.y*0.23)+45)/_safe.size.y,"scale":1.0,"width":width/_safe.size.x,"height":90/_safe.size.y}
func capture_hud_item(key: String) -> Dictionary:
	var controls:=editable_hud_controls()
	if not _page_key.is_empty():return _hud_items().get(key,PageLayout.capture(controls[key],_safe)).duplicate(true)
	var row:Dictionary=_hud_items().get(key,HudLayout.capture(controls[key],_safe)).duplicate()
	if key=="actions":
		var fallback:=_default_action_row()
		row.width=row.get("width",fallback.width);row.height=row.get("height",fallback.height)
		row.button_scale = row.get("button_scale", 692.0 / _safe.size.y)
	else:
		row.width=maxf(1,controls[key].size.x)/_safe.size.x
		row.height=maxf(1,controls[key].size.y)/_safe.size.y
	return row
func hud_item_rect(key: String) -> Rect2:
	return HudLayout.item_rect(key,_hud_items(),editable_hud_controls(),_safe)

func resize_hud_item(key: String, rect: Rect2) -> void:
	var row:=capture_hud_item(key)
	if key=="settlement":row.scale=1.0
	var factor:float=row.scale
	var minimum:=Vector2(328,48)*factor if key=="actions" else Vector2(16,16)
	rect.size=rect.size.clamp(minimum,_safe.size.min(_safe.size*factor))
	var offset:=PageLayout.scroll_offset(editable_hud_controls()[key]) if not _page_key.is_empty() else Vector2.ZERO
	var center:Vector2=((rect.get_center()-_safe.global_position+offset)/_safe.size).clamp(Vector2.ZERO,Vector2.ONE*(16 if not _page_key.is_empty() else 1))
	row.x=center.x;row.y=center.y
	row.width=rect.size.x/(_safe.size.x*factor);row.height=rect.size.y/(_safe.size.y*factor)
	set_hud_item(key,row)
	_apply_hud_layout()

func editable_hud_controls() -> Dictionary:
	if not _page_key.is_empty():return _page_controls
	var result := _hud_controls.duplicate()
	if is_instance_valid(_win_feedback):
		result["win/portrait"] = _win_feedback._portrait
		result["win/title"] = _win_feedback._title
		result["win/names"] = _win_feedback._names
	if _screen == "settlement" and _frame.get_child_count() == 1:
		result.settlement = _frame.get_child(0)
		for index in _settlement_names.badges.size(): result["player/" + str(index)] = _settlement_names.badges[index]
		if is_instance_valid(_next_round_button) and _next_round_button.get_parent() == _safe:
			result.next_round = _next_round_button
	var occurrences := {}
	for button in _buttons.get_children():
		var action: String = button.action
		var count: int = occurrences.get(action, 0)
		occurrences[action] = count + 1
		result["action/" + action + "/" + str(count)] = button
	return result

func _queue_hud_layout() -> void:
	if _hud_layout_queued or not is_instance_valid(_hud): return
	_hud_layout_queued = true
	_apply_hud_layout.call_deferred()

func _apply_hud_layout() -> void:
	_hud_layout_queued = false
	if not is_instance_valid(_table) or not _table.custom_profile: return
	if not _page_key.is_empty():
		PageLayout.apply({} if is_instance_valid(_profile_setup) and _profile_setup.typing else _hud_items(),_page_controls,_safe)
		return
	# The old desktop split result pane has its own name layout, unlike the full-screen phone table.
	if _screen=="settlement" and not table_play_only:return
	_fit_action_buttons(false)
	HudLayout.apply(_hud_items(), editable_hud_controls(), _safe)
	if _screen == "play":
		_refresh_smart_assist()
	if is_instance_valid(_telemetry_bar) and _telemetry_bar.visible:
		_telemetry_bar.refresh_now()
	if _screen=="settlement" and table_play_only:
		_constrain_settlement()
		_clear_settlement_side_names()
		_position_next_round()

func _update_restore_button() -> void:
	if not is_instance_valid(_restore_button): return
	var in_play_hand: bool = str(_round_projection.get("phase", "")) not in ["", "dice", "settled"]
	_restore_button.visible = in_play_hand and (_order.view().manual or not _order.view().pending_insert_ids.is_empty())
	_restore_button.disabled = _waiting_for_foreground() or _auto_play_active() or not _table.own_hand_stable() or is_instance_valid(_leave_overlay)
	_sort_button.disabled = _restore_button.disabled or _sort_busy or _sort_wait_ack or _round_projection.get("phase", "") in ["", "dice", "dealt", "settled"]

func _restore_hand_order() -> void:
	if _screen != "play" or _waiting_for_foreground() or _auto_play_active() or not _table.own_hand_stable() or is_instance_valid(_leave_overlay): return
	_cancel_sort()
	_order.restore_order()
	_restore_scope = _sort_scope()
	if is_instance_valid(_ting_overlay):
		_ting_overlay.show_toast("已恢复默认牌序", 1.4)
	_play_cue("tile_slide", 0.92)
	_apply_order()
	_update_restore_button()
	_queue_hud_layout()

func _sort_scope() -> Dictionary:
	if _view.is_empty() or _round_projection.get("players",[]).size()!=4: return {}
	var profile := _settings.profile()
	var safe := HandSort.safe_view(_round_projection,profile.suit_order,profile.hand_priority)
	return {"room_instance_id":_view.room.room_instance_id,"round_number":int(_view.room.get("round_number",1)),
		"seat":int(_view.seat),"prompt_id":int(_round_projection.prompt_id),"signature":var_to_bytes(safe).hex_encode()}
func _cancel_sort() -> void:
	if is_instance_valid(_sorter): _sorter.cancel()
	_sort_plans.clear(); _sort_index=-1; _sort_scope_cache={}; _sort_busy=false
	if is_instance_valid(_sort_status): _sort_status.text=""; _sort_status.hide()
func _sort_hand() -> void:
	if _screen!="play" or _waiting_for_foreground() or _auto_play_active() or not _table.own_hand_stable() or is_instance_valid(_leave_overlay) or _sort_busy or _sort_wait_ack: return
	if _choices().get("actions",[]).has("self_win"):
		_sort_wait_ack = true
		_sort_decline_prompt = int(_round_projection.prompt_id)
		_sort_decline_ready = _round_projection.players[int(_view.seat)].ready
		if not _client.submit(int(_round_projection.prompt_id),"sort"):
			_sort_wait_ack = false
		_update_restore_button()
		return
	if _sort_scope_cache == _sort_scope() and not _sort_plans.is_empty(): _cycle_sort(); return
	_start_sort()
func _start_sort() -> void:
	var scope := _sort_scope()
	if scope.is_empty(): return
	_sort_busy=true; _sort_scope_cache=scope
	_sort_status.text="正在整理排法…"
	_sort_status.show()
	var profile := _settings.profile()
	if not _sorter.request(scope,_round_projection,profile.suit_order,profile.hand_priority): _cancel_sort()
	_update_restore_button()
func _sort_completed(result: Dictionary) -> void:
	if result.scope != _sort_scope_cache: return
	if result.scope != _sort_scope() or _screen!="play": _cancel_sort(); return
	_sort_busy=false; _sort_plans=result.plans; _sort_index=-1
	if _sort_plans.is_empty(): _sort_status.text="当前没有可用的排法"
	else: _cycle_sort()
	_update_restore_button()
func _cycle_sort() -> void:
	_sort_index=posmod(_sort_index+1,_sort_plans.size())
	var plan: Dictionary=_sort_plans[_sort_index]
	var before: Dictionary = _order.view()
	if not _order.apply_sort_plan(plan.slots,plan.merge_draw): return
	if plan.merge_draw and not before.get("draw_merged",false):
		_insert_plan = HandArrangement._insertion_plan(plan.slots,{"tile_id":before.draw_id,"discard_id":-1,"before_slots":before.slots})
		# Explicit sort has no discard event, but still needs a one-shot space-then-insert animation.
		_insert_plan.discard_id = -2 - int(_round_projection.prompt_id)
	_restore_scope={}
	_sort_status.text="排法 %d/%d：%s"%[_sort_index+1,_sort_plans.size(),plan.message]
	_sort_status.tooltip_text=plan.structure
	_sort_status.show()
	if is_instance_valid(_ting_overlay):
		_ting_overlay.show_toast("智能排法 %d/%d · %s" % [_sort_index + 1, _sort_plans.size(), plan.message], 2.0)
	_play_cue("tile_slide")
	_apply_order()

func _trigger_action_fx(prev_round: Dictionary, next_round: Dictionary) -> void:
	if not is_instance_valid(_fx_stage) or _transition.active:
		return
	var prev_players: Array = prev_round.get("players", [])
	var next_players: Array = next_round.get("players", [])
	if prev_players.size() != 4 or next_players.size() != 4:
		return
	var viewer := int(_view.get("seat", 1))
	for seat in 4:
		var rel := Seats.relative(viewer, seat)
		var old_p: Dictionary = prev_players[seat]
		var new_p: Dictionary = next_players[seat]
		if not bool(old_p.get("ready", false)) and bool(new_p.get("ready", false)):
			_fx_stage.play_action("ready", rel)
		var old_melds: Array = old_p.get("melds", [])
		var new_melds: Array = new_p.get("melds", [])
		if new_melds.size() > old_melds.size():
			var added: Dictionary = new_melds.back()
			var tile_label := SettlementView.tile_name(str(added.get("tile", "")))
			if added.get("kind") == "pung":
				_fx_stage.play_action("pong", rel, tile_label)
				_table.pulse_table_shake(0.10)
			elif added.get("kind") == "kong":
				var is_concealed := bool(added.get("concealed", false))
				_fx_stage.play_action("concealed_kong" if is_concealed else "kong", rel, "" if is_concealed else tile_label)
				_table.pulse_table_shake(0.15)
		else:
			for idx in mini(old_melds.size(), new_melds.size()):
				if old_melds[idx].get("kind") == "pung" and new_melds[idx].get("kind") == "add_kong":
					var tile_label := SettlementView.tile_name(str(new_melds[idx].get("tile", "")))
					_fx_stage.play_action("add_kong", rel, tile_label)
					_table.pulse_table_shake(0.14)
		# 本家新摸牌轻脆手感音效
		if seat == viewer and int(new_p.get("draw_id", -1)) >= 0 and int(new_p.get("draw_id", -1)) != int(old_p.get("draw_id", -1)):
			if prev_round.get("phase", "") not in ["", "dice", "dealt"]:
				_play_cue("tile_draw")
	# 冲锋鸡检测（幺鸡 / 八筒首次打出）
	var old_charges: Dictionary = prev_round.get("charge_chickens", {})
	var new_charges: Dictionary = next_round.get("charge_chickens", {})
	for chicken_tile in ["tiao1", "tong8"]:
		if not old_charges.has(chicken_tile) and new_charges.has(chicken_tile):
			var owner := int(new_charges[chicken_tile].get("owner", -1))
			if owner in range(4):
				var label := "幺鸡" if chicken_tile == "tiao1" else "八筒"
				_fx_stage.play_action("charge_chicken", Seats.relative(viewer, owner), label)
				_table.pulse_table_shake(0.16)
				_play_cue("charge_chicken")

func _play_cue(clip: String, pitch: float = 1.0) -> void:
	if is_instance_valid(_sound):
		_sound.play_cue(clip, pitch)

func _cancel_flip_reveal() -> void:
	_pending_settlement_key = ""
	if is_instance_valid(_flip_reveal):
		_flip_reveal.cancel()


func _flip_reveal_finished(key: String) -> void:
	if _pending_settlement_key == key:
		_pending_settlement_key = ""
	if not _view.is_empty():
		_update_screen()


func _cancel_chicken_reveal() -> void:
	if _chicken_reveal_tween != null and _chicken_reveal_tween.is_valid():
		_chicken_reveal_tween.kill()
	_chicken_reveal_tween = null
	if is_instance_valid(_table):
		_table.clear_chicken_highlights()

func _extract_win_badges(result: Dictionary, settlement: Dictionary) -> PackedStringArray:
	var tags: PackedStringArray = PackedStringArray()
	var seen := {}
	var ledger: Dictionary = settlement.get("ledger", {})
	var items_all: Array = ledger.get("items", [])
	for winner in result.get("winners", []):
		var seat := int(winner)
		if seat < 0 or seat >= items_all.size():
			continue
		for entry in items_all[seat]:
			var kind: String = str(entry.get("kind", ""))
			var label: String = str(entry.get("label", ""))
			if kind in ["pattern", "bonus", "win"] and int(entry.get("amount", 0)) > 0:
				var short_name := label.replace("自摸基础分", "").replace("点炮基础分", "").replace("平胡", "").strip_edges()
				if not short_name.is_empty() and not seen.has(short_name) and tags.size() < 4:
					seen[short_name] = true
					tags.append(short_name)
	return tags

func _start_chicken_reveal(settlement: Dictionary) -> void:
	_cancel_chicken_reveal()
	if settlement.is_empty() or not is_instance_valid(_table) or not is_instance_valid(_fx_stage):
		return
	var ledger: Dictionary = settlement.get("ledger", {})
	var items_all: Array = ledger.get("items", [])
	var hit_ids: Array[int] = []
	var seen_ids := {}
	var counts := {}
	for seat_items in items_all:
		for entry in seat_items:
			var kind: String = str(entry.get("kind", ""))
			if kind not in ["chicken", "charge", "flip"]:
				continue
			var label: String = str(entry.get("label", "鸡牌"))
			var ids: Array = entry.get("tile_ids", [])
			for raw_id in ids:
				var id := int(raw_id)
				if id >= 0 and not seen_ids.has(id) and _table.tiles.has(id):
					seen_ids[id] = true
					hit_ids.append(id)
					counts[label] = int(counts.get(label, 0)) + 1
	var flip_idx := int(_round_projection.get("result", {}).get("flip_wall_index", -1))
	if flip_idx >= 0 and not seen_ids.has(flip_idx) and _table.tiles.has(flip_idx):
		seen_ids[flip_idx] = true
		hit_ids.append(flip_idx)
	if hit_ids.is_empty():
		return
	# 结算静默金光标亮翻出鸡牌与所有计分鸡牌，不再播放连续嘀嘀声与数币噪音
	_table.set_chicken_highlights(hit_ids)

func _show_win_feedback(result: Dictionary, key: String) -> void:
	if _screen not in ["play","settlement"] or _view.get("room",{}).is_empty(): return
	if key!=str(_view.room.room_instance_id)+"/"+str(_view.room.round_number): return
	var source:=Vector2.ZERO
	var id:int=result.get("win_tile_id",-1)
	if _table.tiles.has(id):
		var point:=_table.camera.unproject_position(_table.tiles[id].position)*_board.size/Vector2(_board_world.size)
		source=point+_board.global_position-_safe.global_position
	var settlement: Dictionary = _view.get("settlement", {})
	var badges := _extract_win_badges(result, settlement)
	if _win_feedback.present(key, result, _view.room.seats, source, badges):
		_table.pulse_table_shake(0.28)
	_start_chicken_reveal(settlement)
	_queue_hud_layout()


func _own_turn_hand_moving() -> bool:
	return _round_projection.get("phase") == "turn" and _round_projection.turn == _view.get("seat") and not _table.own_hand_stable()


func _update_hand_actions() -> void:
	if _screen == "play":
		_refresh_actions()
		_update_restore_button()


func _pick_kong(action: String, tile_id: int, prompt: int) -> void:
	var choices := _choices()
	if choices.get("prompt_id", -1) == prompt and choices.get(action + "_ids", []).has(tile_id):
		_submit_action(action, tile_id)


func _pick_action(action: String) -> void:
	if _screen != "play" or _auto_play_active() or is_instance_valid(_leave_overlay) or _own_turn_hand_moving():
		return
	var choices := _choices()
	if not choices.get("actions", []).has(action):
		return
	if action in ["discard", "ready"]:
		if _tile_action == action:
			_clear_tile_action(true)
			return
		var ids: Array = choices.get(action + "_ids", [])
		var selected := int(_order.view().selected_id)
		if ids.has(selected):
			_submit_action(action, selected)
		else:
			_tile_action = action
			_show_table_notice()
			if is_instance_valid(_table):
				_table.set_hint_tiles(ids)
			if is_instance_valid(_ting_overlay):
				var hint := "请点击亮起的牌打出并报听（点空白或再点报听取消）" if action == "ready" else "请点击要出打的牌（点空白取消）"
				_ting_overlay.show_toast(hint, 3.0)
	else:
		_submit_action(action, int(choices.get("tile_id", -1)))


func _choices() -> Dictionary:
	return {} if _waiting_for_foreground() or _transition.active else _round_projection.get("choices", {})


func _clear_tile_action(show_cancel_toast: bool = false) -> void:
	if _tile_action.is_empty():
		return
	_tile_action = ""
	_show_table_notice()
	if is_instance_valid(_table):
		_table.set_hint_tile(-1)
	if show_cancel_toast and is_instance_valid(_ting_overlay):
		_ting_overlay.show_toast("已取消操作")


func _submit_action(action: String, tile_id: int, confirmed_swipe: bool = false) -> void:
	var choices := _choices()
	if _screen != "play" or is_instance_valid(_leave_overlay) or _auto_play_active() or not choices.get("actions", []).has(action):
		return
	if _own_turn_hand_moving() and not (action == "discard" and confirmed_swipe):
		return
	if not _client.submit(int(choices.prompt_id), action, tile_id):
		_table_message.text = "该操作暂不可用"
		return
	if _tile_action.is_empty():
		_show_table_notice()
	else:
		_clear_tile_action()


func _cancel_table_selection() -> void:
	if _screen != "play" or is_instance_valid(_leave_overlay) or _waiting_for_foreground():
		return
	_clear_tile_action(true)
	if _order.view().selected_id >= 0:
		_order.clear_selection()
		_apply_order()


func _tile_clicked(tile_id: int) -> void:
	if _screen != "play" or is_instance_valid(_leave_overlay) or _auto_play_active() or _waiting_for_foreground() or not _table.can_play_hand():
		return
	if _tile_action != "":
		if _choices().get(_tile_action + "_ids", []).has(tile_id):
			_submit_action(_tile_action, tile_id)
		elif is_instance_valid(_ting_overlay):
			_ting_overlay.show_toast("该牌不能%s，请点击亮起绿光的牌" % ACTION_NAMES[_tile_action], 2.0)
		return
	if not _choices().get("discard_ids", []).has(tile_id):
		return
	var ready_to_discard := tile_id if _table._hold_tap_confirms else _order.tap(tile_id)
	_apply_order()
	if _choices().get("discard_ids", []).has(ready_to_discard):
		_submit_action("discard", ready_to_discard)
	else:
		_play_cue("tile_select")


func _swipe_discard(tile_id: int) -> void:
	if _screen == "play" and _choices().get("discard_ids", []).has(tile_id):
		_submit_action("discard", tile_id, true)


func _on_discard_drag_state_changed(active: bool, ready_to_release: bool) -> void:
	if is_instance_valid(_ting_overlay) and _ting_overlay.has_method("set_discard_drag_hint"):
		_ting_overlay.call("set_discard_drag_hint", _screen == "play" and active, _screen == "play" and ready_to_release)


func _drag_started(tile_id: int) -> void:
	if _screen == "play" and not _waiting_for_foreground() and not is_instance_valid(_leave_overlay) and _order.begin_drag(tile_id):
		_cancel_sort()
		_drag_position = []
		_published_motion_at = -50
		_last_drag_sound_slot = -1
		if is_instance_valid(_table) and _table.tiles.has(tile_id):
			_last_drag_sound_slot = int(_table.tiles[tile_id].get_meta("hand_index", -1))
		_last_drag_sound_ms = Time.get_ticks_msec()
		_play_cue("tile_select", 0.96)
		_apply_order()


func _drag_slot_changed(slot: int) -> void:
	if _waiting_for_foreground(): return
	_order.move_gap(slot)
	var now := Time.get_ticks_msec()
	if slot != _last_drag_sound_slot and now - _last_drag_sound_ms >= 140:
		_last_drag_sound_slot = slot
		_last_drag_sound_ms = now
		_play_cue("tile_slide", 1.0)
	_apply_order()


func _drag_finished(slot: int) -> void:
	if _waiting_for_foreground(): return
	_order.commit_drag(slot)
	_drag_position = []
	_last_drag_sound_slot = -1
	_play_cue("tile_select", 0.90)
	_apply_order()


func _drag_moved(position: Array) -> void:
	if _screen != "play" or int(_order.view().dragged_id) < 0:
		return
	var now := Time.get_ticks_msec()
	if now - _published_motion_at < 50:
		return
	_published_motion_at = now
	_drag_position = position.duplicate()
	_publish_display()


func _apply_order() -> void:
	if is_instance_valid(_table):
		_table.set_hand_order(_take_display_order())
		_publish_display()
		_update_restore_button()
		_refresh_smart_assist()
		_queue_hud_layout()


func _take_display_order() -> Dictionary:
	var display := _order.view()
	if not _insert_plan.is_empty():
		display.insertion = _insert_plan
		_insert_plan = {}
	return display


func _publish_display() -> void:
	if _mode == "solo" or _view.is_empty() or _waiting_for_foreground() or int(_round_projection.get("prompt_id", -1)) < 0 or _round_projection.get("phase") == "settled":
		return
	var order := _order.view()
	var public_order := {"slots": order.slots, "pending_insert_ids": order.pending_insert_ids,
		"dragged_id": order.dragged_id, "selected_id": order.selected_id, "manual": order.manual,"draw_merged":order.draw_merged}
	if int(order.dragged_id) >= 0 and not _drag_position.is_empty():
		public_order.drag_position = _drag_position.duplicate()
	var key := [_view.room.room_instance_id, _view.room.round_number, _round_projection.prompt_id, public_order]
	if key == _published_display:
		return
	_published_display = key
	if not _client.set_hand_display(public_order):
		_published_display = []


func _center_wall(seat: int) -> void:
	if _screen == "play":
		_client.center_wall(seat)


func _cue_key(cue: Dictionary) -> String:
	return "%s/%d/%d" % [cue.room_instance_id, int(cue.round_number), int(cue.prompt_id)]


func _presentation_required(cue: Dictionary) -> void:
	if not is_instance_valid(_table) or _view.is_empty():
		return
	var key := _cue_key(cue)
	if _completed_presentation.has(key):
		_client.finish_presentation.call_deferred(cue)
	else:
		_shown_cues["%s/%d" % [key, int(cue.seat)]] = cue.duplicate()


func _presentation_finished(prompt_id: int) -> void:
	if _view.is_empty() or int(_round_projection.get("prompt_id", -1)) != prompt_id:
		return
	var room: Dictionary = _view.room
	var key := _cue_key({"room_instance_id": room.room_instance_id, "round_number": room.round_number, "prompt_id": prompt_id})
	_completed_presentation.clear()
	_completed_presentation[key] = true
	for identifier in _shown_cues.keys():
		var cue: Dictionary = _shown_cues[identifier]
		_shown_cues.erase(identifier)
		if _cue_key(cue) == key:
			_client.finish_presentation.call_deferred(cue)


func _build_settlement() -> void:
	MainLobbyBuilder.build_settlement(self)

func _toggle_settlement_peek() -> void:
	if _screen != "settlement" or _frame.get_child_count() != 1 or not is_instance_valid(_peek_return_button):
		return
	_settlement_peeking = not _settlement_peeking
	var panel: SettlementView = _frame.get_child(0)
	panel.set_peeking(_settlement_peeking)
	if _settlement_peeking:
		UI.MotionFX.animate_popup_show(_peek_return_button.get_parent())
		UI.focus_later(_peek_return_button)
	else:
		UI.MotionFX.animate_popup_hide(_peek_return_button.get_parent())
		UI.focus_later(panel.peek_button)


func _settlement_viewer() -> int:
	var historic := int(_view.get("settlement", {}).get("viewer_seat", -1))
	return historic if historic in range(4) else int(_view.seat)


func _refresh_settlement_names() -> void:
	_settlement_names.show_result(_view.settlement, _settlement_viewer())
	_refresh_settlement_ready()
	_fit_safe_area.call_deferred()


func _refresh_settlement_ready() -> void:
	if _screen != "settlement" or _frame.get_child_count() != 1:
		return
	var panel := _frame.get_child(0) as SettlementView
	if is_instance_valid(panel):
		panel.update_ready_state(_view.get("room", {}), int(_view.get("seat", -1)), _mode)


func _record_controls() -> HBoxContainer:
	var row := HBoxContainer.new()
	_record_button = UI.button("提交本局记录", _request_record)
	_record_status = UI.label("", 16, UI.MUTED)
	_record_status.set_meta("page_label","记录提交提示")
	_record_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_record_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_record_button)
	row.add_child(_record_status)
	_record_changed(_view.get("record_submission", {}))
	return row


func _request_record() -> void:
	_record_status.text = "正在请求提交…"
	if not _client.request_record_submission():
		_record_status.text = "当前无法请求提交。"


func _record_changed(state: Dictionary) -> void:
	if not is_instance_valid(_record_button):
		return
	var status: String = state.get("status", "")
	_record_button.disabled = status in ["queued", "sending", "stored"]
	_record_button.text = "重试提交" if status == "failed" else "提交本局记录"
	_record_status.text = state.get("message", "")


func _fit_settlement() -> void:
	if table_play_only:
		_queue_hud_layout()
		return
	if _frame.get_child_count() == 1:
		var scores: Control = _frame.get_child(0)
		scores.custom_minimum_size = Vector2(maxf(540, _safe.size.x * 0.59 - 12), maxf(320, _safe.size.y - 20))
	if not is_instance_valid(_settlement_names) or _screen != "settlement":
		return
	var bounds := Rect2()
	var first := true
	var extent: float = _table.table_edge() + 0.8
	for x in [-extent, extent]:
		for z in [-extent, extent]:
			var point := _table.camera.unproject_position(Vector3(x, 0, z)) * _board.size / Vector2(_board_world.size)
			point += _board.global_position - _settlement_names.global_position
			bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
			first = false
	for tile in _table.tiles.values():
		for corner in 8:
			var point:=_table_screen_point(tile.global_transform*tile.get_aabb().get_endpoint(corner))-_settlement_names.global_position
			bounds=bounds.expand(point)
	_settlement_names.arrange(bounds)

func _retire_next_round() -> void:
	if is_instance_valid(_next_round_button) and _next_round_button.get_parent() == _safe:
		_safe.remove_child(_next_round_button); _next_round_button.queue_free()
	_next_round_button = null
	if is_instance_valid(_peek_return_button):
		var holder := _peek_return_button.get_parent()
		holder.hide()
		holder.queue_free()
	_peek_return_button = null
	_settlement_peeking = false

func _position_next_round() -> void:
	# 下一局按钮已固定内置于结算面板底部栏，不再随座位徽章飘动
	return

func _clear_settlement_side_names() -> void:
	for index in [1,3]:
		var badge:=_settlement_names.badges[index]
		var seat:int=badge.context.get("seat",-1)
		var bounds:=Rect2();var found:=false
		for node in _table.tiles.values():
			if node.get_meta("zone","")!="hand" or node.get_meta("seat",-1)!=seat:continue
			for corner in 8:
				var point:=_table_screen_point(node.global_transform*node.get_aabb().get_endpoint(corner))
				bounds=bounds.expand(point) if found else Rect2(point,Vector2.ZERO);found=true
		var rect:=badge.get_global_rect()
		if found and rect.intersects(bounds):
			badge.offset_transform_position.y+=maxf(_safe.global_position.y,bounds.position.y-rect.size.y-6)-rect.position.y

func _table_screen_point(point: Vector3) -> Vector2:
	return _table.camera.unproject_position(point)*_board.size/Vector2(_board_world.size).max(Vector2.ONE)+_board.global_position

func _settlement_geometry() -> Dictionary:
	var polygon:=PackedVector2Array()
	for point in _table.play_area_polygon():polygon.append(_table_screen_point(Vector3(point.x,0,point.y)))
	var walls:=[]
	for node in _table.tiles.values():
		if node.get_meta("zone","")!="wall":continue
		var box:=Rect2()
		for index in 8:
			var point:=_table_screen_point(node.global_transform*node.get_aabb().get_endpoint(index))
			box=Rect2(point,Vector2.ZERO) if index==0 else box.expand(point)
		walls.append(box.grow(4))
	return {"polygon":polygon,"obstacles":walls}

func _constrain_settlement() -> void:
	if _frame.get_child_count() != 1:
		return
	var panel: SettlementView = _frame.get_child(0)
	var safe_rect := _safe.get_global_rect()
	if safe_rect.size.x <= 20.0 or safe_rect.size.y <= 20.0:
		return
	# 固定居中位置与统一尺寸，彻底消除每局按剩余牌墙乱跳的问题；同时保证四家亮牌和徽章完全可见
	var min_w: float = panel._body.get_combined_minimum_size().x + panel.get_theme_stylebox("panel").get_minimum_size().x
	var side_margin := maxf(138.0, safe_rect.size.x * 0.14)
	var left_limit := safe_rect.position.x + side_margin
	var right_limit := safe_rect.end.x - side_margin
	var top_limit := safe_rect.position.y + safe_rect.size.y * 0.22
	var bottom_limit := safe_rect.position.y + safe_rect.size.y * 0.76
	var viewer := _settlement_viewer()
	var opposite := Seats.opposite(viewer)
	var left_seat := Seats.previous(viewer)
	var right_seat := Seats.next(viewer)
	var meld_bottom := INF
	var meld_left := -INF
	var meld_right := INF
	for node in _table.tiles.values():
		var zone: String = node.get_meta("zone", "")
		var seat := int(node.get_meta("seat", -1))
		if zone in ["meld", "chicken"] and seat in [viewer, left_seat, right_seat]:
			for c in 8:
				var point := _table_screen_point(node.global_transform * node.get_aabb().get_endpoint(c))
				if seat == viewer:
					meld_bottom = minf(meld_bottom, point.y - 6.0)
				elif seat == left_seat:
					meld_left = maxf(meld_left, point.x + 8.0)
				else:
					meld_right = minf(meld_right, point.x - 8.0)
		if zone != "hand":
			continue
		if seat == opposite:
			for c in 8:
				top_limit = maxf(top_limit, _table_screen_point(node.global_transform * node.get_aabb().get_endpoint(c)).y + 6.0)
		elif seat == viewer:
			for c in 8:
				bottom_limit = minf(bottom_limit, _table_screen_point(node.global_transform * node.get_aabb().get_endpoint(c)).y - 6.0)
		elif seat == left_seat:
			for c in 8:
				left_limit = maxf(left_limit, _table_screen_point(node.global_transform * node.get_aabb().get_endpoint(c)).x + 8.0)
		elif seat == right_seat:
			for c in 8:
				right_limit = minf(right_limit, _table_screen_point(node.global_transform * node.get_aabb().get_endpoint(c)).x - 8.0)
	var soft_bottom := minf(bottom_limit, meld_bottom)
	var soft_left := maxf(left_limit, meld_left)
	var soft_right := minf(right_limit, meld_right)
	if soft_bottom - top_limit >= 220.0 and soft_right - soft_left >= 380.0:
		bottom_limit = soft_bottom
		left_limit = soft_left
		right_limit = soft_right
	var available_w := maxf(320.0, right_limit - left_limit)
	var target_w := clampf(safe_rect.size.x * 0.54, minf(500.0, available_w), minf(720.0, available_w))
	var width := maxf(min_w, target_w)
	var max_h := maxf(180.0, minf(safe_rect.size.y * 0.52, bottom_limit - top_limit))
	var natural_h := panel.height_for_width(width)
	var factor := minf(1.0, minf(available_w / maxf(1.0, width), max_h / maxf(1.0, natural_h)))
	panel.custom_minimum_size = Vector2(width, natural_h)
	panel.size = Vector2(width, natural_h)
	panel.offset_transform_enabled = true
	panel.offset_transform_position = Vector2.ZERO
	panel.offset_transform_scale = Vector2.ONE
	var final_size := Vector2(width, natural_h) * factor
	var center_x := clampf(safe_rect.position.x + safe_rect.size.x * 0.5, left_limit + final_size.x * 0.5, right_limit - final_size.x * 0.5)
	var center_y := clampf((top_limit + bottom_limit) * 0.5, top_limit + final_size.y * 0.5, bottom_limit - final_size.y * 0.5)
	var center := Vector2(center_x, center_y)
	# CenterContainer 始终将其唯一子节点对齐到自身几何中心，直接以 _frame 中心为锚点彻底避免首帧左偏
	var original := _frame.get_global_rect().get_center()
	panel.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	panel.offset_transform_scale = Vector2.ONE * factor
	panel.offset_transform_position = (center - original) / _frame.get_global_transform_with_canvas().get_scale()
	_settlement_area = Rect2(center - final_size * 0.5, final_size)


func _prepare_next_round() -> void:
	if _view.is_empty():
		return
	var mine := int(_view.get("seat", -1))
	var mine_ready := mine in range(4) and bool(_view.room.seats[mine].get("ready", false))
	var target_ready := true if _mode == "solo" else (not mine_ready)
	if _mode == "solo" and is_instance_valid(_next_round_button) and _next_round_button.disabled:
		return
	if _client.set_ready(target_ready):
		if _mode == "solo" and is_instance_valid(_next_round_button):
			_next_round_button.disabled = true
			_next_round_button.text = "开局中…"
		_refresh_settlement_ready()
	else:
		_set_status("暂时无法准备下一局。")


func _back_home(destination: String = "home") -> void:
	if _leaving: return
	_clear_tile_action()
	_on_discard_drag_state_changed(false, false)
	var was_seated := not _view.is_empty()
	var was_closed := _table_recovery == TableRecovery.CLOSED
	_table_recovery = TableRecovery.NONE
	_stop_room_recovery()
	_leaving = true
	if not _view.is_empty() and not _application_paused and not was_closed:
		_begin_table_transition(false)
	if is_instance_valid(_client):
		await _client.leave()
	if _transition.active: await _transition.finished
	_leaving = false
	_frame.show()
	_table.apply_view({})
	_view.clear()
	_round_projection.clear()
	_published_display = []
	_drag_position = []
	_restore_display_next = false
	_action_key = {"reset": true}
	_shown_cues.clear()
	_completed_presentation.clear()
	_result_seen = ""
	_cancel_flip_reveal()
	_live_ticket.clear()
	_set_status("")
	if was_seated and destination=="home":
		if _mode=="solo":_mode="online"
		destination="connect"
	_show(destination)


func _restore_recent_room() -> void:
	if _screen not in ["home","connect"] or not _view.is_empty() or _restoring or not _recovery_ticket.is_empty():
		return
	var ticket := _settings.remembered_room()
	if ticket.is_empty() or not _require_service():
		return
	_mode = ticket.mode
	if _mode == "online":
		_recovery_ticket = ticket
		_recovery_retries = 0
		_verify_recent_room()
		return
	_connect_recovery(ticket, ticket.address, ticket.port)


func _verify_recent_room() -> void:
	if _recovery_ticket.is_empty() or _application_paused or _restoring:
		return
	if _table_recovery == TableRecovery.RETRYING and _mode == "lan":
		if _client.resume_standby_search():
			_restoring = true
			return
		if not _connect_recovery(_recovery_ticket, _recovery_ticket.address, _recovery_ticket.port):
			_recovery_failed("unavailable")
		return
	if _screen not in ["home","connect"] and _table_recovery != TableRecovery.RETRYING:
		return
	var url: String = _recovery_ticket.get("directory_url", _settings.profile().directory_url)
	if _directory.configure(url):
		_directory.verify_room(_recovery_ticket.room_number, _recovery_ticket.room_instance_id)
	else:
		_recovery_failed("unavailable")


func _recover_online_endpoint(room: Dictionary) -> void:
	if _recovery_ticket.is_empty() or _application_paused or (_screen not in ["home","connect"] and _table_recovery != TableRecovery.RETRYING):
		return
	if not _connect_recovery(_recovery_ticket, room.host, int(room.port)):
		_recovery_failed("unavailable")


func _connect_recovery(ticket: Dictionary, address: String, port: int) -> bool:
	var profile := _profile()
	profile.room_number = ticket.room_number
	_restoring = _client.connect_room(address, port, profile, ticket)
	if _restoring and _table_recovery == TableRecovery.RETRYING and ticket.mode != "lan":
		# A connected socket can still be waiting for its private state and receipt.
		_recovery_timer.start(GameClient.CONNECT_TIMEOUT_MS / 1000.0)
	return _restoring


func _recovery_timeout() -> void:
	if _table_recovery == TableRecovery.RETRYING and _restoring:
		_retry_table()
	else:
		_verify_recent_room()


func _recovery_failed(reason: String) -> void:
	if _recovery_ticket.is_empty():
		return
	if reason == "missing":
		if _transition.active:
			_transition.cancel()
			_board.modulate.a = 1.0
			_board_world.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		_recovery_ticket.clear()
		_remember_ticket({})
		_set_status("")
		if _table_recovery == TableRecovery.RETRYING:
			_table_recovery = TableRecovery.CLOSED
			_recovery_timer.stop()
			_sync_foreground_controls()
	elif _table_recovery == TableRecovery.RETRYING or _recovery_retries < RECOVERY_RETRY_SECONDS.size():
		_recovery_timer.start(RECOVERY_RETRY_SECONDS[mini(_recovery_retries, RECOVERY_RETRY_SECONDS.size() - 1)])
		_recovery_retries += 1
	else:
		_recovery_ticket.clear()
		_set_status("暂时无法核对原房间")


func _stop_room_recovery(suspend: bool = false) -> void:
	if _recovery_ticket.is_empty() and (not _restoring or suspend):
		return
	_recovery_timer.stop()
	_directory.cancel()
	if not suspend:
		_recovery_ticket.clear()
	if _restoring:
		_restoring = false
		if suspend and _table_recovery == TableRecovery.RETRYING:
			_client.cancel_recovery_connection()
		else:
			_leaving = true
			_client.leave()
			_leaving = false
	_set_status("")


func _remember_ticket(ticket: Dictionary) -> void:
	if ticket.get("mode") == "solo":
		return
	if ticket.get("mode") == "online":
		var url: String = _recovery_ticket.get("directory_url", _settings.profile().directory_url)
		if not url.is_empty():
			ticket = ticket.duplicate()
			ticket.directory_url = url
			_voice.set_directory_url(url)
	_live_ticket = ticket.duplicate(true)
	if not _settings.remember_room(ticket):
		_set_status("本机未能保存恢复资料。")


func _retry_table() -> void:
	if _table_recovery != TableRecovery.RETRYING or _application_paused:
		return
	_stop_room_recovery(true)
	_verify_recent_room()


func _session_ended(reason: String) -> void:
	if _leaving:
		return
	var restoring := _restoring
	_restoring = false
	if _table_recovery == TableRecovery.RETRYING:
		_recovery_failed("missing" if reason == "room_expired" else "unavailable")
		return
	if _table_recovery == TableRecovery.CLOSED:
		return
	var room: Dictionary = _view.get("room", {})
	var playing: bool = room.get("rolling", false) or room.get("phase") == Room.Phase.IN_ROUND or _transition.active
	var same_room: bool = not _live_ticket.is_empty() and _live_ticket.room_instance_id == room.get("room_instance_id")
	if playing and same_room and _mode in ["lan", "online"] and reason in ["disconnected", "room_expired"]:
		_table_recovery = TableRecovery.RETRYING
		_recovery_ticket = _live_ticket.duplicate(true)
		_restoring = _client.searching_for_lan_authority()
		_recovery_retries = 0
		_dismiss_leave()
		_cancel_table_input()
		if _screen != "play": _show("play")
		_table_message.text = ""
		_sync_foreground_controls()
		if reason == "room_expired":
			_recovery_failed("missing")
		elif not _application_paused:
			_verify_recent_room.call_deferred()
		return
	if reason == "room_expired":
		var remembered := _settings.remembered_room()
		if restoring or (not _view.is_empty() and _view.room.room_instance_id == remembered.get("room_instance_id")):
			_remember_ticket({})
		_recovery_ticket.clear()
		if restoring:
			_set_status("")
	elif not _recovery_ticket.is_empty():
		if reason in ["disconnected", "connection_failed"]:
			_recovery_failed("unavailable")
		else:
			_recovery_ticket.clear()
		return
	if _screen not in ["home", "connect"]:
		_cancel_flip_reveal()
		_table.apply_view({})
		_view.clear()
		_round_projection.clear()
		_published_display = []
		_drag_position = []
		_action_key = {"reset": true}
		_clear_tile_action()
		_show("home")
	if reason == "disconnected" and not restoring:
		_restore_recent_room.call_deferred()
