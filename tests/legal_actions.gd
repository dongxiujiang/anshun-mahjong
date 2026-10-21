extends SceneTree
const H := preload("res://tests/test_harness.gd")
const LegalActions := preload("res://scripts/core/LegalActions.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _fixture() -> RoundState:
	var round := RoundState.new()
	round.start_round(0, 3)
	return round

func _run() -> void:
	var round := _fixture()
	var player: PlayerState = round.players[0]
	player.concealed = ["tiao1", "tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3", "tong1", "tong2", "tong3", "wan9"]
	player.melds = [{"kind": "pung", "tile": "wan9", "from_seat": 2}]
	player.just_drew = "wan9"
	var options := round.legal_turn_options(0)
	t.expect(options.kong_declares == ["tiao1"] and options.add_kong == ["wan9"], "暗杠加杠统一清单")
	for tile in options.discards: t.expect(round._valid_turn(0, {"discard": tile}), "允许的每张弃牌都通过校验")
	t.expect(not round._valid_turn(0, {"kong_declares": ["tiao1", "wan2"]}), "拒绝多牌和混合动作")
	t.expect(not round._valid_turn(0, {"kong_declares": ["tiao1"], "ready": true}), "暗杠和报听分两次提交")
	t.expect(not round._valid_turn(0, {"add_kong": ["wan9"], "self_win": true}), "不允许凭合法加杠绕过自摸校验")
	t.expect(not round._valid_turn(0, {"kong_declares": "tiao1"}), "错误参数类型安全拒绝")
	options.discards.clear()
	t.expect(not round.legal_turn_options(0).discards.is_empty(), "调用方不能污染缓存")
	player.ready = true
	options = round.legal_turn_options(0)
	t.expect(options.discards == ["wan9"] and options.kong_declares.is_empty() and options.add_kong.is_empty(), "报听只允许打刚摸的牌")
	t.expect(not round._valid_turn(0, {"discard": "wan1"}), "报听不能提交手中其他牌")
	player.ready = false
	round.wall.remaining = 0
	t.expect(round.legal_turn_options(0).kong_declares.is_empty(), "墙空不能杠，缓存随墙更新")
	player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9", "tiao9"]
	player.melds = []
	player.just_drew = "tiao9"
	t.expect(round.legal_turn_options(0).ready_discards.has("tiao9"), "统一枚举首次出牌可报听的牌")
	player.first_turn_done = true
	t.expect(round.legal_turn_options(0).ready_discards.is_empty(), "第一次机会过后报听关闭")
	player.first_turn_done = false
	t.expect(round.allowed_actions(1).is_empty() and round.allowed_actions(0).kind == "turn", "只有当前座位能提交操作")
	var current := round.allowed_actions(0)
	t.expect(current.options.discards == round.legal_turn_options(0).discards, "界面当前清单与权威合法清单一致")
	t.expect(LegalActions.validate_turn_submission(round, 0, {"discard": round.players[0].just_drew}), "统一入口接受当前座位合法出牌")
	t.expect(not LegalActions.validate_turn_submission(round, 1, {"discard": round.players[0].just_drew}), "统一入口拒绝非当前座位出牌")
	var before := round.serialize()
	t.expect(not round.submit_turn(0, {"discard": "invalid"}) and round.serialize() == before, "非法提交不改变牌局")
	round.players[1].concealed = ["tiao1", "tiao1", "tiao1"]
	var response := round.legal_response_options(1, 0, "tiao1", RoundState.ResponseStage.MELD)
	t.expect(response.can_pong and not response.can_kong, "牌墙为空时三张同牌可碰但不能杠（实际=%s）" % str(response))
	response = round.legal_response_options(1, 0, "tiao1", RoundState.ResponseStage.WIN)
	t.expect(not response.can_pong and not response.can_kong, "胡牌响应阶段不显示碰杠")
	response = round.legal_response_options(1, 0, "tiao1", RoundState.ResponseStage.ROB)
	t.expect(not response.can_pong and not response.can_kong, "抢杠响应阶段不显示碰杠")
	var invalid := round.legal_response_options(-1, 0, "tiao1", RoundState.ResponseStage.MELD)
	t.expect(not invalid.can_win and not invalid.can_pong, "非法座位返回空选项")
	quit(t.finish("legal_actions"))
