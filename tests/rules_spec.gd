extends SceneTree
## 按《当前安顺捉鸡麻将规则》逐项回归，覆盖牌、流程、鸡分、胡型和结算账本。
const H := preload("res://tests/test_harness.gd")
var t := H.new()

const PLAIN := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const MELD_WAIT := ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const BIG := ["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]
const SEVEN := ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9","tiao9"]
const DRAGON := ["tiao1","tiao1","tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao5","tiao5","tiao7","tiao7","tiao9","tiao9"]
const CLEAN_SINGLE := ["tiao1","tiao2","tiao3","tiao4","tiao5","tiao6","tiao2","tiao3","tiao4","tiao5","tiao6","tiao7","tiao9","tiao9"]

func _initialize() -> void:
	call_deferred("_run")

func fixture() -> RoundState:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	return r

func settle(r: RoundState) -> Dictionary:
	var result := ScoringEngine.settle(r)
	var total := 0.0
	for value in result.deltas: total += float(value)
	t.expect(is_zero_approx(total), "结算总分必须守恒")
	for seat in 4:
		for other in 4:
			t.expect(is_zero_approx(float(result.pairwise[seat][other]) + float(result.pairwise[other][seat])), "每笔付款必须反向抵消")
	return result

func _run() -> void:
	_test_tiles_and_directions()
	_test_wall_and_deal()
	_test_priority_and_locks()
	_test_kongs_and_burn()
	_test_chickens()
	_test_patterns()
	_test_win_payments()
	_test_robbed_kong()
	_test_draw_and_dealer()
	_test_score_invariants()
	quit(t.finish("rules_spec"))

func _test_tiles_and_directions() -> void:
	var deck := TileSetFactory.create_deck()
	t.expect(deck.size() == 108, "牌堆必须有108张")
	var counts := Tiles.to_counts(deck)
	t.expect(counts.size() == 27, "牌面必须有27种")
	for tile in Tiles.all_values():
		t.expect(int(counts.get(tile, 0)) == 4, "每种牌必须恰好4张：%s" % tile)
	t.expect(GameConfig.ROUND_DIRECTION == 1 and GameConfig.DEAL_DIRECTION == 1 and GameConfig.TURN_DIRECTION == 1, "拿牌和出牌方向使用统一逻辑方向")
	t.expect(GameConfig.SEAT_DEALER == 0 and GameConfig.SEAT_RIGHT == 1 and GameConfig.SEAT_ACROSS == 2 and GameConfig.SEAT_LEFT == 3, "座位编号符合庄、下、对、上")
	var expected_break := [2, 32, 6, 90, 10, 40]
	for die in range(1, 7): t.expect(WallRing.compute_break(die) == expected_break[die - 1], "骰子%d破墙位置" % die)
	for rank in range(1, 10):
		var suit := "wan"
		var related := Tiles.flip_related(suit + str(rank))
		t.expect(related.size() == 3 and related.has(suit + str(rank)), "翻鸡本张范围")
		t.expect(related.has(suit + str(9 if rank == 1 else rank - 1)) and related.has(suit + str(1 if rank == 9 else rank + 1)), "翻鸡首尾循环")

func _test_wall_and_deal() -> void:
	var wall := WallRing.new(TileSetFactory.create_deck())
	for seat in 4:
		t.expect(wall.wall_remaining(seat) == (28 if seat in [0, 2] else 26), "庄家和对家28张、下家和上家26张牌墙")
	var r := RoundState.new()
	r.start_round(0, 1)
	t.expect(r.players[0].concealed.size() == 14, "庄家起手14张")
	for seat in range(1, 4): t.expect(r.players[seat].concealed.size() == 13, "闲家起手13张")
	t.expect(r.wall.remaining == 55 and r.current_turn == 0 and r.phase == RoundState.Phase.PLAYING, "发牌后庄家先出牌且牌墙剩55张")
	var accounted := 0
	for player in r.players:
		accounted += player.concealed.size() + player.discards.size()
		for meld in player.melds: accounted += 3 if meld.kind == "pung" else 4
	accounted += r.wall.remaining
	t.expect(accounted == 108, "发牌后牌数守恒")

func _test_priority_and_locks() -> void:
	var r := fixture()
	r.players[0].concealed = ["wan2"]
	r.players[0].just_drew = "wan2"
	r.players[1].concealed = ["wan2", "wan2", "tong5"]
	r.players[2].concealed = WAIT.duplicate()
	t.expect(r.submit_turn(0, {"discard": "wan2"}), "合法出牌进入响应阶段")
	t.expect(r._awaiting_response.get("seat", -1) == 1 and r._response_stage == RoundState.ResponseStage.MELD, "胡响应完成后才进入碰杠响应")
	t.expect(not r.submit_response(1, "wan2", {"action": "win"}), "无通行条件的普通牌不能点炮")
	t.expect(r.submit_response(1, "wan2", {"action": "pong"}), "无人胡后才允许碰牌")
	t.expect(r.players[1].forbidden_discard_tile == "wan2", "碰牌后立即禁打同牌")
	r.players[1].passed_win_until_draw = true
	t.expect(not r.can_win_on_discard(1, 0, "wan2"), "过胡锁定到下一次摸牌")
	r.players[1].passed_win_until_draw = false
	r.players[1].passed_pong_tiles.clear()
	r.players[1].passed_pong_tiles.append("wan2")
	t.expect(not r.legal_response_options(1, 0, "wan2", RoundState.ResponseStage.MELD).can_pong, "过碰锁定同牌")
	var options := r.legal_response_options(1, 0, "wan2", RoundState.ResponseStage.MELD)
	t.expect(not options.can_kong, "两张同牌只能碰不能杠")

func _test_kongs_and_burn() -> void:
	var r := fixture()
	r.players[1].concealed = ["wan1", "wan1", "wan1"]
	var options := r.legal_response_options(1, 0, "wan1", RoundState.ResponseStage.MELD)
	t.expect(options.can_pong and options.can_kong, "三张同牌可选择碰或明杠")
	var kong := fixture()
	kong.players[0].concealed = MELD_WAIT.duplicate()
	kong.players[0].melds = [{"kind": "kong", "tile": "wan7", "from_seat": 1}]
	kong.round_meta.winner = -1
	kong.players[1].concealed = []
	var draw := settle(kong)
	t.expect(draw.pairwise[0][1] == 4.0 and draw.pairwise[0][2] == 0.0 and draw.pairwise[0][3] == 0.0, "荒牌明杠只由放杠者付4分")
	var burned := fixture()
	burned.players[0].concealed = ["wan1"]
	burned.players[0].melds = [{"kind": "kong", "tile": "wan7", "concealed": true, "after_discard": 0}]
	burned.players[0].discards = ["tiao1"]
	burned.players[0].discard_ids = [0]
	burned.players[0].discard_count = 1
	burned.players[1].concealed = PLAIN.duplicate()
	burned.round_meta.winner = 1
	burned.round_meta.winners = [1]
	burned.round_meta.self_draw = false
	burned.round_meta.discard_seat = 0
	burned.round_meta.win_tile = "wan9"
	burned.round_meta.burn_chicken_seat = 0
	burned.round_meta.burn_chicken_reason = "after_kong_discard"
	burned.last_discard = {"seat": 0, "tile": "wan9", "after_kong": true, "kong_kind": RoundState.KongKind.CONCEALED}
	var burned_result := settle(burned)
	t.expect(ScoringEngine.chicken_profile(burned, 0, "").total == 0.0, "杠后放炮者鸡分归零")
	t.expect(burned_result.items[0].all(func(item): return item.get("kind", "") != "kong"), "暗杠后放炮取消本次杠分")
	t.expect(burned_result.pairwise[1][0] == GameConfig.SCORE_RON_UNCALLED, "杠后放炮仍支付21分基础费")
	var added := fixture()
	added.players[0].concealed = ["wan1"]
	added.players[0].melds = [{"kind": "add_kong", "tile": "wan7", "after_discard": 0}]
	added.players[0].discard_count = 1
	added.players[1].concealed = PLAIN.duplicate()
	added.round_meta.winner = 1
	added.round_meta.winners = [1]
	added.round_meta.self_draw = false
	added.round_meta.discard_seat = 0
	added.round_meta.win_tile = "wan9"
	added.round_meta.burn_chicken_seat = 0
	added.round_meta.burn_chicken_reason = "after_kong_discard"
	added.last_discard = {"seat": 0, "tile": "wan9", "after_kong": true, "kong_kind": RoundState.KongKind.ADD_KONG}
	var added_result := settle(added)
	t.expect(added_result.items[0].all(func(item): return item.get("kind", "") != "kong"), "加杠后放炮取消本次杠分")

func _test_chickens() -> void:
	var r := fixture()
	r.phase = RoundState.Phase.IDLE
	r.players[0].concealed = ["tiao1", "tiao1", "tong8"]
	r._discard(0, "tiao1")
	r._discard(0, "tiao1")
	r._discard(0, "tong8")
	t.expect(r.is_charge_discard(0, 0), "每种鸡牌第一次打出是冲锋鸡")
	t.expect(not r.is_charge_discard(0, 1), "同种鸡牌后续为普通鸡")
	var profile := ScoringEngine.chicken_profile(r, 0, "")
	t.expect(profile.discarded == 10.0, "冲锋鸡4加普通鸡2加冲锋鸡4")
	var gold := ScoringEngine.chicken_profile(r, 0, "tiao1")
	t.expect(gold.discarded == 16.0, "翻中一条时命中金鸡的鸡分翻倍")
	var meld := fixture()
	for tile in ["tiao1", "tong8"]: meld.players[0].melds.append({"kind": "pung", "tile": tile})
	var meld_profile := ScoringEngine.chicken_profile(meld, 0, "")
	t.expect(meld_profile.total == 12.0, "碰中的一条和八筒按每张2分")

func _test_patterns() -> void:
	var patterns := [
		[SEVEN, "seven_pairs", 24.0], [DRAGON, "dragon_seven_pairs", 44.0],
		[BIG, "all_triplets", 14.0], [CLEAN_SINGLE, "clean_single_wait", 54.0],
	]
	for entry in patterns:
		var pattern := RuleEngine.analyze(entry[0], [], str(entry[0].back()))
		t.expect(pattern.win and GameConfig.PATTERNS.any(func(item): return item.key == entry[1] and float(item.score) == entry[2]), "牌型分值与判定：%s" % entry[1])
	var clean_dragon := ["tiao1","tiao1","tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao5","tiao5","tiao7","tiao7","tiao9","tiao9"]
	var dragon_pattern := RuleEngine.analyze(clean_dragon, [])
	t.expect(RuleEngine.special_pattern_key(dragon_pattern) == "clean_dragon_seven_pairs", "清龙七对优先级最高")
	var clean_big := ["tiao1","tiao1","tiao1","tiao2","tiao2","tiao2","tiao4","tiao4","tiao4","tiao6","tiao6","tiao6","tiao9","tiao9"]
	t.expect(RuleEngine.special_pattern_key(RuleEngine.analyze(clean_big, [])) == "clean_big_triplets", "清大对替代普通大队子")

func _test_win_payments() -> void:
	var self_draw := fixture()
	self_draw.players[0].concealed = PLAIN.duplicate()
	self_draw.round_meta.winner = 0
	self_draw.round_meta.winners = [0]
	self_draw.round_meta.self_draw = true
	var self_result := settle(self_draw)
	t.expect(self_result.deltas == [72.0, -24.0, -24.0, -24.0], "四家无鸡时自摸触发大干扣24")
	var called := fixture()
	called.players[0].concealed = PLAIN.duplicate()
	called.players[1].concealed = WAIT.duplicate()
	called.round_meta.winner = 0
	called.round_meta.winners = [0]
	called.round_meta.self_draw = false
	called.round_meta.discard_seat = 1
	called.round_meta.win_tile = "wan9"
	var called_result := settle(called)
	t.expect(called_result.pairwise[0][1] == GameConfig.SCORE_RON_CALLED, "放炮者叫牌支付17分")
	var uncalled := fixture()
	uncalled.players[0].concealed = PLAIN.duplicate()
	uncalled.round_meta.winner = 0
	uncalled.round_meta.winners = [0]
	uncalled.round_meta.self_draw = false
	uncalled.round_meta.discard_seat = 1
	uncalled.round_meta.win_tile = "wan9"
	var uncalled_result := settle(uncalled)
	t.expect(uncalled_result.pairwise[0][1] == GameConfig.SCORE_RON_UNCALLED, "放炮者未叫牌支付21分")
	var big := fixture()
	big.players[0].concealed = BIG.duplicate()
	big.round_meta.winner = 0
	big.round_meta.winners = [0]
	big.round_meta.self_draw = false
	big.round_meta.discard_seat = 1
	big.round_meta.win_tile = "wan9"
	var big_result := settle(big)
	t.expect(big_result.pairwise[0][1] == 45.0, "点炮牌型分与21分基础费分开结算，实际%s" % str(big_result.pairwise[0][1]))
	var multi := fixture()
	multi.players[0].concealed = PLAIN.duplicate()
	multi.players[1].concealed = PLAIN.duplicate()
	multi.round_meta.winner = 0
	multi.round_meta.winners = [0, 1]
	multi.round_meta.self_draw = false
	multi.round_meta.discard_seat = 2
	multi.round_meta.win_tile = "wan9"
	t.expect(settle(multi).deltas[2] == -42.0, "一炮多响按每位赢家分别收21分")

func _test_robbed_kong() -> void:
	var r := fixture()
	r.players[0].melds = [{"kind": "pung", "tile": "wan9"}]
	r.players[0].concealed = ["wan9", "tiao2", "tiao4", "tiao6", "tong2", "tong4", "tong6", "wan4", "wan5", "wan6", "tiao9"]
	r.players[0].just_drew = "wan9"
	r.players[1].concealed = WAIT.duplicate()
	t.expect(r.submit_turn(0, {"add_kong": ["wan9"]}), "加杠进入抢杠胡窗口")
	t.expect(r.submit_response(1, "wan9", {"action": "win"}), "抢杠胡响应成功")
	t.expect(r.round_meta.robbed_kong and not r.round_meta.self_draw and r.round_meta.burn_chicken_seat == 0, "抢杠胡记录被抢杠者并烧鸡")
	var rob_base: bool = r.last_result.transfers.any(func(item): return item.get("from", -1) == 0 and item.get("to", -1) == 1 and is_equal_approx(float(item.get("amount", 0.0)), GameConfig.SCORE_ROB_KONG) and item.get("reason", "") == "抢杠胡基础分")
	t.expect(rob_base, "抢杠胡由被抢杠者单独支付12分，实际流水%s" % str(r.last_result.transfers))

func _test_draw_and_dealer() -> void:
	var r := fixture()
	for player in r.players: player.concealed = WAIT.duplicate()
	r.dealer_seat = 2
	r._penzu()
	t.expect(r.next_dealer_seat == 2 and r.next_chicken_multiplier == 2, "四家叫牌流局连庄且下局倍率为2")
	var mixed := fixture()
	mixed.dealer_seat = 1
	mixed.players[0].concealed = WAIT.duplicate()
	mixed._penzu()
	t.expect(mixed.next_dealer_seat == 1 and mixed.next_chicken_multiplier == 1, "有人未叫牌的流局仍由当前庄家连庄")
	var all_called := fixture()
	for player in all_called.players: player.concealed = WAIT.duplicate()
	all_called.round_meta.winner = -1
	var no_flip := settle(all_called)
	t.expect(no_flip.deltas == [0.0, 0.0, 0.0, 0.0] and all_called.round_meta.get("flip_tile", "") == "", "流局不翻鸡且四家叫牌不互补")

func _test_score_invariants() -> void:
	var r := fixture()
	r.players[0].concealed = PLAIN.duplicate()
	r.players[0].melds = [{"kind": "kong", "tile": "wan7", "concealed": true}]
	r.round_meta.winner = 0
	r.round_meta.winners = [0]
	r.round_meta.self_draw = true
	var result := settle(r)
	t.expect(result.deltas.reduce(func(a, b): return a + b, 0.0) == 0.0, "所有付款后四家总分仍为800")
	t.expect(result.transfers.all(func(item): return float(item.amount) > 0.0 and item.from != item.to), "付款流水没有自付或负金额")
