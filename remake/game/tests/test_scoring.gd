extends SceneTree

const Score := preload("res://src/anshun/scoring/ScoringEngine.gd")
const Rules := preload("res://src/anshun/scoring/RuleEngine.gd")
const Round := preload("res://src/domain/Round.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	_reference_examples()
	_details_example()
	_dead_wait()
	_first_chicken()
	_burned_debts()
	_three_winners()
	_fee_combinations()
	_pattern_fees()
	print("Scoring: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr(message)

func _tiles(spec: String) -> Array:
	var values: Array = []
	for group in spec.split(" ", false):
		var suit: String = {"w": "wan", "t": "tiao", "b": "tong"}[group.left(1)]
		for rank in group.substr(1):
			values.append(suit + rank)
	return values

func _facts(hands: Array) -> Dictionary:
	var players: Array = []
	for hand in hands:
		players.append({"concealed": _tiles(hand), "melds": [], "discards": [], "discard_ids": [], "ready": false})
	return {"players": players, "round_meta": {}, "last_discard": {}}

func _kong(tile: String, kind: String, source: int) -> Dictionary:
	return {"kind": "add_kong" if kind == "add_kong" else "kong", "tile": tile,
		"from_seat": source, "concealed": kind == "concealed", "tile_ids": [96, 97, 98, 99]}

func _paid(result: Dictionary, payer: int, receiver: int, reason: String) -> float:
	var total := 0.0
	for row in result.transfers:
		if row.from == payer and row.to == receiver and row.reason == reason:
			total += row.amount
	return total

func _verify_ledger(result: Dictionary) -> void:
	var deltas := [0.0, 0.0, 0.0, 0.0]
	var pairs := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
	for row in result.transfers:
		var sum := 0.0
		for source in row.sources:
			sum += source.contribution
		_check(sum == row.unit_amount and row.amount == sum * result.multiplier, "transfer sources and single final multiplier reconcile")
		deltas[row.from] -= row.amount
		deltas[row.to] += row.amount
		pairs[row.from][row.to] -= row.amount
		pairs[row.to][row.from] += row.amount
	_check(result.deltas == deltas, "all four nets reconcile with transfers")
	_check(result.pairwise == pairs, "all six pairwise nets reconcile with transfers")

func _reference_examples() -> void:
	# 统一文档 §11.6，例1：未叫者的普通翻鸡杠只有基础4债务。
	var facts := _facts(["w123 t234 b456 t111 b99", "w1389 t258 b147", "", ""])
	facts.round_meta = {"winners": [0], "self_draw": true, "win_tile": "tong9", "flip_tile": "wan6"}
	facts.players[1].melds.append(_kong("wan5", "concealed", -1))
	var scored := Score.settle(facts)
	_check(scored.called == [true, false, false, false], "example 1: called states")
	_check(scored.deltas == [34.0, -14.0, -10.0, -10.0], "example 1: B pays exactly 14, not 18")
	_check(_paid(scored, 1, 0, "未叫牌杠分") == 4.0 and _paid(scored, 1, 0, "未叫牌杠中鸡") == 0.0,
		"example 1: no ordinary flip debt")
	var debts: Array = scored.items[1]
	_check(debts.size() == 1 and debts[0].amount == -4.0 and debts[0].tiles == ["wan5", "wan5", "wan5", "wan5"]
		and debts[0].tile_ids == [96, 97, 98, 99] and debts[0].opponents == [0], "example 1: item is only the actual four-point kong debt")
	_verify_ledger(scored)

	# 例2：部分叫牌流局，叫者之间不结鸡分差或杠费。
	for kind in ["concealed", "add_kong"]:
		facts = _facts(["w123 t234 b123 w9", "w678 t567 b456999 t9", "", ""])
		facts.players[0].melds.append(_kong("wan5", kind, -1))
		scored = Score.settle(facts)
		_check(scored.called == [true, true, false, false] and scored.pairwise[0][1] == 0.0,
			"example 2: called players do not settle between themselves")
		_check(scored.deltas == [16.0, 8.0, -12.0, -12.0] and scored.next_chicken_multiplier == 2,
			"example 2: other pairs still pay, next round doubles")
		_verify_ledger(scored)

	# 例3：换成明杠，另外两家也叫牌，实际入账与项目为空。
	facts = _facts(["w123 t234 b123 w9", "w678 t567 b456999 t9", "w123456 t234 b234 w9", "w123456 t234 b234 w9"])
	facts.players[0].melds.append(_kong("wan5", "exposed", 1))
	scored = Score.settle(facts)
	_check(scored.all_called_draw and scored.deltas == [0.0, 0.0, 0.0, 0.0] and scored.transfers.is_empty()
		and scored.items == [[], [], [], []], "example 3: all-called draw has zero entries including exposed kong")
	_verify_ledger(scored)
	facts = _facts(["w3", "t1", "", ""])
	facts.players[0].melds.append(_kong("wan5", "exposed", 1))
	facts.players[1].discards.append("tong8")
	scored = Score.settle(facts)
	_check(not scored.all_called_draw and scored.deltas == [0.0, 0.0, 0.0, 0.0] and scored.transfers.is_empty()
		and scored.items == [[], [], [], []], "all-uncalled draw has no recipient or fictional scoring lines")
	_verify_ledger(scored)

func _dead_wait() -> void:
	var file := "res://tests/fixtures/scoring/dead_wait_snapshot.json"
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	facts["last_discard"] = {}
	for row in facts.players:
		row["ready"] = false
	facts.round_meta.winners = facts.round_meta.winners.map(func(seat): return int(seat))
	var hand: Dictionary = facts.players[1]
	_check(Rules.waiting_tiles(hand.concealed, hand.melds).is_empty(), "dead wait does not yield a playable draw")
	_check(not Rules.can_win_on(hand.concealed, hand.melds, "tiao7"), "actual fifth copy is invalid")
	var snapshot := facts.duplicate(true)
	var score := Score.settle(facts)
	_check(facts == snapshot and Score.settle(facts) == score, "scoring is repeatable and does not mutate input")
	_check(score.called == [true, true, false, true], "dead wait is called for settlement")
	_check(score.deltas == [5.0, 5.0, -47.0, 37.0], "dead-wait snapshot four exact nets")
	var expected_pairs := [[0.0, -2.0, 14.0, -7.0], [2.0, 0.0, 12.0, -9.0], [-14.0, -12.0, 0.0, -21.0], [7.0, 9.0, 21.0, 0.0]]
	_check(score.pairwise == expected_pairs, "dead-wait snapshot all six exact pairs: %s" % [score.pairwise])
	_check(_paid(score, 0, 1, "明杠") == 4.0 and _paid(score, 1, 0, "未叫牌杠分") == 0.0, "dead wait earns the source-directed kong fee")
	_verify_ledger(score)
	facts.round_meta.chicken_multiplier = 2
	score = Score.settle(facts)
	_check(score.deltas == [10.0, 10.0, -94.0, 74.0] and score.next_chicken_multiplier == 1, "dead-wait fees double once")
	_verify_ledger(score)

func _details_example() -> void:
	# 统一文档 M17，基础4、幺鸡6、八筒6均针对对家，双倍净增32。
	var facts := _facts(["w123456 t3", "w123456 t234 b234 w9", "", "w123456 t234 b234 w9"])
	facts.players[0].melds = [
		{"kind": "pung", "tile": "tiao1", "tile_ids": [31, 32, 33]},
		{"kind": "pung", "tile": "tong8", "tile_ids": [41, 42, 43]},
	]
	facts.round_meta.chicken_multiplier = 2
	var score := Score.settle(facts)
	_check(score.called == [true, true, false, true], "M17 example: only the opposite seat is uncalled")
	_check(score.deltas[0] == 32.0 and score.pairwise[0] == [0.0, 0.0, 32.0, 0.0], "M17 example: seat0 nets +32 from opposite")
	var items: Array = score.items[0]
	_check(items.size() == 3 and items.all(func(item): return item.opponents == [2]), "M17 example: every item has only the opposite seat as payer")
	_check(items.any(func(item): return item.kind == "penalty" and item.amount == 4.0), "M17 example: individual base remains +4")
	_check(items.any(func(item): return item.tile_ids == [31, 32, 33] and item.amount == 6.0), "M17 example: three actual one-bamboo contribute +6")
	_check(items.any(func(item): return item.tile_ids == [41, 42, 43] and item.amount == 6.0), "M17 example: three actual eight-dots contribute +6")
	_check(_paid(score, 2, 0, "荒牌包鸡") == 24.0 and _paid(score, 2, 0, "荒牌基础补付") == 8.0, "M17 example: the full trace reconciles")
	_verify_ledger(score)

func _dealt_round(hands: Dictionary, winning_draw: String, flip: String, white: int, inherited: int) -> Round:
	var fixed := {62: winning_draw, 63: flip}
	for seat in hands:
		var offset := posmod(1 - int(seat), 4)
		var values := _tiles(hands[seat])
		for index in values.size():
			var draw_offset := 48 + offset if index == 12 else (index / 4) * 16 + offset * 4 + index % 4
			fixed[10 + draw_offset] = values[index]
	var pool := Catalog.values(8427)
	for value in fixed.values():
		_check(pool.has(value), "test deck has at most four copies of each tile")
		pool.erase(value)
	var deck: Array = []
	for id in 108:
		deck.append(fixed[id] if fixed.has(id) else pool.pop_back())
	var round := Round.new()
	_check(round.start(1, 5, white, deck, inherited) and round.begin_dealer_turn(), "scoring fixture follows real deal and dealer draw")
	return round

func _first_chicken() -> void:
	for tile in ["tiao1", "tong8"]:
		for gold in [false, true]:
			var waiting := "t2345678923455" if tile == "tiao1" else "b1234567923455"
			var round := _dealt_round({0: waiting}, tile, tile if gold else "wan9", 2, 1)
			var id: int = round.players[1].draw_id
			_check(round.submit(1, round.prompt_id, "discard", id), "first chicken leaves dealer hand")
			_check(round.round_meta.charge_chickens[tile].location == "discard", "first public discard begins as a charge chicken")
			_check(round.submit(0, round.prompt_id, "win"), "flush hand may claim first chicken")
			if round.phase == "response":
				round.expire_responses(round.prompt_id)
			var facts := round.settlement_facts()
			_check(not facts.players[1].discard_ids.has(id) and facts.players[0].concealed_ids.back() == id,
				"winning projection uses actual discard ID and source no longer owns it")
			var score := Score.settle(facts)
			_check(not score.items[1].any(func(item): return item.tile_ids.has(id)), "first chicken generates no discard debt")
			var chicken: Array = score.items[0].filter(func(item): return item.kind == "chicken" and item.tile_ids.has(id))
			_check(chicken.size() == 1 and chicken[0].amount == (4.0 if gold else 2.0), "winner receives only ordinary/ordinary gold chicken")
			_verify_ledger(score)
			# 把同一胜张当作后续普通鸡，来源须保留这一张的实际牌 ID 与鸡分。
			facts.round_meta.resolved_chicken_discards = [{"owner": 1, "tile": tile, "charge": false, "discard_id": id}]
			var later := Score.settle(facts)
			var ordinary: Array = later.items[1].filter(func(item): return item.get("source", "") == "discard" and item.tile_ids == [id])
			_check(ordinary.size() == 1 and absf(ordinary[0].amount) == (4.0 if gold else 2.0),
				"later ordinary chicken still scores its original discard")
			_verify_ledger(later)

func _burned_debts() -> void:
	var facts := _facts(["w14 t9 b2", "w12345699 t234 b234", "w1234569 t234 b234", ""])
	facts.players[0].melds = [_kong("tong8", "concealed", -1),
		{"kind": "pung", "tile": "tiao1", "tile_ids": [30, 31, 32]}, {"kind": "pung", "tile": "wan6", "tile_ids": [45, 46, 47]}]
	facts.players[0].discards = ["tiao1"]
	facts.players[0].discard_ids = [33]
	facts.round_meta = {"winners": [1], "discard_seat": 0, "robbed_kong": true, "burn_chicken_seat": 0, "win_tile": "wan6"}
	var score := Score.settle(facts)
	_check(score.called == [false, true, true, false], "burn fixture keeps the source uncalled")
	_check(score.deltas == [-52.0, 32.0, 20.0, 0.0], "burn removes income and keeps real outgoing debt")
	for receiver in [1, 2]:
		_check(_paid(score, 0, receiver, "未叫牌出牌鸡") == 2.0, "burn keeps discard debt")
		_check(_paid(score, 0, receiver, "未叫牌碰鸡") == 6.0, "burn keeps pong debt")
		_check(_paid(score, 0, receiver, "未叫牌杠中鸡") == 8.0, "burn keeps kong chicken debt")
		_check(_paid(score, 0, receiver, "未叫牌杠分") == 4.0, "burn keeps kong base debt")
	_check(_paid(score, 0, 1, "抢杠胡基础分") == 12.0, "rob-kong fee is independent")
	_check(score.transfers.all(func(row): return row.to != 0), "burned seat receives no credit")
	_check(facts.players[0].melds[2].tile_ids == [45, 46, 47], "the previously legal pung is preserved")
	_verify_ledger(score)

func _three_winners() -> void:
	var round := _dealt_round({0: "w1122334456677", 3: "t112233445566 w5", 2: "b112233445566 w5"}, "wan5", "wan9", 5, 2)
	var id: int = round.players[1].draw_id
	_check(round.submit(1, round.prompt_id, "discard", id), "discard opens multiple-winner response")
	for seat in [2, 3, 0]:
		_check(round.submit(seat, round.prompt_id, "win"), "all three winners can respond independently")
	if round.phase == "response":
		round.expire_responses(round.prompt_id)
	var score := Score.settle(round.settlement_facts())
	_check(score.winners == [0, 3, 2] and score.multiplier == 2, "real multiwinner order and two sources of double capped at two")
	_check(score.deltas == [92.0, -196.0, 36.0, 68.0], "all three winners receive separate correct fees")
	_check(score.pairwise == [[0.0, 92.0, 4.0, -4.0], [-92.0, 0.0, -48.0, -56.0], [-4.0, 48.0, 0.0, -8.0], [4.0, 56.0, 8.0, 0.0]],
		"multiwinner six pairs and net chicken offsets: %s" % [score.pairwise])
	for seat in score.winners:
		var patterns: Array = score.items[seat].filter(func(item): return item.kind == "pattern")
		_check(patterns.size() == 1 and patterns[0].tile_ids == [id] and patterns[0].opponents == [1],
			"each pattern uses the same physical winning tile and only its actual payer")
	_verify_ledger(score)

func _fee_combinations() -> void:
	var facts := _facts(["w11122299 t444 b333", "", "", ""])
	facts.players[0].ready = true
	facts.players[1].ready = true
	facts.round_meta = {"winners": [0], "discard_seat": 1, "win_tile": "wan9", "chicken_multiplier": 2}
	var score := Score.settle(facts)
	_check(score.deltas == [108.0, -108.0, 0.0, 0.0], "big-triplets 14 and two ready charges deduplicate base4 twice")
	_check(_paid(score, 1, 0, "大对子") == 20.0 and _paid(score, 1, 0, "报听胡牌") == 48.0
		and _paid(score, 1, 0, "输家报听") == 40.0 and _paid(score, 1, 0, "杀报") == 0.0, "ready payer, readiness and pattern have separate ledger entries")
	_verify_ledger(score)

	for kind in ["concealed", "add_kong", "exposed", "rob"]:
		for called in [true, false]:
			facts = _facts(["w12345699 t234", "w1234569 t234 b234" if called else "", "", ""])
			facts.players[0].melds = [_kong("tong5", "concealed", -1)]
			facts.round_meta = {"winners": [0], "discard_seat": 1, "win_tile": "wan9", "robbed_kong": kind == "rob"}
			facts.last_discard = {"after_kong": kind != "rob", "kong_kind": kind}
			score = Score.settle(facts)
			var base := 0.0 if kind in ["exposed", "rob"] else (17.0 if called else 21.0)
			var label := "点炮基础分（叫牌）" if called else "点炮基础分（未叫牌）"
			_check(_paid(score, 1, 0, label) == base, "only concealed/added-kong discard has separate called/uncalled fee")
			_check(_paid(score, 1, 0, "通行证胡牌") == (0.0 if kind == "rob" else 4.0), "passport fee stacks with discard fee but not rob-kong")
			_check(_paid(score, 1, 0, "抢杠胡基础分") == (12.0 if kind == "rob" else 0.0), "rob-kong fee separate from discard")
			_verify_ledger(score)

	facts = _facts(["w12345699 t234 b234", "w1234569 t234 b234", "", ""])
	facts.players[1].ready = true
	facts.round_meta = {"winners": [0], "self_draw": true, "win_tile": "wan9"}
	score = Score.settle(facts)
	_check(_paid(score, 1, 0, "杀报") == 24.0 and _paid(score, 1, 0, "大干扣") == 0.0
		and _paid(score, 2, 0, "大干扣") == 24.0, "big dry uses kill-ready only for the ready payer")
	_verify_ledger(score)
	facts.players[1].discards = ["tiao1"]
	facts.players[1].discard_ids = [19]
	score = Score.settle(facts)
	_check(_paid(score, 1, 0, "杀报") == 24.0 and _paid(score, 2, 0, "干扣") == 14.0, "another called player's chicken keeps the winner at dry14")
	_verify_ledger(score)

	facts.players[2].melds = [_kong("tong8", "exposed", 3)]
	score = Score.settle(facts)
	_check(score.items[2].size() == 1 and score.items[2][0].amount == -8.0
		and score.items[2][0].opponents == [0, 1], "uncalled exposed kong retains chicken debt but no base without a called source")
	_verify_ledger(score)

	facts = _facts(["w12345699 t234", "", "", ""])
	facts.players[0].melds = [_kong("tong5", "concealed", -1)]
	facts.round_meta = {"winners": [0], "self_draw": true, "win_tile": "wan9",
		"kong_draw_seat": 0, "last_four_self_draw_seat": 0, "chicken_multiplier": 2}
	score = Score.settle(facts)
	for payer in [1, 2, 3]:
		_check(_paid(score, payer, 0, "杠开") == 10.0 and _paid(score, payer, 0, "海底") == 10.0
			and score.pairwise[0][payer] == 36.0, "extra self draw fees stack and double once with base and kong")
	_verify_ledger(score)

func _pattern_fees() -> void:
	var cases := [
		["w11122299 t444 b333", [], "wan9", "大对子", 14.0],
		["w99", ["wan1", "wan2", "tong3", "tiao4"], "wan9", "大对子单吊", 24.0],
		["w112299 t5566 b3344", [], "wan9", "小七对", 24.0],
		["w111122 t5566 b3344", [], "wan1", "龙七对", 44.0],
		["w111122 t5566 b3344", [], "wan2", "小七对", 24.0],
		["w12345678923499", [], "wan9", "清一色", 24.0],
		["w11122233344499", [], "wan4", "清大对", 34.0],
		["w11223344556699", [], "wan9", "清七对", 44.0],
		["w99", ["wan1", "wan2", "wan4", "wan6"], "wan9", "清单吊", 54.0],
		["w11112233557799", [], "wan1", "清龙七对", 64.0],
	]
	for entry in cases:
		var facts := _facts([entry[0], "", "", ""])
		for tile in entry[1]:
			facts.players[0].melds.append({"kind": "pung", "tile": tile})
		facts.round_meta = {"winners": [0], "discard_seat": 3, "win_tile": entry[2]}
		var score := Score.settle(facts)
		var patterns: Array = score.items[0].filter(func(item): return item.kind == "pattern")
		_check(patterns.size() == 1 and _paid(score, 3, 0, entry[3]) == entry[4], "only the highest applicable pattern: %s" % entry[3])
		_check(score.deltas == [entry[4], 0.0, 0.0, -entry[4]], "pattern's only payer is the discard source")
		_verify_ledger(score)
