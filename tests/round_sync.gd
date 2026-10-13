extends SceneTree
## 枚举与旧字符串协议互转、快照隔离、暗牌隐藏和结算同步。
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := RoundState.new()
	host.set_rng_seed(45)
	host.start_round(0, 3)
	var client := RoundState.new()
	var phase_names := ["idle", "dealing", "playing", "settled"]
	for phase in phase_names.size():
		host.phase = phase
		var wire := host.serialize()
		t.expect(wire.phase == phase_names[phase], "回合阶段发送历史字符串格式")
		client.apply_sync(wire)
		t.expect(client.phase == phase, "接收历史字符串后恢复阶段枚举")
		t.expect(client.serialize() == wire, "接收方没有完整牌墙也能重新生成相同快照")
	host.phase = RoundState.Phase.PLAYING
	var stage_names := ["", "win", "meld", "rob"]
	for stage in stage_names.size():
		host._awaiting_response = {"seat": 1, "disc_seat": 0, "tile": "wan3", "stage": stage, "options": {"can_win": true}}
		var wire := host.serialize()
		t.expect(wire.awaiting_response.stage == stage_names[stage], "响应阶段在网络边界转字符串")
		client.apply_sync(wire)
		t.expect(client._awaiting_response.stage == stage, "旧响应字符串转换回枚举")
		t.expect(host._awaiting_response.stage == stage, "序列化不修改权威状态")
	var kong_names := ["", "exposed", "concealed", "add_kong"]
	for kind in kong_names.size():
		host.last_discard = {"seat": 0, "tile": "tiao1", "after_kong": true, "kong_kind": kind}
		host.last_result = {"items": [[{"kong_kind": kind}]], "points": [{"kong_kind": kind}]}
		var wire := host.serialize()
		t.expect(wire.last_discard.kong_kind == kong_names[kind], "弃牌杠类型仍按字符串发送")
		t.expect(wire.last_result.items[0][0].kong_kind == kong_names[kind] and wire.last_result.points[0].kong_kind == kong_names[kind], "嵌套结算杠类型保留旧协议")
		client.apply_sync(wire)
		t.expect(client.last_discard.kong_kind == kind and client.last_result.items[0][0].kong_kind == kind, "旧快照中的杠类型恢复枚举")
		t.expect(host.last_result.items[0][0].kong_kind == kind, "嵌套结算序列化不修改原数据")
		client.last_result.items[0][0].kong_kind = RoundState.KongKind.NONE
		t.expect(wire.last_result.items[0][0].kong_kind == kong_names[kind], "接收方数据与网络快照互相隔离")
	host.last_result = {}
	host._awaiting_response = {}
	host.players[1].melds = [{"kind": "kong", "tile": "wan5", "concealed": true, "after_discard": 0}]
	host.players[1].discard_count = 0
	for seat in 4:
		var wire := host.serialize_for_seat(seat)
		for player in wire.players:
			if player.seat == seat:
				t.expect(player.concealed == host.players[seat].concealed, "仅本人可见自己的手牌")
			else:
				t.expect(player.concealed.all(func(tile): return tile == "hidden0"), "其他人手牌全部隐藏")
		if seat != 1:
			t.expect(wire.players[1].melds[0].tile == "hidden0", "未亮暗杠不泄露牌名")
		t.expect(host.players[1].melds[0].tile == "wan5", "隐藏处理不改真实暗杠")
	host.players[1].discard_count = 2
	t.expect(host.serialize_for_seat(0).players[1].melds[0].tile == "wan5", "下一轮出牌后暗杠可见")
	host.phase = RoundState.Phase.SETTLED
	t.expect(host.serialize_for_seat(0).players[1].concealed == host.players[1].concealed, "结算公开四家的手牌")
	# 模拟较老客户端/服务端省略后来新增的可选字段。
	var legacy := host.serialize()
	for key in ["dealer_seat", "next_dealer_seat", "prompt_id", "awaiting_response", "last_result", "wall_stacks", "next_chicken_multiplier", "audio_session", "audio_event_id", "audio_events"]:
		legacy.erase(key)
	for player in legacy.players:
		for key in ["discard_history", "discard_ids", "discard_count", "is_dealer", "just_drew", "first_turn_done", "charge_chicken"]:
			player.erase(key)
	client.apply_sync(legacy)
	t.expect(client.phase == RoundState.Phase.SETTLED and client.players.size() == 4, "兼容旧快照缺省字段")
	t.expect(client._awaiting_response.is_empty() and client.last_result.is_empty() and client.next_chicken_multiplier == 1, "可选字段使用历史默认值")
	var idle := RoundState.new()
	client.apply_sync(idle.serialize())
	t.expect(client.phase == RoundState.Phase.IDLE and client.players.is_empty(), "未发牌状态支持往返")
	quit(t.finish("round_sync"))
