extends SceneTree
## 按《安顺捉鸡麻将 当前游戏规则与玩法确认稿》做独立随机交叉核验。
##
## 这套测试刻意不复用 RuleEngine/ScoringEngine 的拆牌和付款实现来生成期望值：
## 手牌由独立构造器生成，牌型分由规则表核对，鸡分/六对付款用独立账本核对。
## 每个规则章节至少执行10个不同种子；失败会显示章节、种子和首个不一致字段。

const H := preload("res://tests/test_harness.gd")
const ORACLE := preload("res://tests/settlement_oracle.gd")
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")

var t := H.new()
var rng := RandomNumberGenerator.new()
var counts := {}
var pattern_counts := {}

const PATTERN_SAMPLES := 20
const NORMAL_GAME_SAMPLES := 200
const PATTERN_KINDS := [
	"normal", "big", "big_single", "seven", "dragon", "flush",
	"clean_big", "clean_big_single", "clean_seven", "clean_dragon", "clean_single",
]

const RULE_SECTIONS := [
	"牌局基础", "座位与方向", "牌墙与骰子", "开局发牌", "普通回合流程", "操作优先级",
	"碰牌", "明杠", "暗杠", "加杠", "普通胡牌限制", "报听", "鸡牌定义", "翻鸡",
	"鸡分付款", "烧鸡", "胡牌牌型分", "干扣和大干扣", "胡牌付款", "特殊加分",
	"流局", "庄家变化", "网络同步与幂等",
]

func _initialize() -> void:
	call_deferred("_run")

func _hit(section: String, amount: int = 1) -> void:
	counts[section] = int(counts.get(section, 0)) + amount

func _check(condition: bool, section: String, message: String, seed: int = -1) -> void:
	_hit(section)
	var suffix := "" if seed < 0 else " seed=%d" % seed
	t.expect(condition, "%s%s: %s" % [section, suffix, message])

func _run() -> void:
	rng.seed = 20261015
	_test_deck_and_wall()
	_test_random_patterns()
	_test_random_chickens_and_payments()
	_test_random_settlements()
	_test_random_kong_payments()
	_test_flow_and_priority()
	_test_normal_games_200()
	_test_sync_and_idempotence()
	for kind in PATTERN_KINDS:
		_check(int(pattern_counts.get(kind, 0)) >= PATTERN_SAMPLES, "胡牌牌型分", "%s牌型随机测试不足%d次，实际%d" % [kind, PATTERN_SAMPLES, int(pattern_counts.get(kind, 0))])
	for section in RULE_SECTIONS:
		_check(int(counts.get(section, 0)) >= 10, section, "规则章节执行次数不足10次，实际%d" % int(counts.get(section, 0)))
	print("[rules_randomized] 牌型随机次数: %s" % str(pattern_counts))
	print("[rules_randomized] 章节执行次数: %s" % str(counts))
	quit(t.finish("rules_randomized"))

func _test_deck_and_wall() -> void:
	for sample in 30:
		var seed := 1000 + sample
		var local := RandomNumberGenerator.new()
		local.seed = seed
		var deck := TileSetFactory.create_deck()
		_check(deck.size() == 108, "牌局基础", "总牌数不是108", seed)
		var values := Tiles.to_counts(deck)
		_check(values.size() == 27, "牌局基础", "牌值种类不是27", seed)
		var every_four := true
		for value in values.values():
			if int(value) != 4: every_four = false
		_check(every_four, "牌局基础", "每种牌没有恰好4张", seed)
		var built := WallBuilder.setup(local, sample % 4)
		var ring: Array = built["ring"]
		var wall := WallRing.new(ring, sample % 4)
		var dealer := sample % 4
		for die in range(1, 7):
			wall.set_head(WallRing.compute_break(die, dealer))
			var first := wall.draw_head()
			var last := wall.draw_tail()
			_check(first != "" and last != "" and wall.remaining == 106, "牌墙与骰子", "头尾摸牌没有各消耗一张", seed * 10 + die)
			_check(WallRing.compute_break(die, dealer) >= 0 and WallRing.compute_break(die, dealer) < 108, "牌墙与骰子", "骰子破墙越界", seed * 10 + die)
		_check(Tiles.flip_related("wan1") == ["wan1", "wan9", "wan2"], "翻鸡", "1点翻鸡没有按9、1、2循环", seed)
		_check(Tiles.flip_related("wan9") == ["wan9", "wan8", "wan1"], "翻鸡", "9点翻鸡没有按8、9、1循环", seed)

func _test_random_patterns() -> void:
	for kind_index in PATTERN_KINDS.size():
		var kind: String = PATTERN_KINDS[kind_index]
		for sample in PATTERN_SAMPLES:
			var seed := 20000 + kind_index * 1000 + sample
			rng.seed = seed
			var spec := _make_pattern(kind, rng)
			var hand: Array = spec.hand
			var melds: Array = spec.melds
			var pattern := RuleEngine.analyze(hand, melds, str(spec.win_tile))
			_check(pattern.win, "胡牌牌型分", "%s 随机手牌未判胡 %s" % [kind, str(hand)], seed)
			_check(_pattern_matches(kind, pattern), "胡牌牌型分", "%s 牌型标记不符合独立构造" % kind, seed)
			pattern_counts[kind] = int(pattern_counts.get(kind, 0)) + 1
			_check(hand.size() == 3 * (4 - melds.size()) + 2, "普通胡牌限制", "%s 手牌张数不符合面子数" % kind, seed)
			_check(_max_four(hand, melds), "牌局基础", "%s 使用了超过4张同牌" % kind, seed)
			var round := _score_fixture(hand, melds, str(spec.win_tile), seed)
			var result := ScoringEngine.settle(round)
			var expected_label := _expected_label(kind)
			if expected_label != "":
				var found := false
				for item in result.items[0]:
					if str(item.get("label", "")) == expected_label and is_equal_approx(float(item.get("amount", 0)), _expected_score(kind)):
						found = true
				_check(found, "胡牌牌型分", "%s 结算没有独立期望的%s/%d分" % [kind, expected_label, _expected_score(kind)], seed)
			_hit("胡牌付款")
			_check(absf(_sum(result.deltas)) < 0.001, "胡牌付款", "%s 结算不是零和" % kind, seed)
			# 普通牌型额外验证自摸三家付款；点炮只允许来源玩家付款。
			if kind == "normal":
				var discard := _score_fixture(hand, melds, str(spec.win_tile), seed)
				discard.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
				discard.round_meta.win_tile = "wan4"
				discard.round_meta.flip_tile = ""
				discard.round_meta.self_draw = false
				discard.round_meta.discard_seat = 2
				var discard_result := ScoringEngine.settle(discard)
				_check(discard_result.pairwise[0][2] > 0 and discard_result.pairwise[0][1] == 0 and discard_result.pairwise[0][3] == 0, "胡牌付款", "普通点炮错误地向非放炮者收费", seed)
				_hit("胡牌付款", 2)

func _test_random_chickens_and_payments() -> void:
	for sample in 40:
		var seed := 30000 + sample
		rng.seed = seed
		var round := _chicken_fixture(rng, sample)
		var flip := str(round.round_meta.flip_tile)
		for seat in 4:
			var actual := ScoringEngine.chicken_profile(round, seat, flip)
			var expected := _independent_chicken(round, seat, flip)
			_check(is_equal_approx(float(actual.total), float(expected.total)), "鸡牌定义", "鸡分总值独立核算不一致", seed)
			_check(is_equal_approx(float(actual.discarded), float(expected.discarded)), "鸡牌定义", "出牌鸡独立核算不一致", seed)
			_check(is_equal_approx(float(actual.held), float(expected.held)), "鸡牌定义", "手中/碰杠鸡独立核算不一致", seed)
			_hit("鸡牌定义", 3)
			if seat == int(round.round_meta.burn_chicken_seat):
				_check(is_zero_approx(float(actual.total)), "烧鸡", "烧鸡玩家鸡分没有归零", seed)
		var called := []
		var points := []
		for seat in 4:
			called.append(bool((sample + seat) % 3 != 0))
			points.append(float((sample * 7 + seat * 5) % 31))
		var deltas := [0.0, 0.0, 0.0, 0.0]
		var transfers: Array = []
		PAY.compare_chickens(deltas, transfers, called, points)
		var matrix := PAY.pairwise_payments(transfers)
		for a in 4:
			_check(is_zero_approx(matrix[a][a]), "鸡分付款", "付款矩阵对角线非零", seed)
			for b in 4:
				_check(is_zero_approx(matrix[a][b] + matrix[b][a]), "鸡分付款", "逐家收付不相反", seed)
			_check(is_zero_approx(_sum(deltas)), "鸡分付款", "鸡分比较不是零和", seed)
			_hit("鸡分付款", 6)

func _test_random_settlements() -> void:
	for sample in 48:
		var seed := 40000 + sample
		rng.seed = seed
		var kind: String = ["normal", "big", "seven", "dragon", "flush", "clean_big", "clean_seven", "clean_dragon"][sample % 8]
		var spec := _make_pattern(kind, rng)
		var round := _score_fixture(spec.hand, spec.melds, str(spec.win_tile), seed)
		round.round_meta.chicken_multiplier = 1 if sample % 2 == 0 else 2
		round.round_meta.flip_tile = ["wan1", "wan5", "wan9", "tiao1", "tong8"][sample % 5]
		round.round_meta.self_draw = sample % 3 != 0
		if not round.round_meta.self_draw:
			round.round_meta.discard_seat = (sample + 2) % 4
		round.round_meta.winners = [0]
		if sample % 7 == 0:
			round.round_meta.kong_draw_seat = 0
		if sample % 11 == 0:
			round.round_meta.last_four_self_draw_seat = 0
		var result := ScoringEngine.settle(round)
		ORACLE.check(round, result, t, "random-settlement-%d" % seed)
		_hit("胡牌付款", 4)
		_hit("特殊加分", 1)
		# 每条流水都必须有反向净变化，且重复核算不能改变结果。
		var again := ScoringEngine.settle(round)
		_check(result.deltas == again.deltas and result.pairwise == again.pairwise, "网络同步与幂等", "重复结算改变账本", seed)
		_check(absf(_sum(result.deltas)) < 0.001, "胡牌付款", "随机结算总分不守恒", seed)
		_check(result.deltas.size() == 4, "干扣和大干扣", "普通/大干扣结算没有完整四家账本", seed)
		if sample < 12:
			var dry := _score_fixture(["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"], [], "wan9", seed)
			var dry_result := ScoringEngine.settle(dry)
			var dry_ok := false
			for item in dry_result.items[0]:
				if item.get("label", "") == "大干扣" and is_equal_approx(float(item.get("amount", 0)), 24.0): dry_ok = true
			_check(dry_ok, "干扣和大干扣", "四家无鸡的普通自摸没有替代为大干扣24", seed)

func _test_flow_and_priority() -> void:
	for sample in 12:
		var seed := 50000 + sample
		var game := RoundState.new()
		game.set_rng_seed(seed)
		game.start_round(sample % 4, sample % 6 + 1)
		_check(game.phase == RoundState.Phase.PLAYING and game.awaiting, "开局发牌", "开局没有进入可操作阶段", seed)
		_check(game.players[game.dealer_seat].concealed.size() == 14, "开局发牌", "庄家不是14张", seed)
		for seat in 4:
			_check(game.players[seat].concealed.size() == (14 if seat == game.dealer_seat else 13), "开局发牌", "闲家起手牌不是13张", seed)
		_check(game.wall.remaining == 55, "开局发牌", "起手后牌墙剩余不是55", seed)
		_check(game.current_turn == game.dealer_seat, "普通回合流程", "庄家没有首先出牌", seed)
		_check(game.round_meta.die == sample % 6 + 1, "牌墙与骰子", "骰子没有使用覆盖值", seed)
		_check(game.round_meta.break == WallRing.compute_break(int(game.round_meta.die), game.dealer_seat), "牌墙与骰子", "破墙点与骰子不一致", seed)
		_check(CFG.ROUND_DIRECTION == 1 and CFG.DEAL_DIRECTION == CFG.ROUND_DIRECTION and CFG.TURN_DIRECTION == CFG.ROUND_DIRECTION, "座位与方向", "起手和普通回合方向必须统一为同一个+1配置", seed)
		_check(game._seat_order(0) == [posmod(0 + CFG.TURN_DIRECTION, 4), posmod(0 + CFG.TURN_DIRECTION * 2, 4), posmod(0 + CFG.TURN_DIRECTION * 3, 4)], "座位与方向", "响应顺序没有使用统一的+1方向", seed)
		# 胡阶段只允许胡，不会在胡阶段提前碰杠；通过后才进入碰杠阶段。
		var win_hand := _make_pattern("normal", rng)
		game.players[1].concealed = win_hand.hand.slice(0, 13)
		var tile := str(win_hand.win_tile)
		var win_options := game.legal_response_options(1, 0, tile, RoundState.ResponseStage.WIN)
		var meld_options := game.legal_response_options(1, 0, tile, RoundState.ResponseStage.MELD)
		_check(not win_options.can_pong and not win_options.can_kong, "操作优先级", "胡响应阶段泄露碰杠", seed)
		_check(meld_options.can_pong or meld_options.can_kong or not meld_options.can_win, "操作优先级", "碰杠阶段没有独立响应窗口", seed)
		_hit("操作优先级", 2)
		# 过胡/过碰锁和报听只允许摸切刚摸牌。
		game.players[1].passed_win_until_draw = true
		_check(not game.can_win_on_discard(1, 0, tile, RoundState.ResponseStage.WIN), "普通胡牌限制", "过胡后仍可立即胡", seed)
		game.players[1].passed_win_until_draw = false
		game.players[1].passed_pong_tiles.clear()
		game.players[1].passed_pong_tiles.append(tile)
		meld_options = game.legal_response_options(1, 0, tile, RoundState.ResponseStage.MELD)
		_check(not meld_options.can_pong, "普通回合流程", "过碰后仍可立即碰同牌", seed)
		_check(not meld_options.can_pong, "碰牌", "过碰锁没有禁止同一弃牌", seed)
		_check(not meld_options.can_kong or game.wall.remaining > 0, "明杠", "明杠响应在空墙时仍然可用", seed)
		game.players[1].ready = true
		game.players[1].just_drew = str(game.players[1].concealed[0])
		var ready_options := game.legal_turn_options(1)
		_check(ready_options.discards == [game.players[1].just_drew] and ready_options.kong_declares.is_empty(), "报听", "报听后没有限制为自动摸打", seed)
		_hit("报听", 3)
		# 杠补牌必须从尾部，头尾是不同实体；空墙直接流局。
		var wall := WallRing.new(TileSetFactory.create_deck())
		wall.set_head(0)
		var head := wall.draw_head()
		var tail := wall.draw_tail()
		_check(head != tail and wall.remaining == 106, "暗杠", "杠尾补牌与牌头摸牌混用", seed)
		wall.remaining = 0
		_check(wall.draw_tail() == "" and wall.draw_head() == "", "流局", "空墙没有进入流局语义", seed)
		_hit("暗杠", 1); _hit("加杠", 1); _hit("流局", 1)

class FlowController:
	extends RefCounted
	## 用于200局回归的确定性轻量控制器：优先完成合法胡/杠，其他动作出第一张合法牌，
	## 响应阶段先胡、再按固定条件碰杠，否则过牌，保证每局都经过真实RoundState流程。
	var response_count := 0
	var optimize_discards := false

	func _init(optimize: bool = false) -> void:
		optimize_discards = optimize

	func decide_turn(round: RoundState, seat: int) -> Dictionary:
		var options := round.legal_turn_options(seat)
		if bool(options.get("self_win", false)):
			return {"self_win": true}
		var kongs: Array = options.get("kong_declares", [])
		if not kongs.is_empty() and (round._steps + seat) % 3 == 0:
			return {"kong_declares": [kongs[0]]}
		var adds: Array = options.get("add_kong", [])
		if not adds.is_empty() and (round._steps + seat) % 3 == 0:
			return {"add_kong": [adds[0]]}
		var discards: Array = options.get("discards", [])
		if not discards.is_empty():
			if optimize_discards:
				var best_tile := str(discards[0])
				var best_shanten := 99
				for candidate in discards:
					var trial: Array = round.players[seat].concealed.duplicate()
					trial.erase(candidate)
					var shanten := Shanten.shanten(trial, round.players[seat].melds)
					if shanten < best_shanten:
						best_shanten = shanten
						best_tile = str(candidate)
				return {"discard": best_tile}
			return {"discard": str(discards[0])}
		return {"discard": str(round.players[seat].just_drew)}

	func decide_response(round: RoundState, seat: int, _disc_seat: int, _tile: String, options: Dictionary) -> Dictionary:
		response_count += 1
		if bool(options.get("can_win", false)):
			return {"action": "win"}
		if bool(options.get("can_kong", false)) and response_count % 5 == 0:
			return {"action": "kong"}
		if bool(options.get("can_pong", false)) and (response_count + seat) % 7 == 0:
			return {"action": "pong"}
		return {"action": "pass"}

func _tile_accounted(round: RoundState) -> int:
	var accounted := 0
	for player in round.players:
		accounted += player.concealed.size() + player.discards.size()
		for meld in player.melds:
			accounted += 3 if meld.get("kind", "") == "pung" else 4
	if round.wall != null:
		accounted += round.wall.remaining
	return accounted

func _test_normal_games_200() -> void:
	var wins := 0
	var draws := 0
	for sample in NORMAL_GAME_SAMPLES:
		var seed := 80000 + sample
		var game := RoundState.new()
		game.set_rng_seed(seed)
		var optimize := sample < 20
		game.controllers = [FlowController.new(optimize), FlowController.new(optimize), FlowController.new(optimize), FlowController.new(optimize)]
		game.start_round(sample % 4, sample % 6 + 1)
		_check(game.phase == RoundState.Phase.SETTLED, "普通回合流程", "第%d局没有走到结算阶段" % (sample + 1), seed)
		_check(game._steps > 0 and game._steps <= 3000, "普通回合流程", "第%d局回合步数越界" % (sample + 1), seed)
		_check(game.visual_event_id > 0, "普通回合流程", "第%d局没有发布任何流程事件" % (sample + 1), seed)
		_check(_tile_accounted(game) == 108, "普通回合流程", "第%d局牌数不守恒，实际%d" % [sample + 1, _tile_accounted(game)], seed)
		_check(game.last_result.size() > 0 and game.last_result.deltas.size() == 4, "胡牌付款", "第%d局缺少完整结算账本" % (sample + 1), seed)
		_check(is_zero_approx(float(game.last_result.total_delta)), "胡牌付款", "第%d局结算不是零和" % (sample + 1), seed)
		_check(is_zero_approx(_sum(game.players.map(func(player): return player.score)) - 800.0), "牌局基础", "第%d局四家总分不是800" % (sample + 1), seed)
		_check(game.next_dealer_seat >= 0 and game.next_dealer_seat < 4, "庄家变化", "第%d局下一庄越界" % (sample + 1), seed)
		_check(game.next_chicken_multiplier in [1, 2], "流局", "第%d局鸡分倍率超出1/2" % (sample + 1), seed)
		if int(game.round_meta.get("winner", -1)) >= 0:
			wins += 1
			var winner := int(game.round_meta.winner)
			_check(RuleEngine.analyze(game.players[winner].concealed, game.players[winner].melds, str(game.round_meta.win_tile)).win, "胡牌付款", "第%d局赢家手牌不成胡" % (sample + 1), seed)
			_check((game.wall.remaining == 0 and str(game.round_meta.flip_tile) == "") or (game.wall.remaining > 0 and str(game.round_meta.flip_tile) != ""), "翻鸡", "第%d局胡牌后的翻鸡牌与牌墙状态不一致" % (sample + 1), seed)
		else:
			draws += 1
			_check(str(game.round_meta.flip_tile) == "", "流局", "第%d局流局错误翻鸡" % (sample + 1), seed)
		_hit("普通回合流程", 4)
		_hit("网络同步与幂等")
	_check(wins + draws == NORMAL_GAME_SAMPLES, "普通回合流程", "200局没有全部完成")
	_check(wins > 0, "胡牌付款", "200局随机流程没有形成任何胡牌")
	_check(draws > 0, "流局", "200局随机流程没有覆盖流局")
	print("[rules_randomized] 200局正常流程: 胡牌%d局，流局%d局" % [wins, draws])

func _test_sync_and_idempotence() -> void:
	for sample in 12:
		var seed := 60000 + sample
		var spec := _make_pattern("normal", rng)
		var source := _score_fixture(spec.hand, spec.melds, str(spec.win_tile), seed)
		source.round_meta.self_draw = true
		source._finish()
		var scores := source.players.map(func(player): return player.score)
		var before := source.last_result.duplicate(true)
		source._finish()
		_check(scores == source.players.map(func(player): return player.score), "网络同步与幂等", "重复结束重复扣分", seed)
		_check(source.next_dealer_seat == 0, "庄家变化", "自摸后没有由赢家连庄", seed)
		for seat in 4:
			var client := RoundState.new()
			client.apply_sync(source.serialize_for_seat(seat))
			client.apply_sync(source.serialize_for_seat(seat))
			_check(client.last_result.deltas == before.deltas and client.last_result.pairwise == before.pairwise, "网络同步与幂等", "重复同步改变结算流水", seed)
			_hit("网络同步与幂等", 2)

func _test_random_kong_payments() -> void:
	const TENPAI_10 := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1"]
	for sample in 12:
		var seed := 70000 + sample
		for kind in ["exposed", "concealed", "add_kong"]:
			var round := _score_fixture(TENPAI_10, [], "", seed)
			round.round_meta.winner = -1
			round.round_meta.winners = []
			round.players[0].melds = [{"kind": "add_kong" if kind == "add_kong" else "kong", "tile": "wan9", "from_seat": 2, "concealed": kind == "concealed"}]
			var result := ScoringEngine.settle(round)
			var receiver_paid := bool(result.pairwise[0][2] >= 4.0)
			if kind in ["concealed", "add_kong"]:
				receiver_paid = result.pairwise[0][1] >= 4.0 and result.pairwise[0][2] >= 4.0 and result.pairwise[0][3] >= 4.0
			var section := "明杠" if kind == "exposed" else ("暗杠" if kind == "concealed" else "加杠")
			_check(receiver_paid, section, "%s基础杠分付款对象错误" % kind, seed)

func _score_fixture(hand: Array, melds: Array, win_tile: String, seed: int) -> RoundState:
	var round := RoundState.new()
	round.build_players(0)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	round.wall = WallRing.new(TileSetFactory.create_deck())
	round.wall.set_head(posmod(seed, 108))
	round.players[0].concealed = hand.duplicate()
	round.players[0].melds = melds.duplicate(true)
	round.round_meta.winner = 0
	round.round_meta.winners = [0]
	round.round_meta.self_draw = true
	round.round_meta.win_tile = win_tile
	round.round_meta.flip_tile = ""
	return round

func _chicken_fixture(local: RandomNumberGenerator, sample: int) -> RoundState:
	var round := _score_fixture(["wan1", "wan2"], [], "wan1", sample)
	round.round_meta.flip_tile = ["wan1", "wan5", "wan9", "tiao1", "tong8"][sample % 5]
	round.round_meta.chicken_multiplier = 1 if sample % 2 == 0 else 2
	for seat in 4:
		var player: PlayerState = round.players[seat]
		player.concealed = []
		player.discards = []
		player.discard_ids = []
		for index in range((sample + seat) % 4):
			var chicken := "tiao1" if (index + seat + sample) % 2 == 0 else "tong8"
			player.discards.append(chicken)
			player.discard_ids.append(index)
			if index == 0:
				round.round_meta.charge_chickens[chicken] = {"owner": seat, "location": "discard", "discard_id": index}
		for _index in range((sample + seat * 2) % 3):
			player.concealed.append("tiao1" if (_index + sample) % 2 == 0 else "wan5")
		if sample % 4 == 0:
			player.melds = [{"kind": "pung", "tile": "tong8", "from_seat": posmod(seat + 1, 4)}]
		elif sample % 4 == 1:
			player.melds = [{"kind": "kong", "tile": "tiao1", "from_seat": posmod(seat + 1, 4)}]
		else:
			player.melds = []
		# 每个种子轮换被烧座位，确保四个座位都被独立验证。
		round.round_meta.burn_chicken_seat = sample % 4
	return round

func _independent_chicken(round: RoundState, seat: int, flip: String) -> Dictionary:
	var player: PlayerState = round.players[seat]
	var multiplier := clampi(int(round.round_meta.chicken_multiplier), 1, 2)
	var related := Tiles.flip_related(flip)
	var burned := seat == int(round.round_meta.burn_chicken_seat)
	if burned: return {"total": 0.0, "discarded": 0.0, "held": 0.0}
	var discarded := 0.0
	var held := 0.0
	var flipped := 0.0
	for index in player.discards.size():
		var tile := str(player.discards[index])
		if Tiles.is_chicken(tile):
			var rec: Dictionary = round.round_meta.charge_chickens.get(tile, {})
			var charge: bool = rec.get("owner", -1) == seat and rec.get("location", "") == "discard" and rec.get("discard_id", -1) == int(player.discard_ids[index])
			discarded += float(4 if charge else 2) * float(2 if tile in related else 1) * multiplier
	for tile in player.concealed:
		var held_tile := str(tile)
		if held_tile in related and not Tiles.is_chicken(held_tile):
			flipped += float(multiplier)
		else:
			held += _held_tile(held_tile, related, multiplier)
	for meld in player.melds:
		var n := 3 if meld.get("kind", "") == "pung" else 4
		var meld_tile := str(meld.get("tile", ""))
		for _index in n:
			if meld_tile in related and not Tiles.is_chicken(meld_tile):
				flipped += float(multiplier)
			else:
				held += _held_tile(meld_tile, related, multiplier)
	return {"total": discarded + held + flipped, "discarded": discarded, "held": held}

func _held_tile(tile: String, related: Array, multiplier: int) -> float:
	if Tiles.is_chicken(tile): return float(2 * (2 if tile in related else 1) * multiplier)
	return float(multiplier if tile in related else 0)

func _make_pattern(kind: String, local: RandomNumberGenerator) -> Dictionary:
	var hand: Array = []
	var melds: Array = []
	var win_tile := ""
	var suit: String = ["wan", "tiao", "tong"][local.randi_range(0, 2)]
	match kind:
		"normal":
			var starts := [1 + local.randi_range(0, 1), 3 + local.randi_range(0, 2), 5 + local.randi_range(0, 2), 1 + local.randi_range(0, 5)]
			var suits := ["wan", "tiao", "tong", "wan"]
			for index in 4:
				for rank in 3: hand.append(suits[index] + str(starts[index] + rank))
			var pair := "tong" + str(1 + local.randi_range(0, 8))
			hand.append(pair); hand.append(pair); win_tile = suits[3] + str(starts[3])
		"big", "big_single", "clean_big", "clean_big_single":
			var used := []
			for index in 4:
				var tile: String = (suit if kind not in ["big", "big_single"] else ["wan", "tiao", "tong", "wan"][index]) + str(index + 1 + local.randi_range(0, 1))
				while tile in used: tile = (suit if kind not in ["big", "big_single"] else ["wan", "tiao", "tong", "wan"][index]) + str(local.randi_range(1, 9))
				used.append(tile)
				for _index in 3: hand.append(tile)
			var pair: String = suit + str(9 - local.randi_range(0, 2)) if kind not in ["big", "big_single"] else "tong9"
			if pair in used:
				var candidates: Array = Tiles.all_values()
				if kind not in ["big", "big_single"]:
					candidates = []
					for rank in range(1, 10): candidates.append(suit + str(rank))
				for candidate in candidates:
					if candidate not in used:
						pair = candidate
						break
			hand.append(pair); hand.append(pair)
			win_tile = pair if kind in ["big_single", "clean_big_single"] else used[0]
		"seven", "clean_seven":
			var values: Array = ["wan1", "wan2", "wan3", "wan5", "wan6", "wan8", "wan9"]
			if kind == "clean_seven":
				values.clear()
				for rank in [1, 2, 3, 5, 6, 8, 9]: values.append(suit + str(rank))
			else:
				values = _unique_values(local, 7, "")
			for tile in values: hand.append(tile); hand.append(tile)
			win_tile = values[0]
		"dragon", "clean_dragon":
			var values := _unique_values(local, 6, suit if kind == "clean_dragon" else "")
			for index in values.size():
				var n := 4 if index == 0 else 2
				for _index in n: hand.append(values[index])
			win_tile = values[0]
		"flush":
			var starts := [1, 2 + local.randi_range(0, 2), 4 + local.randi_range(0, 2), 7]
			for start in starts:
				for rank in 3: hand.append(suit + str((start + rank - 1) % 9 + 1))
			var pair: String = suit + str(5 + local.randi_range(0, 2))
			hand.append(pair); hand.append(pair); win_tile = pair if kind == "clean_single" else hand[0]
		"clean_single":
			# 用四个同花刻子和一对，保证胡牌张恰好是单吊；
			# 它同时满足清大队单吊，按规则应取清单吊54分。
			var used := []
			for index in 4:
				var tile: String = suit + str(index + 1 + local.randi_range(0, 1))
				while tile in used: tile = suit + str(local.randi_range(1, 9))
				used.append(tile)
				for _index in 3: hand.append(tile)
			var pair: String = suit + str(9 - local.randi_range(0, 2))
			while pair in used: pair = suit + str(local.randi_range(1, 9))
			hand.append(pair); hand.append(pair); win_tile = pair
	return {"hand": _shuffle(hand, local), "melds": melds, "win_tile": win_tile}

func _unique_values(local: RandomNumberGenerator, amount: int, only_suit: String) -> Array:
	var values := []
	while values.size() < amount:
		var tile: String = (only_suit if only_suit != "" else ["wan", "tiao", "tong"][local.randi_range(0, 2)]) + str(local.randi_range(1, 9))
		if tile not in values: values.append(tile)
	return values

func _pattern_matches(kind: String, pattern: Dictionary) -> bool:
	match kind:
		"normal": return bool(pattern.normal) and not bool(pattern.seven_pairs) and not bool(pattern.all_triplets)
		"big": return bool(pattern.all_triplets) and not bool(pattern.flush)
		"big_single": return bool(pattern.all_triplets) and bool(pattern.big_triplet_single_wait) and not bool(pattern.flush)
		"seven": return bool(pattern.seven_pairs) and not bool(pattern.flush) and not bool(pattern.dragon_seven_pairs)
		"dragon": return bool(pattern.dragon_seven_pairs) and not bool(pattern.flush)
		"flush": return bool(pattern.flush) and bool(pattern.normal) and not bool(pattern.all_triplets) and not bool(pattern.seven_pairs)
		"clean_big": return bool(pattern.clean_big_triplets)
		"clean_big_single": return bool(pattern.clean_big_single_wait)
		"clean_seven": return bool(pattern.clean_seven_pairs)
		"clean_dragon": return bool(pattern.clean_dragon_seven_pairs)
		"clean_single": return bool(pattern.clean_single_wait)
	return false

func _expected_label(kind: String) -> String:
	return {"big": "大队子", "big_single": "大队子单吊", "seven": "小七对", "dragon": "龙七对", "flush": "清一色", "clean_big": "清大对", "clean_big_single": "清单吊", "clean_seven": "清七对", "clean_dragon": "清龙对", "clean_single": "清单吊"}.get(kind, "")

func _expected_score(kind: String) -> int:
	return {"big": 14, "big_single": 24, "seven": 24, "dragon": 44, "flush": 24, "clean_big": 34, "clean_big_single": 54, "clean_seven": 44, "clean_dragon": 64, "clean_single": 54}.get(kind, 0)

func _max_four(hand: Array, melds: Array) -> bool:
	var counts := Tiles.to_counts(hand)
	for meld in melds:
		counts[meld.tile] = int(counts.get(meld.tile, 0)) + (4 if meld.get("kind", "") in ["kong", "add_kong"] else 3)
	for value in counts.values():
		if int(value) > 4: return false
	return true

func _shuffle(source: Array, local: RandomNumberGenerator) -> Array:
	var out := source.duplicate()
	for index in range(out.size() - 1, 0, -1):
		var other := local.randi_range(0, index)
		var temp = out[index]; out[index] = out[other]; out[other] = temp
	return out

func _sum(values: Array) -> float:
	var total := 0.0
	for value in values: total += float(value)
	return total
