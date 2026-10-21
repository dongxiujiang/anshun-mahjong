extends SceneTree
## 当前文档是唯一 oracle；失败累积到末尾，不能用旧实现生成期望值。
## -- --case <断言ID> 可单独显示/判断一个断言；仍执行其确定性前置动作。
const CFG = preload("res://scripts/autoload/GameConfig.gd")
const ACT = preload("res://scripts/core/LegalActions.gd")
const CH = preload("res://scripts/core/ChickenScoring.gd")
const KG = preload("res://scripts/core/KongScoring.gd")
const WIN = preload("res://scripts/core/WinScoring.gd")
const PAY = preload("res://scripts/core/PaymentLedger.gd")
const SEED = 20261018
const DOC = "res://docs/当前游戏规则与玩法.txt"
const OUT = "res://build/rules_audit/results.json"
const PLAIN = ["wan1","wan2","wan3","wan4","wan5","wan6","tiao2","tiao3","tiao4","tong2","tong3","tong4","wan9","wan9"]
const BIG = ["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]
const FLUSH = ["wan1","wan2","wan3","wan2","wan3","wan4","wan4","wan5","wan6","wan6","wan7","wan8","wan9","wan9"]
const SEVEN = ["wan1","wan1","wan2","wan2","wan4","wan4","tiao2","tiao2","tiao5","tiao5","tong3","tong3","tong7","tong7"]
const DRAGON = ["wan1","wan1","wan1","wan1","wan2","wan2","tiao2","tiao2","tiao5","tiao5","tong3","tong3","tong7","tong7"]
var checks: Array = []
var context := {}
var case_name := ""
var selected_case := ""
var settlement_number := 0

func _initialize() -> void:
	call_deferred("_run")

func fixture(seed_value: int = SEED) -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(seed_value)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	return r

func waiting(hand: Array = PLAIN) -> Array:
	return hand.slice(0, hand.size() - 1)

func meld(tile: String, kind: String = "pung", source: int = 1, concealed: bool = false, after: int = 0) -> Dictionary:
	return {"kind": kind, "tile": tile, "from_seat": source, "concealed": concealed, "after_discard": after}

func snapshot(r: RoundState) -> Dictionary:
	var seats: Array = []
	for p in r.players:
		seats.append({"seat": p.seat, "hand": p.concealed.duplicate(), "melds": p.melds.duplicate(true), "discards": p.discards.duplicate(), "ready": p.ready, "drawn": p.just_drew, "discard_count": p.discard_count, "score": p.score})
	return {"seed": SEED, "seats": seats, "meta": r.round_meta.duplicate(true), "last_discard": r.last_discard.duplicate(true), "turn": r.current_turn, "dealer": r.dealer_seat}

func begin(name: String, r: RoundState = null, actions: String = "无；隔离单元输入") -> void:
	case_name = name
	context = snapshot(r) if r != null else {"seed": SEED, "seats": [], "scope": "纯函数"}
	context["actions"] = actions

func eq(lines: Array, name: String, actual: Variant, expected: Variant, location: String) -> void:
	var id := case_name + "." + name
	if selected_case != "" and selected_case != id:
		return
	var ok: bool = actual == expected
	checks.append({"id": id, "lines": lines, "assertion": name, "actual": actual, "expected": expected, "location": location, "result": "通过" if ok else "失败", "repro": context.duplicate(true)})
	if not ok:
		print("[RULE_FAIL] %s actual=%s expected=%s" % [id, str(actual), str(expected)])

func ambiguity(lines: Array, name: String, actual: Variant, explanation: String, location: String) -> void:
	var id := case_name + "." + name
	if selected_case != "" and selected_case != id:
		return
	checks.append({"id": id, "lines": lines, "assertion": name, "actual": actual, "expected": explanation, "location": location, "result": "有歧义", "repro": context.duplicate(true)})

func conservation(result: Dictionary, applied_scores: Array = []) -> void:
	settlement_number += 1
	var tag := "结算%d" % settlement_number
	var scores := applied_scores.duplicate()
	if scores.is_empty():
		for d in result.deltas: scores.append(200.0 + float(d))
	eq([12, 272], tag + "四家总分800", scores.reduce(func(a,b): return a+b, 0.0), 800.0, "scripts/core/RoundState.gd:892; scripts/core/PaymentLedger.gd:5")
	var rebuilt := [0.0, 0.0, 0.0, 0.0]
	for i in result.transfers.size():
		var x: Dictionary = result.transfers[i]
		var pair := [0.0, 0.0, 0.0, 0.0]
		pair[int(x.from)] -= float(x.amount)
		pair[int(x.to)] += float(x.amount)
		eq([271], tag + "流水%d双边相抵" % i, pair.reduce(func(a,b): return a+b, 0.0), 0.0, "scripts/core/PaymentLedger.gd:5")
		for seat in 4: rebuilt[seat] += pair[seat]
	for seat in 4:
		eq([271], tag + "座位%d流水等于净变化" % seat, rebuilt[seat], result.deltas[seat], "scripts/core/PaymentLedger.gd:5")
		for other in range(seat + 1, 4):
			eq([271], tag + "矩阵%d-%d反对称" % [seat, other], result.pairwise[seat][other] + result.pairwise[other][seat], 0.0, "scripts/core/PaymentLedger.gd:42")

func settle(r: RoundState) -> Dictionary:
	var out := ScoringEngine.settle(r)
	conservation(out)
	return out

func finish_round(r: RoundState) -> Dictionary:
	r._finish()
	conservation(r.last_result, r.players.map(func(p): return p.score))
	return r.last_result

func win_meta(r: RoundState, winner: int = 0, source: int = -1, tile: String = "wan9") -> void:
	r.round_meta.winner = winner
	r.round_meta.winners = [winner]
	r.round_meta.self_draw = source < 0
	r.round_meta.discard_seat = source
	r.round_meta.win_tile = tile

func fee(result: Dictionary, payer: int, receiver: int, reason: String) -> float:
	var total := 0.0
	for x in result.transfers:
		if int(x.from) == payer and int(x.to) == receiver and (reason == "*" or str(x.reason) == reason):
			total += float(x.amount)
	return total

func label_amount(result: Dictionary, seat: int, label: String) -> float:
	var total := 0.0
	for item in result.items[seat]:
		if item.get("label", "") == label: total += float(item.amount)
	return total

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "--case": selected_case = args[1]
	_test_deck_wall_deal()
	_test_actions()
	_test_passports()
	_test_kong_flow()
	_test_chickens()
	_test_patterns()
	_test_ready_and_win_fees()
	_test_kong_and_burn_payments()
	_test_ledger_and_draws()
	_test_dealer_and_bonuses()
	_test_ui_and_absences()
	_test_additional_boundaries()
	_test_confirmed_clarifications()
	var failed := checks.filter(func(c): return c.result == "失败").size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var output := FileAccess.open(OUT, FileAccess.WRITE)
	output.store_string(JSON.stringify({"document": DOC, "document_sha256": FileAccess.get_sha256(DOC), "seed": SEED, "checks": checks, "failed": failed, "selected_case": selected_case}, "\t"))
	output.close()
	var suite := "rules_spec_v2" if OS.get_cmdline_args().has("res://tests/rules_spec_v2.gd") else "rules_spec"
	print("[%s] %s (%d checks, %d failures, %d ambiguities)" % [suite, "passed" if failed == 0 else "FAILED", checks.size(), failed, checks.filter(func(c): return c.result == "有歧义").size()])
	quit(1 if failed > 0 or checks.is_empty() else 0)

func _test_deck_wall_deal() -> void:
	begin("deck")
	var deck := TileSetFactory.create_deck()
	eq([6], "总牌数", deck.size(), 108, "scripts/core/TileSetFactory.gd:5")
	eq([7], "三种花色", Tiles.SUITS, ["wan", "tiao", "tong"], "scripts/core/Tiles.gd:5")
	eq([8], "牌值数", Tiles.to_counts(deck).size(), 27, "scripts/core/Tiles.gd:20")
	for tile in Tiles.all_values():
		eq([9], tile + "四张", deck.count(tile), 4, "scripts/core/TileSetFactory.gd:10")
		eq([8, 13], tile + "合法点数花色", Tiles.rank(tile) in range(1, 10) and Tiles.suit(tile) in ["wan", "tiao", "tong"], true, "scripts/core/Tiles.gd:20")
	for i in 4:
		eq([19+i], "座位%d" % i, [CFG.SEAT_DEALER, CFG.SEAT_RIGHT, CFG.SEAT_ACROSS, CFG.SEAT_LEFT][i], i, "scripts/autoload/GameConfig.gd:62")
	eq([25, 28, 31, 34], "回合方向", CFG.TURN_DIRECTION, 1, "scripts/autoload/GameConfig.gd:57")
	eq([26, 30], "发牌方向", CFG.DEAL_DIRECTION, 1, "scripts/autoload/GameConfig.gd:57")
	for dealer in 4:
		var wall := WallRing.new(deck, dealer)
		for seat in 4:
			eq([54 if posmod(seat-dealer,2)==0 else 55], "庄%d座%d墙长度" % [dealer,seat], wall.wall_remaining(seat), 28 if posmod(seat-dealer,2)==0 else 26, "scripts/core/WallRing.gd:34; scripts/core/WallBuilder.gd:5")
		for die in range(1,7):
			var idx := WallRing.compute_break(die, dealer)
			var target := -1
			for seg in WallRing.segments_for_dealer(dealer).values():
				if idx >= seg.start and idx < seg.start+seg.len: target = seg.seat
			eq([43,44 if die in [1,3,5] else (46 if die==4 else 45)], "庄%d骰%d破墙方向" % [dealer,die], target, posmod(dealer+(2 if die in [1,3,5] else (3 if die==4 else 1)),4), "scripts/core/WallRing.gd:44")
	var ring: Array = []
	for i in 108: ring.append(str(i))
	var wall := WallRing.new(ring)
	wall.set_head(107)
	eq([47,48], "牌头第一张", wall.draw_head(), "107", "scripts/core/WallRing.gd:75")
	eq([47,48], "牌头环绕", wall.draw_head(), "0", "scripts/core/WallRing.gd:75")
	eq([29,49], "牌尾第一张", wall.draw_tail(), "106", "scripts/core/WallRing.gd:86")
	eq([49], "牌尾第二张", wall.draw_tail(), "105", "scripts/core/WallRing.gd:86")
	var full_segments: Array = []
	context["unit_input"] = "WallRing牌墙使用0..107作为可区分的牌标签；头0起；墙座位边界2/3/0/1"
	var logical := WallRing.new(ring)
	logical.set_head(0)
	for i in 108:
		var idx := int(logical.draw_head())
		for seg in WallRing.SEG.values():
			if idx == seg.start: full_segments.append(seg.seat)
	eq([27,48], "跨墙座位按加1取牌", full_segments, [2,3,0,1], "scripts/core/WallRing.gd:10; scripts/core/WallRing.gd:75")
	for dealer in 4:
		var r := fixture()
		r.next_dealer_seat = dealer
		var batches: Array = []
		r.dealt.connect(func(info): batches.append_array(info.batches))
		r.start_round(0)
		begin("deal%d" % dealer, r, "set_rng_seed(20261018); start_round(0)")
		eq([41], "骰子范围", int(r.round_meta.die) in range(1,7), true, "scripts/core/RoundState.gd:200")
		eq([42], "骰子决定破墙", r.round_meta["break"], WallRing.compute_break(r.round_meta.die,dealer), "scripts/core/RoundState.gd:202")
		for b in 3:
			for offset in 4:
				eq([26,56], "轮%d座%d四张" % [b,offset], batches[b][offset].cards.size(), 4, "scripts/core/RoundState.gd:233")
				eq([26,56], "轮%d发牌方向%d" % [b,offset], batches[b][offset].seat, posmod(dealer+offset,4), "scripts/core/RoundState.gd:238")
		for offset in 4:
			eq([57], "座%d三轮共12张" % offset, batches[0][offset].cards.size()+batches[1][offset].cards.size()+batches[2][offset].cards.size(), 12, "scripts/core/RoundState.gd:235")
			eq([58], "座%d补1张" % offset, batches[3+offset][0].cards.size(), 1, "scripts/core/RoundState.gd:246")
		for seat in 4:
			eq([10], "座%d初始200" % seat, r.players[seat].score, 200.0, "scripts/core/RoundState.gd:168")
			eq([59 if seat==dealer else 58], "座%d手牌张数" % seat, r.players[seat].concealed.size(), 14 if seat==dealer else 13, "scripts/core/RoundState.gd:258")
		eq([60], "庄家先出牌", r.current_turn, dealer, "scripts/core/RoundState.gd:204")
	var opening := fixture()
	opening.build_players(0)
	opening.phase = RoundState.Phase.DEALING
	opening.players[0].concealed = ["wan1"]
	begin("opening", opening)
	eq([61], "动画前禁止出牌", opening.submit_turn(0,{"discard":"wan1"}), false, "scripts/core/LegalActions.gd:48")
	eq([61], "动画前禁止响应", opening.submit_response(1,"wan1",{"action":"pong"}), false, "scripts/core/LegalActions.gd:57")
	var exhausted := fixture()
	exhausted.wall.remaining = 0
	begin("empty_wall", exhausted, "牌墙耗尽; _begin_turn()")
	exhausted._begin_turn()
	eq([50,291], "无牌流局", exhausted.phase, RoundState.Phase.SETTLED, "scripts/core/RoundState.gd:268")
	eq([50,291], "无赢家", exhausted.round_meta.winner, -1, "scripts/core/RoundState.gd:865")
	conservation(exhausted.last_result, exhausted.players.map(func(p): return p.score))

func _test_actions() -> void:
	var r := fixture()
	r.players[0].concealed = ["wan9"]
	r.players[0].just_drew = "wan9"
	r.players[1].concealed = ["wan9","wan9","tong5"]
	r.players[2].concealed = waiting()
	r.players[2].ready = true
	begin("priority", r, "0打wan9 → 2过胡 → 1过碰 → 1摸牌")
	eq([70], "接受出牌", r.submit_turn(0,{"discard":"wan9"}), true, "scripts/core/RoundState.gd:319")
	eq([71,80,83], "先询问胡家", r._awaiting_response.get("seat",-1), 2, "scripts/core/RoundState.gd:492")
	eq([83], "胡响应阶段", r._response_stage, RoundState.ResponseStage.WIN, "scripts/core/RoundState.gd:493")
	var before := r.wall.remaining
	r.submit_response(2,"wan9",{"action":"pass"})
	eq([84], "过胡后碰杠阶段", r._response_stage, RoundState.ResponseStage.MELD, "scripts/core/RoundState.gd:536")
	eq([84], "碰杠玩家", r._awaiting_response.get("seat",-1), 1, "scripts/core/RoundState.gd:537")
	eq([80,85], "响应未完不摸牌", r.wall.remaining, before, "scripts/core/RoundState.gd:529")
	eq([88], "过胡锁被设置", r.players[2].passed_win_until_draw, true, "scripts/core/RoundState.gd:638")
	eq([88], "过胡不能再胡", r.can_win_on_discard(2,3,"wan9"), false, "scripts/core/LegalActions.gd:116")
	r.submit_response(1,"wan9",{"action":"pass"})
	eq([28,72,85], "下家摸牌", r.current_turn, 1, "scripts/core/RoundState.gd:547")
	eq([66,85], "摸且只摸一张", r.wall.remaining, before-1, "scripts/core/RoundState.gd:267")
	for source in 4:
		eq([87], "响应座位顺序%d" % source, r._seat_order(source), [posmod(source+1,4),posmod(source+2,4),posmod(source+3,4)], "scripts/core/RoundState.gd:497")
	r.current_turn = 2
	r._begin_turn()
	eq([88], "本人摸牌解除过胡", r.players[2].passed_win_until_draw, false, "scripts/core/RoundState.gd:273")
	var pong := fixture()
	pong.players[0].concealed = ["wan5"]
	pong.players[2].concealed = ["wan5","wan5","wan5","tong2"]
	begin("pong", pong, "0打wan5 → 2碰 → 2尝试打wan5")
	pong.submit_turn(0,{"discard":"wan5"})
	eq([95], "至少两张可碰", pong.legal_response_options(2,0,"wan5",RoundState.ResponseStage.MELD).can_pong, true, "scripts/core/LegalActions.gd:94")
	pong.submit_response(2,"wan5",{"action":"pong"})
	eq([96], "移除手中两张", pong.players[2].concealed.count("wan5"), 1, "scripts/core/RoundState.gd:656")
	eq([96], "组成一组碰", pong.players[2].melds.size(), 1, "scripts/core/RoundState.gd:657")
	eq([97], "碰家继续出牌", pong.current_turn, 2, "scripts/core/RoundState.gd:661")
	eq([98], "碰后禁打同值", pong.submit_turn(2,{"discard":"wan5"}), false, "scripts/core/LegalActions.gd:13")
	eq([101], "弃牌记录移除", pong.players[0].discards.has("wan5"), false, "scripts/core/RoundState.gd:828")
	var lock := fixture()
	lock.players[0].concealed = ["wan5"]
	lock.players[2].concealed = ["wan5","wan5","tong2"]
	begin("pass_pong", lock, "0打wan5 → 2过碰 → 1摸牌; 2本人摸牌后解锁")
	lock.submit_turn(0,{"discard":"wan5"})
	lock.submit_response(2,"wan5",{"action":"pass"})
	eq([89], "过碰锁同牌", lock.legal_response_options(2,1,"wan5",RoundState.ResponseStage.MELD).can_pong, false, "scripts/core/LegalActions.gd:94")
	eq([90], "拒绝过期碰响应", lock.submit_response(2,"wan5",{"action":"pong"}), false, "scripts/core/LegalActions.gd:57")
	lock.current_turn = 2
	lock._begin_turn()
	eq([89], "本人摸牌恢复碰", lock.legal_response_options(2,1,"wan5",RoundState.ResponseStage.MELD).can_pong, true, "scripts/core/RoundState.gd:500")
	var ready := fixture()
	ready.players[0].concealed = waiting()+["tong9"]
	ready.players[0].just_drew = "tong9"
	begin("ready_window", ready, "0首摸tong9并报听打tong9; 后续摸tiao9")
	eq([154], "首摸可报听", ready.can_declare_ready(0), true, "scripts/core/LegalActions.gd:67")
	eq([155], "打牌听牌可报听", ready.legal_turn_options(0).ready_discards.has("tong9"), true, "scripts/core/LegalActions.gd:20")
	ready.submit_turn(0,{"discard":"tong9","ready":true})
	eq([155], "报听生效", ready.players[0].ready, true, "scripts/core/RoundState.gd:365")
	ready.current_turn = 0
	ready.awaiting = true
	ready.players[0].concealed.append("tiao9")
	ready.players[0].just_drew = "tiao9"
	eq([91,156], "不能换牌", ready.submit_turn(0,{"discard":"wan1"}), false, "scripts/core/LegalActions.gd:9")
	eq([157], "仅摸牌可打", ready.legal_turn_options(0).discards, ["tiao9"], "scripts/core/LegalActions.gd:10")
	ready.players[0].concealed = ["wan1","wan1","wan1","wan1","tong8"]
	ready.players[0].just_drew = "tong8"
	ready.players[0].melds = [meld("tong8")]
	eq([91], "报听禁止暗杠", ready.legal_turn_options(0).kong_declares, [], "scripts/core/LegalActions.gd:11")
	eq([91], "报听禁止加杠", ready.legal_turn_options(0).add_kong, [], "scripts/core/LegalActions.gd:11")
	var multi := fixture()
	multi.players[0].concealed = ["wan9"]
	for seat in [1,2]:
		multi.players[seat].concealed = waiting()
		multi.players[seat].ready = true
	begin("multi_win", multi, "0打wan9 → 1胡 → 2胡")
	multi.submit_turn(0,{"discard":"wan9"})
	multi.submit_response(1,"wan9",{"action":"win"})
	eq([86], "首胡后继续问第二家", multi._awaiting_response.get("seat",-1), 2, "scripts/core/RoundState.gd:629")
	multi.submit_response(2,"wan9",{"action":"win"})
	eq([86], "一炮两响", multi.round_meta.winners, [1,2], "scripts/core/RoundState.gd:669")
	conservation(multi.last_result, multi.players.map(func(p): return p.score))

func _test_passports() -> void:
	for passport in ["none","ready","source_ready","concealed","added","big","seven","dragon","flush","own_dark","own_add","rob"]:
		var r := fixture()
		r.players[1].concealed = waiting()
		var lines: Array = [150]
		var stage := RoundState.ResponseStage.WIN
		match passport:
			"ready":
				r.players[1].ready = true
				lines = [141]
			"source_ready":
				r.players[0].ready = true
				lines = [142,159]
			"concealed", "added":
				r.last_discard = {"seat":0,"tile":"wan9","after_kong":true,"kong_kind":{"concealed":RoundState.KongKind.CONCEALED,"added":RoundState.KongKind.ADD_KONG}[passport]}
				lines = [143]
				if passport == "concealed": lines.append(122)
				if passport == "added": lines.append(132)
			"big":
				r.players[1].concealed = waiting(BIG)
				lines = [144]
			"seven", "dragon":
				r.players[1].concealed = waiting(SEVEN if passport=="seven" else DRAGON)
				lines = [145]
			"flush":
				r.players[1].concealed = waiting(FLUSH)
				lines = [146]
			"own_dark", "own_add":
				r.players[1].concealed = waiting().slice(3)
				r.players[1].melds = [meld("tong7","kong" if passport=="own_dark" else "add_kong",0,passport=="own_dark")]
				lines = [121,147] if passport=="own_dark" else [148]
			"rob":
				stage = RoundState.ResponseStage.ROB
				lines = [149]
		var tile := "tong7" if passport in ["seven","dragon"] else "wan9"
		begin("passport_"+passport,r,"0弃"+tile+"; 1申请胡牌")
		eq(lines,"胡牌通行条件",r.can_win_on_discard(1,0,tile,stage),passport!="none","scripts/core/LegalActions.gd:113")
		if passport == "none":
			r.players[1].concealed.append(tile)
			r.players[1].just_drew = tile
			eq([67,150],"普通小牌可自摸",r.legal_turn_options(1).self_win,true,"scripts/core/LegalActions.gd:8")
	# Exposed-kong discard is not a passport any more.
	var exposed := fixture()
	exposed.players[1].concealed = waiting()
	exposed.last_discard = {"seat":0,"tile":"wan9","after_kong":true,"kong_kind":RoundState.KongKind.EXPOSED}
	eq([143],"明杠后弃牌不开放普通胡",exposed.can_win_on_discard(1,0,"wan9",RoundState.ResponseStage.WIN),false,"scripts/core/LegalActions.gd:122")

func _test_kong_flow() -> void:
	for kind in ["exposed","concealed","added"]:
		var r := fixture()
		var owner := 1 if kind=="exposed" else 0
		r.players[owner].concealed = ["wan7","wan7","wan7","tong2"] if kind=="exposed" else ["wan7","wan7","wan7","wan7","tong2"]
		if kind=="added":
			r.players[owner].concealed = ["wan7","tong2"]
			r.players[owner].melds = [meld("wan7")]
		r.players[owner].just_drew = "wan7" if kind=="added" else "tong2"
		if kind=="exposed": r.players[0].concealed = ["wan7"]
		begin("kong_flow_"+kind,r,"明杠:0打wan7后1杠; 暗杠/加杠:0宣告wan7; 补牌取牌尾")
		var tail: String = r.wall._ring[r.wall._tail]
		var count := r.wall.remaining
		if kind=="exposed":
			r.submit_turn(0,{"discard":"wan7"})
			eq([105],"明杠合法",r.legal_response_options(1,0,"wan7",RoundState.ResponseStage.MELD).can_kong,true,"scripts/core/LegalActions.gd:95")
			r.submit_response(1,"wan7",{"action":"kong"})
			eq([106],"明杠没有抢杠阶段",r._response_stage != RoundState.ResponseStage.ROB and r._pending_kong.is_empty(),true,"scripts/core/RoundState.gd:819")
		else:
			eq([68,115] if kind=="concealed" else [69,127,128],"杠选项",r.legal_turn_options(0)["kong_declares" if kind=="concealed" else "add_kong"].has("wan7"),true,"scripts/core/LegalActions.gd:15")
			r.submit_turn(0,{"kong_declares" if kind=="concealed" else "add_kong":["wan7"]})
		eq([106 if kind=="exposed" else (116 if kind=="concealed" else 131),29,49],"补牌来自尾部",r.players[owner].just_drew,tail,"scripts/core/RoundState.gd:714")
		eq([106 if kind=="exposed" else (116 if kind=="concealed" else 131)],"只补1张",r.wall.remaining,count-1,"scripts/core/RoundState.gd:716")
		eq([111],"杠后继续出牌",r.current_turn,owner,"scripts/core/RoundState.gd:726")
		if kind=="concealed":
			eq([117,118],"暗杠最初不翻开",r.is_meld_revealed(owner,0),false,"scripts/core/RoundState.gd:811")
			r.phase = RoundState.Phase.IDLE
			r._discard(owner,"tong2")
			eq([119],"一次出牌未翻",r.is_meld_revealed(owner,0),false,"scripts/core/RoundState.gd:818")
			r._discard(owner,tail)
			eq([119],"两次出牌翻开",r.is_meld_revealed(owner,0),true,"scripts/core/RoundState.gd:818")
	var rob := fixture()
	rob.players[0].concealed = ["wan9","wan4","wan5","wan6","tiao5","tiao6","tiao7","tong6","tong7","tong8","tiao9"]
	rob.players[0].melds = [meld("wan9")]
	rob.players[0].just_drew = "wan9"
	# 抢第4张wan9须成顺，赢家不能再持wan9，否则会构造出不存在的第5张。
	rob.players[1].concealed = ["wan1","wan2","wan3","tiao2","tiao3","tiao4","tong2","tong3","tong4","wan7","wan8","tong5","tong5"]
	begin("rob_flow",rob,"0加杠wan9 → 1抢杠胡")
	rob.submit_turn(0,{"add_kong":["wan9"]})
	eq([129],"先进入抢杠阶段",rob._response_stage,RoundState.ResponseStage.ROB,"scripts/core/RoundState.gd:747")
	eq([133],"抢杠胡提交",rob.submit_response(1,"wan9",{"action":"win"}),true,"scripts/core/RoundState.gd:610")
	eq([135,205],"被抢杠者烧鸡",rob.round_meta.burn_chicken_seat,0,"scripts/core/RoundState.gd:706")
	eq([134,278],"被抢者付12",fee(rob.last_result,0,1,"抢杠胡基础分"),12.0,"scripts/core/WinScoring.gd:9")
	conservation(rob.last_result,rob.players.map(func(p): return p.score))
	for kind in [RoundState.KongKind.CONCEALED,RoundState.KongKind.ADD_KONG]:
		var r := fixture()
		r.players[0].concealed = ["wan9"]
		r.players[1].concealed = waiting()
		r._kong_draw_turn = true
		r._kong_draw_kind = kind
		begin("burn_flow%d" % kind,r,"0暗/加杠补牌后打wan9 → 1胡")
		r.submit_turn(0,{"discard":"wan9"})
		r.submit_response(1,"wan9",{"action":"win"})
		eq([206 if kind==RoundState.KongKind.CONCEALED else 207],"杠后放炮烧鸡",r.round_meta.burn_chicken_seat,0,"scripts/core/RoundState.gd:625")
		conservation(r.last_result,r.players.map(func(p): return p.score))

func _test_chickens() -> void:
	begin("chicken_definition")
	for tile in Tiles.all_values():
		eq([172,173],tile+"是否鸡牌",Tiles.is_chicken(tile),tile in ["tiao1","tong8"],"scripts/core/Tiles.gd:28")
	for tile in ["tiao1","tong8"]:
		var r := fixture()
		r.phase = RoundState.Phase.IDLE
		r.players[0].concealed = [tile,tile]
		begin("charge_"+tile,r,"0第一次打"+tile+"; 0第二次打同牌")
		r._discard(0,tile)
		eq([176],"首打4",CH.chicken_profile(r,0,"").discarded,4.0,"scripts/core/ChickenScoring.gd:5")
		r._discard(0,tile)
		eq([177],"后打增2",CH.chicken_profile(r,0,"").discarded,6.0,"scripts/core/ChickenScoring.gd:5")
		eq([198,262],"冲锋金鸡8",CH.chicken_profile(r,0,tile).raw_items[0].amount,8.0,"scripts/core/ChickenScoring.gd:5")
		for kind in ["hand","pung","kong","add_kong"]:
			var held := fixture()
			if kind=="hand": held.players[0].concealed = [tile]
			else: held.players[0].melds = [meld(tile,kind,1,kind=="kong")]
			var count := 1 if kind=="hand" else (3 if kind=="pung" else 4)
			begin("chicken_"+tile+"_"+kind,held)
			var refs: Array = [178 if kind=="hand" else (179 if kind=="pung" else 180),260]
			if kind=="kong": refs.append_array([109,123])
			if kind=="add_kong": refs.append(136)
			eq(refs,"每张2",CH.chicken_profile(held,0,"").total,count*2.0,"scripts/core/ChickenScoring.gd:5")
			eq([196,197,262],"金鸡每张4",CH.chicken_profile(held,0,tile).total,count*4.0,"scripts/core/ChickenScoring.gd:63")
		for kind in ["pong","kong"]:
			var take := fixture()
			take.players[0].concealed = [tile]
			take.players[1].concealed = [tile,tile,"wan5"] if kind=="pong" else [tile,tile,tile,"wan5"]
			begin("claim_"+tile+"_"+kind,take,"0打首张"+tile+" → 1"+kind)
			take.submit_turn(0,{"discard":tile})
			take.submit_response(1,tile,{"action":kind})
			eq([100,110,181],"原弃牌移除",take.players[0].discards.has(tile),false,"scripts/core/RoundState.gd:828")
			eq([182],"归碰杠者",take.round_meta.charge_chickens[tile].owner,1,"scripts/core/RoundState.gd:843")
			var raw: Array = CH.chicken_profile(take,1,"").raw_items.filter(func(x): return x.tile==tile)
			for i in raw.size():
				eq([100,110,183],"第%d张不再冲锋" % i,raw[i].kind,"chicken","scripts/core/ChickenScoring.gd:5")
				eq([100,110,179,180],"第%d张降为2" % i,raw[i].amount,2.0,"scripts/core/ChickenScoring.gd:63")
	begin("flip_range")
	for suit in ["wan","tiao","tong"]:
		for rank in range(1,10):
			var actual := Tiles.flip_related(suit+str(rank))
			actual.sort()
			var expected: Array = [suit+str(9 if rank==1 else rank-1),suit+str(rank),suit+str(1 if rank==9 else rank+1)]
			expected.sort()
			eq([190,191 if rank==1 else (192 if rank==9 else 193),194],suit+str(rank)+"前本后循环",actual,expected,"scripts/core/Tiles.gd:32")
	var flip := fixture()
	flip.players[0].concealed = ["wan4","wan5","wan6","tong5"]
	begin("flip_value",flip)
	eq([195,199,262],"非鸡翻牌每张1同花色",CH.chicken_profile(flip,0,"wan5").total,3.0,"scripts/core/ChickenScoring.gd:63")
	var r := fixture()
	r.players[0].concealed = PLAIN.duplicate()
	win_meta(r)
	var next := r.wall.peek_head()
	begin("flip_head",r,"自摸结算，翻牌取下一张牌头")
	finish_round(r)
	eq([188,189],"胡牌翻下一张",r.round_meta.flip_tile,next,"scripts/core/RoundState.gd:877")

func _test_patterns() -> void:
	begin("constants")
	var values := [CFG.SCORE_SELF_DRAW,CFG.SCORE_NO_CHICKEN,CFG.SCORE_BIG_NO_CHICKEN,CFG.SCORE_READY,CFG.SCORE_BIG_SET,CFG.SCORE_BIG_SET_SINGLE_WAIT,CFG.SCORE_SEVEN_PAIRS,CFG.SCORE_DRAGON_SEVEN_PAIRS,CFG.SCORE_FLUSH,CFG.SCORE_CLEAN_BIG_TRIPLETS,CFG.SCORE_CLEAN_SEVEN_PAIRS,CFG.SCORE_CLEAN_SINGLE_WAIT,CFG.SCORE_CLEAN_DRAGON_SEVEN_PAIRS]
	var expected := [4,14,24,24,14,24,24,44,24,34,44,54,64]
	for i in values.size(): eq([216+i],"L%d数值" % (216+i),values[i],float(expected[i]),"scripts/autoload/GameConfig.gd:6")
	var clean_big: Array = ["wan1","wan1","wan1","wan2","wan2","wan2","wan4","wan4","wan4","wan6","wan6","wan6","wan9","wan9"]
	var clean_seven: Array = ["wan1","wan1","wan2","wan2","wan3","wan3","wan4","wan4","wan5","wan5","wan6","wan6","wan9","wan9"]
	var clean_dragon: Array = ["wan1","wan1","wan1","wan1","wan2","wan2","wan3","wan3","wan5","wan5","wan7","wan7","wan9","wan9"]
	var four_mixed := [meld("wan1"),meld("wan2"),meld("tong3"),meld("tiao4")]
	var four_clean := [meld("wan1"),meld("wan2"),meld("wan4"),meld("wan6")]
	var specs := [
		["big",BIG,[],"wan2","all_triplets",14.0,[220,231]],
		["big_single",["wan9","wan9"],four_mixed,"wan9","big_triplet_single_wait",24.0,[221,239]],
		["seven",SEVEN,[],"tong7","seven_pairs",24.0,[222,232]],
		["dragon",DRAGON,[],"tong7","dragon_seven_pairs",44.0,[223,233]],
		["flush",FLUSH,[],"wan8","flush",24.0,[224,234]],
		["clean_big",clean_big,[],"wan6","clean_big_triplets",34.0,[225,235]],
		["clean_seven",clean_seven,[],"wan9","clean_seven_pairs",44.0,[226,236]],
		["clean_single",["wan9","wan9"],four_clean,"wan9","clean_single_wait",54.0,[227,238]],
		["clean_dragon",clean_dragon,[],"wan9","clean_dragon_seven_pairs",64.0,[228,237]]]
	for s in specs:
		var r := fixture()
		r.players[0].concealed = s[1].duplicate()
		r.players[0].melds = s[2].duplicate(true)
		win_meta(r,0,-1,s[3])
		begin("pattern_"+s[0],r,"胡牌张="+s[3])
		var p := RuleEngine.analyze(s[1],s[2],s[3])
		eq(s[6],"合法胡牌",p.win,true,"scripts/core/RuleEngine.gd:116")
		var info := WIN._pattern_info(p)
		eq(s[6],"最高牌型",info.get("key",""),s[4],"scripts/core/WinScoring.gd:109")
		eq(s[6],"牌型分",info.get("score",0),s[5],"scripts/core/WinScoring.gd:109")
		var result := settle(r)
		eq([241],"只一个牌型付款项",result.items[0].filter(func(x): return x.kind=="pattern").size(),1,"scripts/core/WinScoring.gd:9")
		eq([252],"大牌不叠干扣",label_amount(result,0,"干扣"),0.0,"scripts/core/WinScoring.gd:9")
		eq([252],"大牌不叠大干扣",label_amount(result,0,"大干扣"),0.0,"scripts/core/WinScoring.gd:9")
	for s in [["closed_big",BIG,"big_triplet_single_wait",[239]],["closed_flush_sequences",FLUSH,"clean_single_wait",[238,239]],["closed_clean_big",clean_big,"clean_single_wait",[238,239]]]:
		var r := fixture()
		r.players[0].concealed = s[1].duplicate()
		begin(s[0],r,"手牌胡前13张，无固定面子，胡wan9")
		eq(s[3],"不是仅剩一张单吊",RuleEngine.analyze(s[1],[],"wan9").get(s[2]),false,"scripts/core/RuleEngine.gd:101")
		if s[0]=="closed_big":
			eq([220,239],"闭手大对子仍14",WIN._pattern_info(RuleEngine.analyze(s[1],[],"wan9")).get("score"),14.0,"scripts/core/RuleEngine.gd:116")
		if s[0]=="closed_clean_big":
			eq([225,238],"闭手清大对仍34",WIN._pattern_info(RuleEngine.analyze(s[1],[],"wan9")).get("score"),34.0,"scripts/core/RuleEngine.gd:116")
	var r := fixture()
	r.players[0].concealed = FLUSH.duplicate()
	begin("flush_sequences",r,"清一色含顺子，胡wan9")
	eq([238,241],"有顺子清一色应24",WIN._pattern_info(RuleEngine.analyze(FLUSH,[],"wan9")).get("score"),24.0,"scripts/core/RuleEngine.gd:116")
	begin("removed_pattern")
	context["unit_input"] = "CFG.PATTERNS；直接调用WinScoring._pattern_info({clean_big_single_wait:true})，这是遗留分支单测，不宣称正常牌局可达"
	eq([240],"配置不含清大对单吊44",CFG.PATTERNS.any(func(x): return x.key=="clean_big_single_wait"),false,"scripts/autoload/GameConfig.gd:42")
	eq([240],"分支不返回清大对单吊44",WIN._pattern_info({"clean_big_single_wait":true}).get("score",0),0,"scripts/core/RuleEngine.gd:190")
	var wrong_suit := four_clean.duplicate(true)
	wrong_suit[0].tile = "tong1"
	eq([234],"固定面子跨花色不清",RuleEngine.analyze(["wan9","wan9"],wrong_suit,"wan9").flush,false,"scripts/core/RuleEngine.gd:88")
	eq([232],"有固定面子不七对",RuleEngine.analyze(["wan9","wan9"],four_clean,"wan9").seven_pairs,false,"scripts/core/RuleEngine.gd:116")

func _test_ready_and_win_fees() -> void:
	for special in [false,true]:
		var r := fixture()
		r.players[0].concealed = BIG.duplicate() if special else PLAIN.duplicate()
		r.players[0].ready = true
		win_meta(r,0,-1,"wan2" if special else "wan9")
		begin("ready_self_big" if special else "ready_self_plain",r,"0报听自摸; 牌型=大对子14或普通0; 普通牌只收24+鸡，不再加自摸4")
		var result := settle(r)
		for payer in [1,2,3]:
			eq([158,242,287],"座%d另付报听24" % payer,fee(result,payer,0,"报听胡牌"),24.0,"scripts/core/WinScoring.gd:9")
			eq([158,287],"座%d牌型加报听" % payer,result.pairwise[0][payer],38.0 if special else 24.0,"scripts/core/WinScoring.gd:9")
		eq([251],"不叠干扣",label_amount(result,0,"干扣"),0.0,"scripts/core/WinScoring.gd:9")
		eq([251],"不叠大干扣",label_amount(result,0,"大干扣"),0.0,"scripts/core/WinScoring.gd:9")
	for source_ready in [false,true]:
		var r := fixture()
		r.players[0].concealed = PLAIN.duplicate()
		r.players[0].ready = true
		r.players[1].concealed = waiting()
		r.players[1].ready = true
		r.players[2].ready = source_ready
		win_meta(r,0,2)
		begin("ready_ron_source_"+str(source_ready),r,"A=0 B=1均报听; C=2打wan9 → A胡; C报听="+str(source_ready))
		var result := settle(r)
		for payer in [1,2,3]:
			eq([160,165 if payer==2 else (166 if payer==1 else 167),269,279],"座%d定向报听付款" % payer,fee(result,payer,0,"报听胡牌"),24.0 if payer==2 else 0.0,"scripts/core/WinScoring.gd:9")
		eq([161],"无额外杀报",fee(result,2,0,"杀报"),0.0,"scripts/core/WinScoring.gd:9")
		eq([161],"放炮者是否报听不改变24",result.pairwise[0][2],24.0,"scripts/core/WinScoring.gd:9")
		eq([161],"没有44杀报流水",result.transfers.any(func(x): return x.reason=="杀报" and x.amount==44.0),false,"scripts/core/WinScoring.gd:9")
	for mode in ["normal","gan","big_gan","ron","rob"]:
		var r := fixture()
		r.players[0].concealed = PLAIN.duplicate()
		if mode=="normal": r.players[0].discards = ["tiao1"]
		if mode=="gan":
			r.players[1].concealed = waiting()
			r.players[1].discards = ["tong8"]
		win_meta(r,0,1 if mode in ["ron","rob"] else -1)
		r.round_meta.robbed_kong = mode=="rob"
		begin("base_"+mode,r,"单元结算; 0普通牌胡wan9; 只有指定的鸡与情境")
		var result := settle(r)
		var expected_label: String = {"normal":"自摸","gan":"干扣","big_gan":"大干扣","ron":"点炮基础分（叫牌）","rob":"抢杠胡基础分"}[mode]
		eq([216,217,218,246,247,248,250,253,259,276],"基础金额",label_amount(result,0,expected_label),{"normal":4.0,"gan":14.0,"big_gan":24.0,"ron":0.0,"rob":12.0}[mode],"scripts/core/WinScoring.gd:9")
		if mode in ["ron","rob","big_gan"]:
			eq([250,253,276],"不叠干扣14",label_amount(result,0,"干扣"),0.0,"scripts/core/WinScoring.gd:9")
		if mode in ["ron","rob"]:
			eq([253,276],"不叠大干扣24",label_amount(result,0,"大干扣"),0.0,"scripts/core/WinScoring.gd:9")
	for called in [false,true]:
		var r := fixture()
		r.players[0].concealed = BIG.duplicate()
		if called: r.players[1].concealed = waiting()
		win_meta(r,0,1,"wan2")
		r.last_discard = {"seat":1,"tile":"wan2","after_kong":true,"kong_kind":RoundState.KongKind.CONCEALED}
		begin("kong_ron_called_"+str(called),r,"1暗杠后首打wan2 → 0大对子胡; 1叫牌="+str(called))
		var result := settle(r)
		eq([249,277],"杠放炮基础17或21",fee(result,1,0,"点炮基础分（叫牌）")+fee(result,1,0,"点炮基础分（未叫牌）"),17.0 if called else 21.0,"scripts/core/WinScoring.gd:9")
		eq([277],"杠放炮加牌型14",result.pairwise[0][1],31.0 if called else 35.0,"scripts/core/WinScoring.gd:9")
		eq([249],"杠放炮不叠干扣",label_amount(result,0,"干扣")+label_amount(result,0,"大干扣"),0.0,"scripts/core/WinScoring.gd:9")
	var ron := fixture()
	ron.players[0].concealed = BIG.duplicate()
	ron.players[0].discards = ["tiao1"]
	ron.players[1].concealed = waiting()
	ron.players[1].discards = ["tong8"]
	win_meta(ron,0,1,"wan2")
	begin("ordinary_ron",ron,"1打wan2 → 0大对子胡; 两人普通鸡各2; 无翻鸡")
	var result := settle(ron)
	eq([275,276],"普通放炮差额14加2减2",result.pairwise[0][1],14.0,"scripts/core/WinScoring.gd:9; scripts/core/PaymentLedger.gd:60")
	var ready_diff := fixture()
	ready_diff.players[0].concealed = PLAIN.duplicate()
	ready_diff.players[0].ready = true
	ready_diff.players[2].concealed = waiting()
	ready_diff.players[2].discards = ["tiao1","tong8"]
	win_meta(ready_diff,0,2)
	begin("ready_direct",ready_diff,"2打wan9 → 0报听胡; 2鸡4，0鸡0; 24定向且鸡差额反向4")
	result = settle(ready_diff)
	eq([269],"定向24保持完整",fee(result,2,0,"报听胡牌"),24.0,"scripts/core/WinScoring.gd:9")
	eq([269],"鸡差额另付4",fee(result,0,2,"鸡分差额"),4.0,"scripts/core/PaymentLedger.gd:60")

func _test_kong_and_burn_payments() -> void:
	for kind in ["exposed","concealed","added"]:
		var r := fixture()
		r.players[0].melds = [meld("tiao1","add_kong" if kind=="added" else "kong",2,kind=="concealed")]
		begin("kong_pay_"+kind,r,"KongScoring单元:0杠tiao1，放杠者2；四家叫牌")
		var d := [0.0,0.0,0.0,0.0]
		var transfers: Array = []
		var items: Array = [[],[],[],[]]
		KG.pay(r,d,transfers,[true,true,true,true],items,"",false)
		var result := {"deltas":d,"transfers":transfers,"pairwise":PAY.pairwise_payments(transfers),"items":items}
		conservation(result)
		for payer in [1,2,3]:
			eq([107,108,120,130,261,280],"座%d杠基础付款" % payer,fee(result,payer,0,"*"),4.0 if kind!="exposed" or payer==2 else 0.0,"scripts/core/KongScoring.gd:6")
		eq([184],"杠基础独立4",items[0][0].base_amount,4.0,"scripts/core/KongScoring.gd:6")
		eq([184],"杠鸡独立8",items[0][0].chicken_amount,8.0,"scripts/core/KongScoring.gd:6")
	for reason in ["robbed_added_kong","concealed_discard","added_discard"]:
		var r := fixture()
		r.players[0].concealed = ["wan1","wan2","wan3","tong5","tong6","tong7","wan9"]
		r.players[0].melds = [meld("tiao1","kong",2,true,0),meld("tong8","pung" if reason=="robbed_added_kong" else ("kong" if reason=="concealed_discard" else "add_kong"),2,reason=="concealed_discard",2)]
		r.players[0].discard_count = 3
		r.players[1].concealed = PLAIN.duplicate()
		r.players[2].discards = ["wan1"]
		if reason=="robbed_added_kong":
			r.players[1].concealed = ["wan1","wan2","wan3","wan4","wan5","wan6","tiao2","tiao3","tiao4","tong6","tong7","tong8","wan9","wan9"]
		win_meta(r,1,0)
		if reason=="robbed_added_kong": r.round_meta.win_tile = "tong8"
		r.round_meta.flip_tile = "wan2"
		r.round_meta.burn_chicken_seat = 0
		r.round_meta.burn_chicken_reason = "robbed_added_kong" if reason=="robbed_added_kong" else "after_kong_discard"
		r.round_meta.robbed_kong = reason=="robbed_added_kong"
		r.last_discard = {"seat":0,"tile":"wan9","after_kong":reason!="robbed_added_kong","kong_kind":RoundState.KongKind.CONCEALED if reason=="concealed_discard" else RoundState.KongKind.ADD_KONG}
		begin("burn_income_"+reason,r,"0历史暗杠tiao1；"+("当前tong8加杠被1抢胡" if reason=="robbed_added_kong" else "当前tong8暗/加杠后打wan9被1胡")+"；0仍叫牌")
		var profile := CH.chicken_profile(r,0,"wan2")
		eq([210],"幺鸡八筒收入0",profile.held+profile.discarded,0.0,"scripts/core/ChickenScoring.gd:5")
		eq([210],"翻鸡收入0",profile.flipped,0.0,"scripts/core/ChickenScoring.gd:5")
		var result := settle(r)
		var kong_income := 0.0
		var total_income := 0.0
		var pattern_income := 0.0
		for x in result.transfers:
			if x.to != 0: continue
			total_income += x.amount
			if str(x.reason) in ["暗杠","明杠","加杠"]: kong_income += x.amount
			if CFG.PATTERNS.any(func(p): return p.label==x.reason): pattern_income += x.amount
		eq([210],"包括历史杠收入0",kong_income,0.0,"scripts/core/KongScoring.gd:6; scripts/core/KongScoring.gd:6")
		eq([210],"牌型收入0",pattern_income,0.0,"scripts/core/WinScoring.gd:9")
		eq([210],"所有收入0",total_income,0.0,"scripts/core/ScoringEngine.gd:10; scripts/core/KongScoring.gd:6")
	for kind in ["exposed","concealed","added"]:
		var r := fixture()
		r.players[0].concealed = ["wan1"]
		r.players[0].melds = [meld("tiao1","add_kong" if kind=="added" else "kong",1,kind=="concealed")]
		r.players[1].concealed = PLAIN.duplicate()
		r.players[2].concealed = waiting()
		win_meta(r,1,-1)
		begin("uncalled_kong_"+kind,r,"0未叫牌且杠tiao1，来源1；1胡、2叫牌；每个叫牌者应收基础4及杠鸡8")
		var result := settle(r)
		for target in [1,2]:
			eq([263],"未叫杠主向%d补基础4" % target,fee(result,0,target,"未叫牌杠分"),4.0,"scripts/core/ScoringEngine.gd:99")
			eq([263],"未叫杠主向%d补杠鸡8" % target,fee(result,0,target,"未叫牌杠中鸡"),8.0,"scripts/core/KongScoring.gd:6")

func _test_ledger_and_draws() -> void:
	begin("ledger_difference")
	var d := [0.0,0.0,0.0,0.0]
	var transfers: Array = []
	PAY.compare_chickens(d,transfers,[true,true,true,true],[2.0,4.0,6.0,8.0])
	var matrix := PAY.pairwise_payments(transfers)
	for a in 4:
		for b in range(a+1,4):
			eq([266,267,268],"鸡分两两差额%d-%d" % [a,b],matrix[a][b],float((a-b)*2),"scripts/core/PaymentLedger.gd:60")
	conservation({"deltas":d,"transfers":transfers,"pairwise":matrix})
	var r := fixture()
	r.players[0].concealed = PLAIN.duplicate()
	r.players[1].concealed = waiting()
	r.players[2].discards = ["tiao1","tong8"]
	r.players[2].discard_ids = [0,1]
	r.round_meta.charge_chickens = {"tiao1":{"owner":2,"location":"discard","discard_id":0}}
	win_meta(r)
	begin("uncalled_discards",r,"2未叫牌打出冲锋tiao1=4、普通tong8=2; 0胡、1叫牌")
	var result := settle(r)
	for target in [0,1]: eq([263],"向%d补出牌鸡6" % target,fee(result,2,target,"未叫牌出牌鸡"),6.0,"scripts/core/PaymentLedger.gd:60")
	eq([263],"未叫牌自身总分0",result.round_points[2],0.0,"scripts/core/ScoringEngine.gd:138")
	var total := fixture()
	total.players[0].concealed = ["wan1","wan2","wan3","tong2","tong3","tong4","tiao2","tiao3","tiao4","wan9","wan9"]
	total.players[0].melds = [meld("tiao1","kong",1,true)]
	win_meta(total)
	total.round_meta.flip_tile = "wan2"
	begin("called_total",total,"0自摸4 + 暗杠tiao1基础4 + 鸡8 + wan1/2/3翻鸡3 = 19")
	result = settle(total)
	eq([258],"胡分鸡分杠分翻鸡总和19",result.round_points[0],19.0,"scripts/core/ScoringEngine.gd:138")
	eq([258,266],"总和作为与空白未叫家差额",result.pairwise[0][1],19.0,"scripts/core/ScoringEngine.gd:10")
	var multi := fixture()
	multi.players[0].concealed = ["wan1","wan1","wan2","wan2","wan4","wan4","tiao2","tiao2","tiao5","tiao5","tong3","tong3","wan9","wan9"]
	multi.players[1].concealed = ["wan1","wan1","wan2","wan2","wan4","wan4","wan5","wan5","wan7","wan7","wan8","wan8","wan9","wan9"]
	win_meta(multi,0,2)
	multi.round_meta.winners = [0,1]
	begin("winner_pair_difference",multi,"2打wan9; 0小七对24、1清七对44同时胡；放炮者分别付牌型分，赢家之间不互付")
	result = settle(multi)
	eq([258,266,267,268,280],"赢家之间不再互付牌型差额",result.pairwise[1][0],0.0,"scripts/core/WinScoring.gd:9")
	eq([275,280],"放炮者付0小七对24",fee(result,2,0,"小七对"),24.0,"scripts/core/WinScoring.gd:81")
	eq([275,280],"放炮者付1清七对44",fee(result,2,1,"清七对"),44.0,"scripts/core/WinScoring.gd:81")
	eq([275,280],"放炮者多赢家合计68",result.deltas[2],-68.0,"scripts/core/WinScoring.gd:81")
	for all_called in [true,false]:
		var draw := fixture()
		for seat in (range(4) if all_called else [0,1]): draw.players[seat].concealed = waiting()
		draw.players[0].discards = ["tiao1"]
		draw.players[2].discards = ["tong8"]
		draw.round_meta.chicken_multiplier = 2
		begin("draw_all_"+str(all_called),draw,"流局；0出tiao1普通2，2出tong8普通2；四家叫牌="+str(all_called))
		result = finish_round(draw)
		eq([188,200,295,298],"流局无翻鸡",draw.round_meta.flip_tile,"","scripts/core/RoundState.gd:877")
		if all_called:
			for seat in 4: eq([292],"座%d本局不计分" % seat,result.deltas[seat],0.0,"scripts/core/ScoringEngine.gd:10")
			eq([293,294],"下局鸡倍数封顶2",draw.next_chicken_multiplier,2,"scripts/core/ScoringEngine.gd:10")
			eq([296],"叫牌家之间无付款",result.transfers,[],"scripts/core/ScoringEngine.gd:10")
		else:
			# 用户2026-10-18确认：双方出牌鸡之外每对额外4，最后统一翻倍。
			eq([297,300],"用户确认流局额外基础4整体翻倍",fee(result,2,0,"荒牌包鸡"),16.0,"scripts/core/PaymentLedger.gd:30")
	var draw_unit := fixture()
	begin("draw_chicken_unit",draw_unit,"PaymentLedger单元: called=[真,真,假,假],出牌鸡=[2,4,6,0]")
	d = [0.0,0.0,0.0,0.0]
	transfers = []
	PAY.pay_uncalled(d,transfers,[true,true,false,false],[2.0,4.0,6.0,0.0])
	result = {"deltas":d,"transfers":transfers,"pairwise":PAY.pairwise_payments(transfers)}
	eq([297,300],"未叫2向叫0补双方8",result.pairwise[0][2],8.0,"scripts/core/PaymentLedger.gd:30")
	eq([297,300],"未叫2向叫1补双方10",result.pairwise[1][2],10.0,"scripts/core/PaymentLedger.gd:30")
	conservation(result)
	var draw_kong := fixture()
	draw_kong.players[0].concealed = waiting().slice(3)
	draw_kong.players[0].melds = [meld("tiao1","kong",1,true)]
	begin("draw_kong",draw_kong,"0叫牌且暗杠tiao1；1/2/3未叫牌；流局继续结算杠")
	result = settle(draw_kong)
	for payer in [1,2,3]:
		eq([299,300],"流局座%d付杠4" % payer,fee(result,payer,0,"查叫暗杠"),4.0,"scripts/core/KongScoring.gd:6")
		eq([299,300],"流局座%d付杠鸡8" % payer,fee(result,payer,0,"杠中鸡"),8.0,"scripts/core/KongScoring.gd:6")

func _test_dealer_and_bonuses() -> void:
	for how in ["self","ron","kong_ron","rob"]:
		var r := fixture()
		r.dealer_seat = 3
		r.players[1].concealed = PLAIN.duplicate()
		win_meta(r,1,-1 if how=="self" else 0)
		r.round_meta.robbed_kong = how=="rob"
		if how=="kong_ron": r.last_discard = {"seat":0,"tile":"wan9","after_kong":true,"kong_kind":RoundState.KongKind.ADD_KONG}
		begin("dealer_"+how,r,"原庄3；赢家1，放炮/被抢者0；结算后检查下局庄家")
		finish_round(r)
		eq([304],"赢家成为下庄",r.next_dealer_seat,1,"scripts/core/RoundState.gd:905")
	var loss := fixture()
	loss.dealer_seat = 0
	loss.players[0].concealed = waiting()
	loss.players[2].discards = ["tiao1","tong8"]
	begin("dealer_draw_loss",loss,"0叫牌；1/2/3未叫；2多打普通tiao1和tong8各2故失分最多")
	finish_round(loss)
	eq([305],"未叫失分最多2当庄",loss.next_dealer_seat,2,"scripts/core/RoundState.gd:905")
	var tie := fixture()
	tie.dealer_seat = 0
	tie.players[0].concealed = waiting()
	begin("dealer_draw_tie",tie,"0叫牌；1/2/3均未叫且同分；随机只能选1/2/3")
	finish_round(tie)
	eq([305],"并列候选范围",tie.next_dealer_seat in [1,2,3],true,"scripts/core/RoundState.gd:905")
	var same_seed := fixture()
	same_seed.dealer_seat = 0
	same_seed.players[0].concealed = waiting()
	finish_round(same_seed)
	eq([305],"固定种子并列可重复",same_seed.next_dealer_seat,tie.next_dealer_seat,"scripts/core/RoundState.gd:994")
	var retained := fixture()
	retained.dealer_seat = 2
	for p in retained.players: p.concealed = waiting()
	begin("dealer_all_called",retained,"四家叫牌流局 → 开下一局")
	finish_round(retained)
	eq([306],"四叫连庄",retained.next_dealer_seat,2,"scripts/core/RoundState.gd:905")
	retained.start_round(0,1)
	eq([307],"下局继承庄家",retained.dealer_seat,2,"scripts/core/RoundState.gd:177")
	eq([307],"下局继承倍率",retained.round_meta.chicken_multiplier,2,"scripts/core/RoundState.gd:185")
	for count in [1,2,3,4,5]:
		for kong in [false,true]:
			var r := fixture()
			r.players[0].concealed = PLAIN.duplicate()
			r.players[0].just_drew = "wan9"
			r._draw_remaining_before = count
			r._kong_draw_turn = kong
			begin("bonus_%d_%s" % [count,kong],r,"0摸wan9自摸; 摸前余牌%d; 杠补=%s" % [count,kong])
			r._do_self_win(0)
			conservation(r.last_result,r.players.map(func(p): return p.score))
			for payer in [1,2,3]:
				eq([284],"座%d杠开5" % payer,fee(r.last_result,payer,0,"杠开"),5.0 if kong else 0.0,"scripts/core/WinScoring.gd:9")
				eq([285],"座%d海底5边界" % payer,fee(r.last_result,payer,0,"海底捞"),5.0 if count<=4 else 0.0,"scripts/core/RoundState.gd:777")
				if kong and count<=4: eq([286],"座%d双加分10" % payer,fee(r.last_result,payer,0,"杠开")+fee(r.last_result,payer,0,"海底捞"),10.0,"scripts/core/WinScoring.gd:9")
	var negative := fixture()
	negative.apply_scores([1.0,200.0,200.0,399.0])
	negative.players[1].concealed = PLAIN.duplicate()
	win_meta(negative,1,-1)
	begin("negative_score",negative,"四家总分800，座0仅1分；座1自摸后座0允许负分")
	finish_round(negative)
	eq([11],"分数允许负值",negative.players[0].score<0,true,"scripts/core/RoundState.gd:894")

func _test_ui_and_absences() -> void:
	var r := fixture()
	r.players[0].concealed = ["wan3","wan1","wan3"]
	r.players[0].just_drew = "wan3"
	r.phase = RoundState.Phase.IDLE
	begin("discard_entity",r,"同值牌在索引0和2；点击索引0应打0，保留刚摸索引2")
	r._discard(0,"wan3",0)
	var event: Dictionary = r.visual_events.filter(func(e): return e.type=="discard")[0]
	eq([73],"实际打出点击索引0",event.discard_index,0,"scripts/core/RoundState.gd:389")
	eq([73],"不替换成摸牌实体",event.discard_from_draw,false,"scripts/core/RoundState.gd:393")
	begin("tile_selection")
	var tile := TileView.new()
	tile.set_table_position(Vector2(10,20))
	tile.set_selected(true)
	eq([74],"选中不永久上移",tile.position,Vector2(10,20),"scripts/ui/TileView.gd:70")
	tile.set_selected(false)
	eq([74],"取消选中回布局",tile.position,Vector2(10,20),"scripts/ui/TileView.gd:70")
	tile.free()
	var view := Control.new()
	var area = load("res://scripts/ui/table/PlayerTileAreas.gd").new(view)
	for source in [1,2,3]:
		var layout: Dictionary = area._meld_tile_layout(meld("wan3","pung",source),0,1.0,2.0)
		eq([99],"碰来源%d无横牌标记" % source,layout.sideways,-1,"scripts/ui/table/PlayerTileAreas.gd:260")
	view.free()
	var authority := fixture()
	authority.start_round(0,1)
	var client := fixture()
	var emitted: Array = []
	client.visual_event.connect(func(e): emitted.append(e))
	begin("reconnect",authority,"已完成发牌; 新客户端首次apply_sync直接恢复")
	client.apply_sync(authority.serialize())
	eq([62],"重连跳过历史动画",emitted.size(),0,"scripts/core/RoundPresentation.gd:36")
	for seat in 4: eq([62],"座%d同步最终牌" % seat,client.players[seat].concealed,authority.players[seat].concealed,"scripts/core/RoundSerializer.gd:54")
	var absent := fixture()
	absent.players[0].concealed = PLAIN.duplicate()
	absent.players[0].just_drew = "wan9"
	begin("absent_actions",absent)
	for action in ["chow","false_win","fake_win"]:
		eq([14] if action=="chow" else [0],action+"无响应入口",ACT.valid_response({"can_win":true,"can_pong":true,"can_kong":true},{"action":action}),false,"scripts/core/LegalActions.gd:98")
	var buttons := FileAccess.get_file_as_string("res://scripts/ui/table/TableActions.gd")
	eq([0],"无诈胡按钮",buttons.contains('"诈胡"'),false,"scripts/ui/table/TableActions.gd:185")
	var scoring := FileAccess.get_file_as_string("res://scripts/core/WinScoring.gd")+FileAccess.get_file_as_string("res://scripts/core/ScoringEngine.gd")+FileAccess.get_file_as_string("res://scripts/autoload/GameConfig.gd")
	eq([0],"无诈胡处罚13入口",scoring.contains("诈胡") or scoring.contains("SCORE_FALSE") or scoring.contains("SCORE_FAKE"),false,"scripts/core/ScoringEngine.gd:10; scripts/autoload/GameConfig.gd:21")
	var invalid := fixture()
	invalid.players[0].concealed = ["wan1"]
	invalid.players[0].just_drew = "wan1"
	begin("false_win_rejected",invalid,"不成胡手牌请求self_win")
	eq([0],"不成胡拒绝结算",invalid.submit_turn(0,{"self_win":true}),false,"scripts/core/LegalActions.gd:78")
	eq([0],"拒绝后不扣13",invalid.players[0].score,200.0,"scripts/core/RoundState.gd:319")

func _test_additional_boundaries() -> void:
	var flow := fixture()
	flow.players[0].concealed = ["wan9"]
	flow.players[0].just_drew = "wan9"
	flow.players[1].concealed = waiting()
	flow.players[0].ready = true
	begin("passport_flow_source_ready",flow,"0报听后打wan9；1普通等待wan9，应出现胡牌响应")
	flow.submit_turn(0,{"discard":"wan9"})
	eq([142,159],"普通赢家应收到胡牌窗口",flow._awaiting_response.get("seat",-1),1,"scripts/core/RoundState.gd:457; scripts/core/LegalActions.gd:121")

	var exposed_flow := fixture()
	exposed_flow.players[0].concealed = ["wan9"]
	exposed_flow.players[0].just_drew = "wan9"
	exposed_flow.players[1].concealed = waiting()
	exposed_flow._kong_draw_turn = true
	exposed_flow._kong_draw_kind = RoundState.KongKind.EXPOSED
	begin("passport_flow_exposed",exposed_flow,"明杠后打wan9；1普通等待，不应出现胡牌响应")
	exposed_flow.submit_turn(0,{"discard":"wan9"})
	eq([143],"明杠后普通等待不出现胡牌窗口",exposed_flow._awaiting_response.get("seat",-1),-1,"scripts/core/LegalActions.gd:122")
	var r := fixture()
	r.players[0].concealed = PLAIN.duplicate()
	r.players[0].just_drew = "wan9"
	r.wall.remaining = 0
	begin("last_tile_win",r,"已摸到最后一张wan9成胡，墙余0；接受自摸后不被流局覆盖")
	eq([50],"最后一张仍可自摸",r.submit_turn(0,{"self_win":true}),true,"scripts/core/LegalActions.gd:8")
	eq([50],"赢家保留",r.round_meta.winner,0,"scripts/core/RoundState.gd:769")
	conservation(r.last_result,r.players.map(func(p): return p.score))
	var tied_results: Array = []
	for seed_value in range(SEED,SEED+12):
		var tied := fixture(seed_value)
		tied.dealer_seat = 0
		tied.players[0].concealed = waiting()
		begin("tie_random_%d" % seed_value,tied,"三位未叫者同分；仅1/2/3有资格；跨固定种子观察随机选择")
		context.seed = seed_value
		finish_round(tied)
		tied_results.append(tied.next_dealer_seat)
	begin("tie_random_variety")
	context["unit_input"] = "种子20261018..20261029；座0叫牌，1/2/3均未叫且失分相同；每局均结算验证800"
	var distinct: Dictionary = {}
	for seat in tied_results: distinct[seat] = true
	eq([305],"并列随机不是固定连庄",distinct.size()>1,true,"scripts/core/RoundState.gd:905")
	var draw := fixture()
	draw.players[0].concealed = waiting().slice(3)
	draw.players[0].melds = [meld("tiao1","kong",1,true)]
	for seat in [1,2,3]: draw.players[seat].concealed = waiting()
	begin("all_called_with_kong",draw,"四家都叫牌且0有暗杠；本局所有付款0；连续下一局再四叫流局")
	finish_round(draw)
	eq([292,296],"四叫即使有杠不付款",draw.last_result.transfers,[],"scripts/core/ScoringEngine.gd:10")
	draw.start_round(0,1)
	for p in draw.players: p.concealed = waiting()
	finish_round(draw)
	eq([294],"连续四叫倍率仍2",draw.next_chicken_multiplier,2,"scripts/core/ScoringEngine.gd:10")
	var rob := fixture()
	rob.players[0].concealed = BIG.duplicate()
	rob.players[0].discards = ["tiao1"]
	win_meta(rob,0,1,"wan2")
	rob.round_meta.robbed_kong = true
	begin("rob_pattern_chicken",rob,"被抢者1；0大对子14且普通tiao1鸡2；1→0应12+14+2=28")
	var result := settle(rob)
	eq([134,278],"抢杠另加牌型鸡分28",result.pairwise[0][1],28.0,"scripts/core/WinScoring.gd:9")
	for target in [2,3]: eq([269,278],"无关座%d不付抢杠12" % target,fee(result,target,0,"抢杠胡基础分"),0.0,"scripts/core/WinScoring.gd:9")
	var burn := fixture()
	burn.players[0].concealed = waiting()
	burn.players[1].concealed = PLAIN.duplicate()
	burn.players[2].discards = ["tiao1"]
	win_meta(burn,1,0)
	burn.round_meta.burn_chicken_seat = 0
	burn.round_meta.burn_chicken_reason = "robbed_added_kong"
	burn.round_meta.robbed_kong = true
	begin("burn_uncalled_income",burn,"0叫牌但被烧；2未叫并打普通tiao1鸡2；0所有收入必须0")
	result = settle(burn)
	eq([210],"烧鸡也不能收未叫者出牌鸡",fee(result,2,0,"*"),0.0,"scripts/core/PaymentLedger.gd:60; scripts/core/ScoringEngine.gd:10")
	var no_pong := fixture()
	no_pong.players[1].concealed = ["wan2"]
	begin("pong_count_negative",no_pong)
	eq([95],"仅一张不能碰",no_pong.legal_response_options(1,0,"wan2",RoundState.ResponseStage.MELD).can_pong,false,"scripts/core/LegalActions.gd:94")
	var no_add := fixture()
	no_add.players[0].concealed = ["wan7"]
	begin("add_kong_requires_pung",no_add)
	eq([127],"没有碰不能加杠",no_add.legal_turn_options(0).add_kong,[],"scripts/core/LegalActions.gd:18")

func _test_confirmed_clarifications() -> void:
	# 文档未明处的直接答复见 tests/rules_clarifications_2026-10-18.md。
	var selected: Array = []
	for tied in [false,true]:
		for seed_value in range(SEED,SEED+12):
			var r := fixture(seed_value)
			r.players[0].concealed = SEVEN.duplicate()
			r.players[1].concealed = SEVEN.duplicate() if tied else DRAGON.duplicate()
			win_meta(r,0,2,"tong7")
			r.round_meta.winners = [0,1]
			r.wall = null
			begin("confirmed_multi_dealer_%s_%d" % [tied,seed_value],r,"0/1同时胡2；净得分最高赢家当庄，并列随机；墙空不翻鸡")
			context.seed = seed_value
			finish_round(r)
			if tied:
				eq([304],"并列赢家净分相同",r.last_result.deltas[0],r.last_result.deltas[1],"scripts/core/RoundState.gd:905")
				eq([304],"庄家仅从并列赢家选择",r.next_dealer_seat in [0,1],true,"scripts/core/RoundState.gd:905")
				selected.append(r.next_dealer_seat)
				var repeat := fixture(seed_value)
				repeat.round_meta = r.round_meta.duplicate(true)
				repeat._last_deltas = r.last_result.deltas.duplicate()
				eq([304],"同种子同并列结果",repeat._choose_next_dealer([true,true,false,false]),r.next_dealer_seat,"scripts/core/RoundState.gd:905")
			else:
				eq([304],"不按首个赢家而按净得分选1",r.next_dealer_seat,1,"scripts/core/RoundState.gd:905")
	begin("confirmed_multi_random")
	eq([304],"并列随机覆盖两个赢家",selected.has(0) and selected.has(1),true,"scripts/core/RoundState.gd:905")
	for dealer in 4:
		var r := fixture()
		r.next_dealer_seat = dealer
		r.start_round(0,1)
		begin("confirmed_fixed_seats_%d" % dealer,r,"用户确认编号固定、庄家身份移动")
		eq([19,304,307],"编号始终0到3",r.players.map(func(p): return p.seat),[0,1,2,3],"scripts/core/RoundState.gd:177")
		eq([304,307],"庄家身份移动",r.players[dealer].is_dealer,true,"scripts/core/RoundState.gd:177")
		for die in range(1,7):
			var target := posmod(dealer+(2 if die in [1,3,5] else (3 if die==4 else 1)),4)
			var segment: Dictionary = r.wall._wall_seg_for_seat(target)
			eq([42,43],"骰%d跳过点数乘2" % die,WallRing.compute_break(die,dealer),int(segment.start)+2*die,"scripts/core/WallRing.gd:44")
	var called := fixture()
	called.players[0].concealed = PLAIN.duplicate()
	called.players[1].concealed = waiting(DRAGON)
	win_meta(called,0,2)
	begin("confirmed_nonwinner",called,"座1虽听龙七对但没胡，胡牌分必须0")
	var result := settle(called)
	eq([258,275],"叫牌但没胡不收潜在44",result.pairwise[1][3],0.0,"scripts/core/WinScoring.gd:9")
	# 所有付款先以单倍结算，再统一缩放；按六对和每笔流水独立核对。
	for kind in ["ready_plain","ready_big","rob","kong_called","kong_uncalled","exposed","concealed","added","uncalled_kong","mixed_draw","bonuses"]:
		var r := fixture()
		r.players[0].concealed = BIG.duplicate() if kind=="ready_big" else PLAIN.duplicate()
		win_meta(r,0,-1 if kind in ["ready_plain","ready_big","bonuses"] else 1)
		r.players[0].ready = kind in ["ready_plain","ready_big","rob","kong_called","kong_uncalled"]
		r.round_meta.flip_tile = "wan2"
		r.players[0].discards = ["tiao1"]
		if kind=="rob": r.round_meta.robbed_kong = true
		if kind in ["kong_called","kong_uncalled"]:
			r.last_discard = {"after_kong":true,"kong_kind":RoundState.KongKind.CONCEALED}
			if kind=="kong_called": r.players[1].concealed = waiting()
		if kind in ["exposed","concealed","added"]:
			r.players[0].concealed = PLAIN.slice(3)
			r.players[0].melds = [meld("tiao1","add_kong" if kind=="added" else "kong",1,kind=="concealed")]
		if kind=="uncalled_kong": r.players[1].melds = [meld("tong8","kong",2)]
		if kind=="mixed_draw":
			r.round_meta.winner = -1
			r.round_meta.winners = []
			r.players[0].concealed = waiting()
		if kind=="bonuses":
			r.round_meta.kong_draw_seat = 0
			r.round_meta.last_four_self_draw_seat = 0
		begin("confirmed_multiplier_"+kind,r,"同状态单倍结算，再倍率2；所有款项/明细和六对矩阵均恰好翻倍")
		var single := settle(r)
		r.round_meta.chicken_multiplier = 2
		var doubled := settle(r)
		for seat in 4:
			eq([293,258],"座%d净分整体乘2" % seat,doubled.deltas[seat],single.deltas[seat]*2,"scripts/core/ScoringEngine.gd:138")
			eq([293,258],"座%d项目合计乘2" % seat,doubled.round_points[seat],single.round_points[seat]*2,"scripts/core/ScoringEngine.gd:138")
			for other in range(seat+1,4):
				eq([293,266],"矩阵%d-%d统一乘2" % [seat,other],doubled.pairwise[seat][other],single.pairwise[seat][other]*2,"scripts/core/ScoringEngine.gd:138")
			for i in single.items[seat].size():
				eq([293],"座%d明细%d乘2" % [seat,i],doubled.items[seat][i].amount,single.items[seat][i].amount*2,"scripts/core/ScoringEngine.gd:138")
		for i in single.transfers.size():
			eq([293,269],"流水%d乘2" % i,doubled.transfers[i].amount,single.transfers[i].amount*2,"scripts/core/ScoringEngine.gd:138")
			eq([269],"流水%d指定付款人不变" % i,doubled.transfers[i].from,single.transfers[i].from,"scripts/core/ScoringEngine.gd:138")
	var burn := fixture()
	burn.players[0].discards = ["tiao1"]
	burn.players[0].melds = [meld("tong8","kong",2,true)]
	burn.players[1].concealed = PLAIN.duplicate()
	burn.players[2].concealed = waiting()
	burn.round_meta.burn_chicken_seat = 0
	win_meta(burn,1,0)
	begin("burn_preserves_debts",burn,"0未叫烧鸡但仍付普通出牌鸡2、暗杠4、杠中鸡8给1/2；收入0")
	result = settle(burn)
	for receiver in [1,2]:
		eq([210,263],"烧鸡向%d仍付出牌鸡2" % receiver,fee(result,0,receiver,"未叫牌出牌鸡"),2.0,"scripts/core/ChickenScoring.gd:5")
		eq([210,263],"烧鸡向%d仍付杠4" % receiver,fee(result,0,receiver,"未叫牌杠分"),4.0,"scripts/core/ScoringEngine.gd:99")
		eq([210,263],"烧鸡向%d仍付杠鸡8" % receiver,fee(result,0,receiver,"未叫牌杠中鸡"),8.0,"scripts/core/KongScoring.gd:6")
	for payer in [1,2,3]: eq([210],"烧鸡无座%d收入" % payer,fee(result,payer,0,"*"),0.0,"scripts/core/PaymentLedger.gd:12")
	begin("cancel_income_unit")
	var deltas := [0.0,0.0,0.0,0.0]
	var transfers: Array = []
	PAY.transfer(deltas,transfers,1,0,9.0,"入账")
	PAY.transfer(deltas,transfers,0,2,5.0,"支出")
	PAY.cancel_income(deltas,transfers,0)
	eq([210],"取消入账不取消支出",deltas,[-5.0,0.0,5.0,0.0],"scripts/core/PaymentLedger.gd:12")
	PAY.cancel_income(deltas,transfers,0)
	eq([210],"重复取消幂等",deltas,[-5.0,0.0,5.0,0.0],"scripts/core/PaymentLedger.gd:12")
	conservation({"deltas":deltas,"transfers":transfers,"pairwise":PAY.pairwise_payments(transfers)})
