extends SceneTree
const H := preload("res://tests/test_harness.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
const SMOKE := preload("res://tests/smoke_round.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for seed_value in range(50):
		var original := RoundState.new()
		original.set_rng_seed(100 + seed_value)
		original.controllers = []
		for seat in 4: original.controllers.append(SMOKE.SimpleAi.new("AI"))
		original.next_dealer_seat = seed_value % 4
		original.next_chicken_multiplier = 2 if seed_value % 2 == 0 else 1
		original.start_round(0, seed_value % 6 + 1)
		var record := original.replay_record()
		t.expect(original.phase == RoundState.Phase.SETTLED and not record.actions.is_empty(), "完整对局自动记录实际操作")
		t.expect(str(record.actions[0].get("before", "")) == "", "正常对局不再为每次出牌计算全量状态指纹")
		t.expect(not str(record.get("final", {}).get("fingerprint", "")).is_empty(), "结算时仍保留一次最终指纹用于回放校验")
		var data: Variant = JSON.parse_string(JSON.stringify(record))
		var restored := REPLAY.replay(data)
		if not t.expect(restored.ok, "种子%d重放第%d步：%s" % [100 + seed_value, restored.event_index, restored.error]):
			break
		t.expect(JSON.stringify(JSON.parse_string(JSON.stringify(restored.round.last_result))) == JSON.stringify(JSON.parse_string(JSON.stringify(original.last_result))), "重放手牌、积分、翻鸡和庄家完全一致")
		t.expect(restored.round.wall.debug_ring_head_tail() == original.wall.debug_ring_head_tail(), "头尾摸牌与剩余牌墙一致")
		t.expect(restored.round._recorder.record.is_empty(), "重放不递归生成新记录")
		if seed_value == 0:
			var file := "user://replay-test.json"
			t.expect(original.export_replay(file) == file, "可导出诊断文件")
			t.expect(REPLAY.replay(REPLAY.load_record(file)).ok, "真实文件读取后可重放")
			DirAccess.remove_absolute(file)
			var corrupted: Dictionary = data.duplicate(true)
			corrupted.wall.head = 108
			t.expect(not REPLAY.replay(corrupted).ok, "损坏牌墙位置安全拒绝")
			corrupted = data.duplicate(true)
			corrupted.initial.players[0].erase("concealed")
			t.expect(not REPLAY.replay(corrupted).ok, "缺少玩家字段安全拒绝")
			corrupted = data.duplicate(true)
			corrupted.actions[0].seat = 4
			t.expect(not REPLAY.replay(corrupted).ok, "操作座位越界安全拒绝")
			data.actions[0].decision = {"discard": "invalid"}
			t.expect(not REPLAY.replay(data).ok, "篡改操作时明确报告失败")
	# 未完成的对局同样可用于诊断。
	var partial := RoundState.new()
	partial.start_round(0, 3)
	partial.players[0].name_label = "房主昵称"
	partial._recorder.update_players(partial)
	partial.submit_turn(0, {"discard": partial.players[0].just_drew})
	var snapshot := partial.replay_record()
	var restored := REPLAY.replay(JSON.parse_string(JSON.stringify(snapshot)))
	t.expect(restored.ok and REPLAY.fingerprint(restored.round) == REPLAY.fingerprint(partial), "未结束牌局也能恢复当前状态")
	t.expect(not REPLAY.replay({}).ok and not REPLAY.replay({"schema": 99}).ok, "损坏和不支持的日志返回错误")
	_test_special_actions()
	quit(t.finish("round_replay"))

func _assert_replay(round: RoundState, label: String) -> void:
	var replay := REPLAY.replay(JSON.parse_string(JSON.stringify(round.replay_record())))
	t.expect(replay.ok, "%s 重放第%d步：%s" % [label, replay.event_index, replay.error])

func _fixture() -> RoundState:
	var round := RoundState.new()
	round.build_players(0)
	round.phase = RoundState.Phase.PLAYING
	round.controllers = [null, null, null, null]
	round.wall = WallRing.new(TileSetFactory.create_deck())
	round.wall.set_head(0)
	for player in round.players:
		player.concealed = ["wan1", "wan2", "wan4", "wan5", "wan7", "wan8", "tong1", "tong3", "tong5", "tong7", "tong9", "tiao2", "tiao4"]
	return round

func _start_fixture(round: RoundState) -> void:
	round._recorder.begin(round)
	round._begin_turn()

func _test_special_actions() -> void:
	var dark := _fixture()
	dark.players[0].concealed = ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan4", "wan5", "wan7", "wan8", "tong1", "tong3", "tong5", "tong7"]
	dark.wall._ring[0] = "tiao1"
	_start_fixture(dark)
	t.expect(dark.submit_turn(0, {"kong_declares": ["tiao1"]}), "记录暗杠和尾部补牌")
	t.expect(dark.submit_turn(0, {"discard": dark.players[0].just_drew}), "暗杠后正常出牌")
	_assert_replay(dark, "暗杠")
	for robbed in [false, true]:
		var added := _fixture()
		added.players[0].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 2}]
		added.players[0].concealed = ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
		if robbed: added.players[1].concealed = ["tiao1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong1", "tong2", "tong3", "tong4", "tong5", "tong6"]
		added.wall._ring[0] = "tiao1"
		_start_fixture(added)
		t.expect(added.submit_turn(0, {"add_kong": ["tiao1"]}), "记录加杠宣告")
		if robbed: t.expect(added.submit_response(1, "tiao1", {"action": "win"}), "记录抢杠烧鸡")
		else: t.expect(added.players[0].melds[0].kind == "add_kong", "无抢杠时完成加杠")
		_assert_replay(added, "抢杠" if robbed else "加杠")
	for action in ["pong", "kong"]:
		var claimed := _fixture()
		claimed.wall._ring[0] = "tiao1"
		claimed.players[1].concealed = (["tiao1", "tiao1"] if action == "pong" else ["tiao1", "tiao1", "tiao1"]) + ["wan1", "wan2", "wan4", "wan5", "wan7", "wan8", "tong1", "tong3", "tong5", "tong7"]
		_start_fixture(claimed)
		t.expect(claimed.submit_turn(0, {"discard": "tiao1"}), "记录冲锋鸡出牌")
		t.expect(claimed.submit_response(1, "tiao1", {"action": action}), "记录碰杠转移鸡牌归属")
		_assert_replay(claimed, action)
	var ready := _fixture()
	ready.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
	ready.wall._ring[0] = "tiao9"
	_start_fixture(ready)
	t.expect(ready.submit_turn(0, {"discard": "tiao9", "ready": true}), "记录首次出牌报听")
	_assert_replay(ready, "报听")
