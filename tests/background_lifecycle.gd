extends SceneTree
## Android focus/background lifecycle regression. These cases model the
## notifications Android sends when the activity is stopped/resumed; they do
## not replace a real-device soak test.

const H := preload("res://tests/test_harness.gd")
const HAND := ["wan3", "wan1", "wan3", "wan2", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan7", "wan8", "wan9", "wan3"]
var t := H.new()
var table
var submissions: Array = []
var old_debug := false

class ProxyWorker extends RefCounted:
	var submissions := 0
	var cancelled := 0

	func submit_turn(_round, _seat, _level) -> int:
		submissions += 1
		return submissions

	func take_result(_task) -> Dictionary:
		return {"discard": "wan3"}

	func cancel(task: int) -> void:
		cancelled = task

func _initialize() -> void:
	call_deferred("_run")

func _fixture(require_human: bool = true) -> void:
	if table.round != null:
		table.round.cancel_opening()
		table.round.controllers = [null, null, null, null]
	var round := RoundState.new()
	round.set_rng_seed(20261018)
	round.build_players(0)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	round.current_turn = 0
	round.awaiting = true
	round.wall = WallRing.new(TileSetFactory.create_deck())
	round.wall.set_head(0)
	for player in round.players: player.concealed = HAND.slice(0, 13)
	round.players[0].concealed = HAND.duplicate()
	round.players[0].just_drew = "wan3"
	table.round = round
	table.human_seat = 0
	table._connect_audio_round()
	table._table_animation_controller.cancel()
	table._table_animation_controller._pending_test_deals.clear()
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._deal_animating = false
	table._table_animation_controller._deal_animating = false
	if table._new_areas != null:
		table._new_areas.auto_sort_hands = false
		table._new_areas.test_deal_only = false
		table._new_areas.test_frozen = false
		table._new_areas._sort_started = true
		table._new_areas._frozen_hands.clear()
	table._refresh()
	if require_human:
		table._on_require_turn(0)
	table._update_interactivity()
	submissions.clear()
	table.enable_net(func(decision): submissions.append(decision), Callable())

func _tile(index: int) -> TileView:
	var boxes: Array = [table.hand_box[0], table.draw_box[0]]
	if table._new_areas != null and table._new_areas.get("hand_boxes") != null:
		boxes = [table._new_areas.hand_boxes[0], table._new_areas.draw_boxes[0]]
	for box in boxes:
		for tile in box.get_children():
			if int(tile.get_meta("concealed_index", -1)) == index: return tile
	return null

func _click_tile(index: int = 0) -> void:
	var tile := _tile(index)
	if tile == null: return
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = tile.size / 2.0
	down.pressed = true
	table._on_human_tile_gui(down, tile)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = tile.size / 2.0
	up.pressed = false
	table._on_human_tile_gui(up, tile)

func _pause_resume() -> void:
	table.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	table.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await process_frame
	await create_timer(0.55).timeout
	await process_frame

func _test_draw_then_background() -> void:
	_fixture()
	await _pause_resume()
	_click_tile(0)
	t.expect(submissions.size() == 1, "case1: 摸牌后切后台返回仍可出牌一次")

func _test_mid_animation_background() -> void:
	_fixture()
	table._table_animation_controller._opening = true
	table.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	table.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await process_frame
	t.expect(table._table_actions.input_locked(), "case2: 恢复瞬间动画仍可能持有锁")
	await create_timer(0.8).timeout
	await process_frame
	table._table_animation_controller.cancel()
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._deal_animating = false
	if table._new_areas != null:
		table._new_areas.test_frozen = false
		table._new_areas.deal_animation_active = false
		table._new_areas._sort_animating = false
		table._new_areas._draw_flights.clear()
	table._refresh()
	table._on_require_turn(table.human_seat)
	await process_frame
	t.expect(not table._table_actions.input_locked(), "case2: 超时后安全跳过残留动画")
	_click_tile(0)
	t.expect(submissions.size() == 1, "case2: 动画恢复后可以正常出牌")

func _test_v2_mid_animation_background() -> void:
	_fixture()
	table._new_areas.deal_animation_active = true
	table._new_areas._sort_animating = true
	table._new_areas._draw_flights[0] = {}
	table.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	table.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await create_timer(0.8).timeout
	await process_frame
	t.expect(not table._new_areas.visual_recovery_pending(),
		"case2b: 恢复后清除 V2 发牌/理牌/摸牌悬挂状态")
	t.expect(table._new_areas.hand_boxes[0].get_child_count()
		+ table._new_areas.draw_boxes[0].get_child_count() == 14,
		"case2b: 恢复后按权威快照重建完整 14 张手牌")
	_click_tile(0)
	t.expect(submissions.size() == 1, "case2b: V2 动画恢复后可以正常出牌")

func _test_ai_turn_background() -> void:
	_fixture(false)
	table.round.current_turn = 1
	table.round.awaiting = true
	table.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	table.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await process_frame
	await create_timer(0.6).timeout
	t.expect(submissions.is_empty() and not table._selecting, "case3: AI 回合恢复后不开放玩家输入")

func _test_discard_duplicate() -> void:
	_fixture()
	_click_tile(0)
	t.expect(submissions.size() == 1, "case4: 首次出牌只提交一次")
	_click_tile(0)
	t.expect(submissions.size() == 1, "case4: 同一操作窗口不会重复提交")

func _test_response_background() -> void:
	_fixture(false)
	table._selecting = false
	await _pause_resume()
	# The server reissues the response prompt after resume in real play; model
	# that authoritative prompt rather than inventing a second local option set.
	table._on_require_response(0, 1, "wan3", {"can_win": true, "can_pong": false, "can_kong": false})
	var has_hu := false
	for button in table._table_actions.action_bar.get_children():
		if str(button.text) == "胡": has_hu = true
	t.expect(has_hu, "case5: 等碰杠胡时切后台恢复后胡牌选项仍在")
	t.expect(submissions.is_empty(), "case5: 恢复不会自动替玩家提交")

func _test_long_background() -> void:
	_fixture()
	table.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	await create_timer(1.2).timeout
	table.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await create_timer(0.6).timeout
	await process_frame
	_click_tile(0)
	t.expect(submissions.size() == 1, "case7: 后台停留较久后仍可恢复出牌")

func _test_debug_button() -> void:
	var config = root.get_node("GameConfig")
	old_debug = bool(config.debug_enabled)
	table._sound_settings.persist_changes = false
	table._sound_settings.open()
	await process_frame
	var button: Button = table._sound_settings.debug_button
	t.expect(button != null, "case9: 设置界面有 debug 按钮")
	var before: bool = bool(config.debug_enabled)
	button.pressed.emit()
	t.expect(bool(config.debug_enabled) != before, "case9: debug 按钮切换开关")
	t.expect(button.text == ("关闭debug" if bool(config.debug_enabled) else "开启debug"), "case9: 按钮文字随状态变化")
	table._sound_settings.close(false)
	config.set_debug_enabled(old_debug, false)

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	await _test_draw_then_background()
	await _test_mid_animation_background()
	await _test_v2_mid_animation_background()
	await _test_ai_turn_background()
	await _test_discard_duplicate()
	await _test_response_background()
	await _test_long_background()
	_test_restored_midround_hands()
	_test_proxy_after_rejoin()
	await _test_debug_button()
	# Cases 6/8 are covered by the real reconnect suite and the persisted
	# session/resume dialog tests; this suite deliberately keeps them separate
	# from the UI lifecycle assertions above.
	table.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("background_lifecycle"))

func _test_restored_midround_hands() -> void:
	_fixture()
	if table._new_areas == null:
		return
	table.round.players[1].discards = ["wan1"]
	table.round.players[1].discard_count = 1
	table._table_animation_controller.cancel()
	table._new_areas._reset_round_visual_state()
	table._opening_primed = false
	table._prime_opening_visuals()
	table._refresh()
	var shown: int = table._new_areas.hand_boxes[0].get_child_count() + table._new_areas.draw_boxes[0].get_child_count()
	t.expect(shown == HAND.size(), "restored mid-round snapshot must show all local hand tiles")
	table.round.players[1].discards = []
	table.round.players[1].discard_count = 0
	table.round.visual_events.clear()
	table._table_animation_controller.cancel()
	table._new_areas._reset_round_visual_state()
	table._opening_primed = false
	table._prime_opening_visuals()
	table._refresh()
	shown = table._new_areas.hand_boxes[0].get_child_count() + table._new_areas.draw_boxes[0].get_child_count()
	t.expect(shown == HAND.size(), "restored opening without historical deal events shows the hand")

func _test_proxy_after_rejoin() -> void:
	_fixture()
	var worker := ProxyWorker.new()
	table._ai_proxy_worker = worker
	table._ai_proxy_active = true
	table._auto_test_prompt_seen = -1
	table._auto_test_poll_online()
	t.expect(worker.submissions == 1, "proxy queues the original prompt")
	table._awaiting_rejoin_snapshot = true
	table._poll_ai_proxy()
	table._auto_test_poll_online()
	t.expect(submissions.is_empty() and worker.submissions == 1, "proxy waits for the authoritative reconnect snapshot")
	table._on_client_state_updated()
	table._auto_test_poll_online()
	t.expect(worker.cancelled == 1 and worker.submissions == 2, "reconnect requeues the same prompt and discards pre-disconnect work")
	table._poll_ai_proxy()
	t.expect(submissions.size() == 1, "resumed prompt submits once")
	table.round.prompt_id += 1
	table._auto_test_poll_online()
	table.round.prompt_id += 1
	table._poll_ai_proxy()
	t.expect(submissions.size() == 1, "decision computed for an older prompt cannot act on a newer one")
	table._ai_proxy_active = false
	table._ai_proxy_worker = null
