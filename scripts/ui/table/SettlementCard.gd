extends "res://scripts/ui/table/TableComponent.gd"
## 结算结束后只显示桌面底部的下一局按钮与联机准备人数、倒计时。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var _post_controls: Control
var _next_round_button: Button
var _post_next_button: Button:
	get: return _next_round_button
var _next_round_status: Label
var _next_round_hint: Label
var _return_seat_button: Button

func build() -> void:
	_post_controls = table._box(table.surface)
	_post_controls.name = "PostSettlementControls"
	_post_controls.z_index = 250
	_next_round_button = table._button("下一局", table._next_round, Vector2(440, 84), true)
	_next_round_button.name = "NextRoundButton"
	_next_round_button.add_theme_font_size_override("font_size", UI.NEXT_ROUND_FONT_SIZE)
	_post_controls.add_child(_next_round_button)
	_next_round_status = table._label(_post_controls, "", Vector2(0, 0), Vector2(1040, 30), 28, UI.GOLD)
	_next_round_status.name = "NextRoundReadiness"
	_next_round_hint = table._label(_post_controls, "", Vector2(0, 28), Vector2(1040, 28), 24, UI.MUTED)
	_next_round_hint.name = "NextRoundCountdown"
	# Same size and style as the next-round button; in online mode it takes the
	# left slot and the next-round button moves into the right slot.
	_return_seat_button = table._button("返回座位", _return_to_seat, UI.DISCARD_BUTTON_SIZE, true)
	_return_seat_button.name = "ReturnToSeatButton"
	_return_seat_button.add_theme_font_size_override("font_size", 32)
	_post_controls.add_child(_return_seat_button)
	refresh_layout()
	_post_controls.hide()

func _return_to_seat() -> void:
	# 返回座位由结算页发起房间投票；所有真人同意后才回大厅/座位选择。
	# 退出房间是独立的直接退出动作，不再和返回座位混在同一个确认框里。
	var network = table._net_node()
	if network != null and network.has_method("request_return_to_lobby"):
		network.request_return_to_lobby()

const ONLINE_BUTTON_SIZE := Vector2(340, UI.DISCARD_BUTTON_SIZE.y)

func refresh_layout() -> void:
	if not is_instance_valid(_post_controls): return
	var online: bool = table._net_mode() != ""
	_post_controls.size = Vector2(ONLINE_BUTTON_SIZE.x * 2.0 + 12.0 if online else UI.DISCARD_BUTTON_SIZE.x, UI.DISCARD_BUTTON_SIZE.y)
	_post_controls.position = Vector2((table._design_size().x - _post_controls.size.x) / 2.0, table._design_size().y - _post_controls.size.y - 8.0)
	# The readiness/countdown text lives inside the button now; keep the old
	# labels as hidden compatibility fields for regression probes.
	_next_round_status.visible = false
	_next_round_hint.visible = false
	if is_instance_valid(_return_seat_button):
		_return_seat_button.visible = online
		_return_seat_button.position = Vector2.ZERO
		_return_seat_button.size = ONLINE_BUTTON_SIZE if online else UI.DISCARD_BUTTON_SIZE
		_return_seat_button.add_theme_font_size_override("font_size", 30 if online else 32)
	_next_round_button.position = Vector2(ONLINE_BUTTON_SIZE.x + 12.0, 0) if online else Vector2.ZERO
	_next_round_button.size = ONLINE_BUTTON_SIZE if online else UI.DISCARD_BUTTON_SIZE
	_next_round_button.add_theme_font_size_override("font_size", 30 if online else UI.NEXT_ROUND_FONT_SIZE)

func show_post_settlement_controls() -> void:
	if not is_instance_valid(_post_controls) or table.round == null or table.round.phase != RoundState.Phase.SETTLED: return
	refresh_layout()
	_post_controls.show()
	_refresh_next_round_controls()

func hide_post_settlement_controls() -> void:
	if is_instance_valid(_post_controls): _post_controls.hide()

func _next_round() -> void:
	if table.round == null or table.round.phase != RoundState.Phase.SETTLED or not table._settlement_animation_done(): return
	if table._net_mode() == "":
		table.new_game()
		return
	var network = table._net_node()
	if network == null or network.lobby.get("ready_round", -1) != network.round_number: return
	var seats: Array = network.lobby.get("seats", [])
	if seats.size() != 4 or table.human_seat not in range(4): return
	var me: Dictionary = seats[table.human_seat]
	network.set_ready(not bool(me.get("ready", false)))

func _refresh_next_round_controls() -> void:
	if not is_instance_valid(_next_round_button): return
	if table.round == null or table.round.phase != RoundState.Phase.SETTLED:
		hide_post_settlement_controls()
		return
	if table._net_mode() == "":
		_next_round_button.text = "下一局"
		_next_round_button.disabled = not table._settlement_animation_done()
		_next_round_button.add_theme_font_size_override("font_size", UI.NEXT_ROUND_FONT_SIZE)
		return
	var network = table._net_node()
	var state: Dictionary = network.lobby if network != null else {}
	var seats: Array = state.get("seats", [])
	var ready_round: bool = network != null and state.get("ready_round", -1) == network.round_number and seats.size() == 4 and table.human_seat in range(4)
	_next_round_button.disabled = not ready_round or not table._settlement_animation_done()
	_next_round_button.add_theme_font_size_override("font_size", 30)
	_next_round_button.text = "准备下一局"
	if not ready_round:
		_next_round_button.text = "准备下一局 --/4"
		if is_instance_valid(_return_seat_button):
			_return_seat_button.text = "返回座位 --/4"
			_return_seat_button.disabled = true
		_next_round_status.text = "下一局准备"
		_next_round_hint.text = "等待房间同步…"
		return
	var ready_count := 0
	var human_count := 0
	for member in seats:
		if bool(member.get("ai", false)): continue
		human_count += 1
		if bool(member.get("ready", false)): ready_count += 1
	var return_vote: Dictionary = state.get("return_vote", {})
	var vote_humans: Array = return_vote.get("humans", [])
	var vote_yes: Dictionary = return_vote.get("yes", {})
	var returned := 0
	for voter in vote_humans:
		if bool(vote_yes.get(int(voter), false)): returned += 1
	if is_instance_valid(_return_seat_button):
		_return_seat_button.text = "返回座位 %d/%d" % [returned, maxi(1, vote_humans.size())]
		_return_seat_button.disabled = vote_humans.is_empty()
	var seconds := int(state.get("countdown", -1))
	var ready := bool(seats[table.human_seat].get("ready", false))
	var all_ready := human_count > 0 and ready_count >= human_count
	# Only human seats participate in the countdown/readiness display; AI
	# seats are automatically ready.
	if seconds >= 0 and all_ready:
		_next_round_button.text = "全部准备，%d 秒后开始" % seconds
	else:
		_next_round_button.text = "准备下一局 %d/%d" % [ready_count, maxi(1, human_count)]
	_next_round_status.text = "下一局准备  %d / %d" % [ready_count, maxi(1, human_count)]
	_next_round_hint.text = "全部准备，%d 秒后自动开局" % seconds if seconds >= 0 and all_ready else "等待其他玩家准备" if ready else "准备后开始下一局"
