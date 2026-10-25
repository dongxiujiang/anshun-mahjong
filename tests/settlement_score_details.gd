extends SceneTree
## Independent recorded-result fixtures; no scoring engine or random rounds.
const DETAILS := preload("res://scripts/ui/table/SettlementScoreDetails.gd")
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _fixture() -> Dictionary:
	var players: Array = []
	for seat in 4:
		players.append({"seat": seat, "concealed": [], "just_drew": "", "melds": [], "discards": [], "discard_ids": []})
	return {"players": players, "meta": {"winner": 0, "winners": [0], "flip_tile": "wan5", "charge_chickens": {}},
		"result": {"items": [[], [], [], []], "transfers": [], "called": [true, true, true, true]}, "plan": {}}

func _build(f: Dictionary) -> Array:
	return DETAILS.build(f.result, f.meta, f.players, f.plan)

func _item(kind: String, label: String, tiles: Array, unit: float, source: String = "discard") -> Dictionary:
	return {"kind": kind, "label": label, "tiles": tiles, "tile": tiles[0], "amount": unit * tiles.size(), "unit_amount": unit, "source": source}

func _kong(tile: String, label: String, source: int, payers: Array, base: float = 4.0, chicken: float = 0.0, flip: float = 0.0, owner: int = 0) -> Dictionary:
	return {"kind": "kong", "label": label, "tile": tile, "tiles": [tile, tile, tile, tile], "owner": owner,
		"from_seat": source, "payers": payers, "chicken_payers": [], "base_amount": base,
		"chicken_amount": chicken, "flip_amount": flip, "amount": base + chicken + flip}

func _pay(f: Dictionary, payer: int, receiver: int, amount: float, reason: String) -> void:
	f.result.transfers.append({"from": payer, "to": receiver, "amount": amount, "reason": reason})

func _find(groups: Array, id: String) -> Dictionary:
	for group in groups:
		if group.id == id: return group
	t.expect(false, "missing group " + id)
	return {"stages": {}, "tiles": [], "detail": "", "area": ""}

func _amount(group: Dictionary, stage: String, expected: float, message: String) -> void:
	t.expect(group.stages.has(stage), message + " has stage")
	t.expect(is_equal_approx(float(group.stages.get(stage, {}).get("amount", INF)), expected), message + " amount")
	t.expect(group.stages.get(stage, {}).get("text", "") != "", message + " text")

func _test_grouped_sources() -> void:
	var f := _fixture()
	f.players[0].concealed = ["tiao1", "tong8", "tong8", "wan4", "wan5", "wan6"]
	f.players[0].just_drew = "tong8"
	f.players[0].discards = ["tiao1"]
	f.players[0].discard_ids = [7]
	f.players[0].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 3}]
	# The retained source deliberately says discard for a mixed-source item.
	f.result.items[0] = [_item("chicken", "普通鸡", ["tiao1", "tiao1", "tiao1", "tiao1", "tiao1", "tong8", "tong8"], 2),
		_item("flip", "翻鸡", ["wan4", "wan5", "wan6"], 1)]
	var before := var_to_bytes(f)
	var groups := _build(f)
	_amount(_find(groups, "0:hand_chicken"), "chicken", 4, "hand excludes drawn duplicate")
	_amount(_find(groups, "0:draw"), "chicken", 2, "draw independently consumes one unit")
	_amount(_find(groups, "0:chicken_tiao1"), "chicken", 2, "discard receives one recorded unit")
	_amount(_find(groups, "0:meld_0"), "chicken", 6, "pung receives three recorded units")
	_amount(_find(groups, "0:hand_flip"), "flip", 3, "hand flip tiles grouped")
	t.expect(_find(groups, "0:hand_flip").stages.flip.text == "翻鸡3分", "short flip caption")
	t.expect(_find(groups, "0:hand_flip").detail == "翻鸡3分", "click uses the same compact caption")
	t.expect(var_to_bytes(f) == before, "build leaves all nested inputs unchanged")
	t.expect(groups == _build(f), "deterministic details")
	groups[0].tiles.clear()
	groups[0].stages.clear()
	t.expect(var_to_bytes(f) == before, "output owns arrays and dictionaries")

func _test_gold_charge_and_multiplier() -> void:
	var f := _fixture()
	f.meta.flip_tile = "tiao1"
	f.meta.chicken_multiplier = 2
	f.players[0].discards = ["tiao1", "tiao1"]
	f.players[0].discard_ids = [3, 9]
	f.meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 3}}
	# Values are already settled. Even with multiplier=2, never multiply again.
	f.result.items[0] = [_item("charge", "冲锋金鸡", ["tiao1"], 8), _item("chicken", "金鸡", ["tiao1"], 4)]
	var group := _find(_build(f), "0:chicken_tiao1")
	_amount(group, "flip", 12, "gold charge plus ordinary")
	t.expect(group.stages.flip.text == "冲锋幺鸡8分 幺鸡4分", "gold composition short caption")
	t.expect(group.detail == "冲锋幺鸡8分 幺鸡4分", "click details include the same addition total")
	t.expect(not group.stages.has("chicken"), "gold never counts twice")
	t.expect(group.detail.contains("冲锋幺鸡8分") and group.detail.contains("幺鸡4分"), "charge and ordinary details")
	# Already doubled ordinary charge/ordinary items have different recorded units.
	f.meta.flip_tile = "wan5"
	f.result.items[0] = [_item("charge", "冲锋鸡", ["tiao1"], 8), _item("chicken", "普通鸡", ["tiao1"], 4)]
	_amount(_find(_build(f), "0:chicken_tiao1"), "chicken", 12, "round multiplier already reflected")

func _test_exposed_kong() -> void:
	var f := _fixture()
	f.players[1].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 3}]
	f.result.items[1] = [_kong("tiao1", "明杠", 3, [3], 4, 8, 0, 1)]
	_pay(f, 3, 1, 4, "明杠")
	var group := _find(_build(f), "1:meld_0")
	_amount(group, "other", 4, "win round exposed base remains other")
	_amount(group, "chicken", 8, "kong chicken contribution separate from base")
	t.expect(group.detail.contains("杠对家幺鸡4分") and group.detail.contains("幺鸡8分")
		and not group.detail.contains("12分"), "called exposed chicken kong never aggregates base+chicken into 12")
	t.expect(not group.stages.has("kong"), "exposed base not moved to own-kong phase")
	t.expect(group.detail.contains("杠对家幺鸡4分"), "payer relative to owner seat1, not human/dealer")
	t.expect(group.tiles.size() == 4, "whole kong node group")
	var plain := _fixture()
	plain.players[1].melds = [{"kind": "kong", "tile": "wan2", "from_seat": 3}]
	plain.result.items[1] = [_kong("wan2", "明杠", 3, [3], 4, 0, 0, 1)]
	_pay(plain, 3, 1, 4, "明杠")
	var plain_group := _find(_build(plain), "1:meld_0")
	t.expect(plain_group.detail == "杠对家2万4分", "plain exposed kong uses tile, direction and per-payer unit")
	# The same from_seat on an added kong is NOT its sole base payer.
	f.players[1].melds[0].kind = "add_kong"
	f.result.items[1] = [_kong("tiao1", "加杠", 3, [0, 2, 3], 8, 16, 0, 1)]
	f.result.transfers = []
	for payer in [0, 2, 3]: _pay(f, payer, 1, 8, "加杠")
	group = _find(_build(f), "1:meld_0")
	_amount(group, "kong", 24, "added kong uses actual three payments")
	t.expect(group.stages.kong.text == "杠幺鸡8分", "added kong payer count and scaled unit")

func _test_multiple_same_kongs() -> void:
	var f := _fixture()
	for tile in ["wan1", "wan2"]:
		f.players[0].melds.append({"kind": "kong", "tile": tile, "concealed": true})
		f.result.items[0].append(_kong(tile, "暗杠", -1, [1, 2, 3]))
		for payer in [1, 2, 3]: _pay(f, payer, 0, 4, "暗杠")
	var groups := _build(f)
	for index in 2:
		var group := _find(groups, "0:meld_%d" % index)
		_amount(group, "kong", 12, "complete same-rate rows match meld order")
		t.expect(group.stages.kong.text == ("杠1万4分" if index == 0 else "杠2万4分"), "three real payers")
	# Truncated/aggregated row count is not enough to allocate payer1's money.
	f.result.transfers.remove_at(3)
	groups = _build(f)
	for index in 2:
		var group := _find(groups, "0:meld_%d" % index)
		_amount(group, "kong", 8, "only complete payer2/3 partitions remain")
		t.expect(group.detail.contains("该家合计向下家收4分"), "ambiguous payer money is explicitly family total")

func _test_draw() -> void:
	var f := _fixture()
	f.meta.winner = -1
	f.meta.winners = []
	f.result.called = [true, true, false, false]
	f.players[0].concealed = ["tiao1", "wan5"]
	f.players[0].just_drew = "wan5"
	f.players[0].discards = ["tong8"]
	f.players[0].melds = [{"kind": "kong", "tile": "tiao1", "concealed": true}]
	var kong := _kong("tiao1", "暗杠", -1, [2, 3], 4, 8)
	kong.chicken_payers = [2, 3]
	f.result.items[0] = [_item("chicken", "普通鸡", ["tong8"], 2), kong]
	for payer in [2, 3]:
		_pay(f, payer, 0, 4, "查叫暗杠")
		_pay(f, payer, 0, 8, "杠中鸡")
		_pay(f, payer, 0, 6, "荒牌包鸡")
	var groups := _build(f)
	t.expect(groups.all(func(group): return group.area not in ["hand", "draw"]), "draw does not expose hidden hands/draw")
	t.expect(groups.all(func(group): return not group.stages.has("flip") and not group.stages.has("chicken")), "draw details use only existing phases")
	_amount(_find(groups, "0:meld_0"), "kong", 24, "draw kong includes base and actual chicken payments")
	var discard := _find(groups, "0:chicken_tong8")
	_amount(discard, "other", 2, "draw discarded chicken composition goes other")
	t.expect(not discard.detail.contains("向下家收"), "called seat1 never invented as payer")
	f.result.called = [true, true, true, true]
	t.expect(_build(f).is_empty(), "four-called draw returns no details")

func _test_uncalled_debts() -> void:
	var f := _fixture()
	f.result.called = [true, false, true, false]
	f.players[1].concealed = ["tiao1"]
	f.players[1].discards = ["tong8"]
	f.players[1].melds = [{"kind": "kong", "tile": "tiao1", "from_seat": 3}]
	# No positive uncalled items exist; only settled transfers supply debt amounts.
	for receiver in [0, 2]:
		_pay(f, 1, receiver, 2, "未叫牌出牌鸡")
		_pay(f, 1, receiver, 4, "未叫牌杠分")
		_pay(f, 1, receiver, 8, "未叫牌杠中鸡")
	var groups := _build(f)
	t.expect(_find(groups, "1:hand_chicken").stages.is_empty(), "uncalled concealed chicken has no income")
	_amount(_find(groups, "1:chicken_tong8"), "chicken", -4, "one visible discarded type owns recorded debt")
	_amount(_find(groups, "1:meld_0"), "other", -8, "uncalled exposed base debt stage")
	_amount(_find(groups, "1:meld_0"), "chicken", -16, "uncalled kong chicken debt")
	f.players[1].discards.append("tiao1")
	f.players[1].melds.append({"kind": "kong", "tile": "tong8", "concealed": true})
	groups = _build(f)
	for id in ["1:chicken_tong8", "1:chicken_tiao1", "1:meld_0", "1:meld_1"]:
		var group := _find(groups, id)
		t.expect(group.stages.is_empty(), "ambiguous debt not divided by tile count " + id)
		t.expect(group.detail.contains("该家合计向上家付"), "ambiguous group retains real family payment " + id)

func _test_short_chicken_labels() -> void:
	var f := _fixture()
	f.players[0].discards = ["tong8"]
	f.players[0].discard_ids = [0]
	f.meta.charge_chickens = {"tong8": {"owner": 0, "location": "discard", "discard_id": 0}}
	f.result.items[0] = [_item("charge", "冲锋鸡", ["tong8"], 4)]
	t.expect(_find(_build(f), "0:chicken_tong8").detail == "冲锋八筒4分", "called charge chicken shows 冲锋八筒4分")
	var ordinary := _fixture()
	ordinary.players[0].discards = ["tong8"]
	ordinary.players[0].discard_ids = [0]
	ordinary.result.items[0] = [_item("chicken", "普通鸡", ["tong8"], 2)]
	t.expect(_find(_build(ordinary), "0:chicken_tong8").detail == "八筒2分", "called ordinary chicken shows 八筒2分")

func _test_uncalled_charge_short_label() -> void:
	var f := _fixture()
	f.result.called = [true, false, true, true]
	f.players[1].discards = ["tong8"]
	f.players[1].discard_ids = [0]
	f.meta.charge_chickens = {"tong8": {"owner": 1, "location": "discard", "discard_id": 0}}
	for receiver in [0, 2, 3]:
		_pay(f, 1, receiver, 4, "未叫牌出牌鸡")
	var group := _find(_build(f), "1:chicken_tong8")
	t.expect(group.stages.has("chicken"), "uncalled charge chicken has a visible stage")
	t.expect(group.stages.chicken.text == "冲锋八筒-4分", "uncalled charge chicken shows one short tile line")
	t.expect(group.detail == "冲锋八筒-4分", "click uses the same short tile line")
	t.expect(is_equal_approx(float(group.stages.chicken.amount), -12.0), "short label keeps the real 12-point ledger total")

func _test_uncalled_two_same_chickens() -> void:
	var f := _fixture()
	f.result.called = [true, false, true, true]
	f.players[1].discards = ["tiao1", "tiao1"]
	f.players[1].discard_ids = [0, 1]
	f.meta.charge_chickens = {"tiao1": {"owner": 1, "location": "discard", "discard_id": 0}}
	for receiver in [0, 2, 3]:
		_pay(f, 1, receiver, 6, "未叫牌出牌鸡")
	var group := _find(_build(f), "1:chicken_tiao1")
	t.expect(group.stages.chicken.text == "冲锋幺鸡-4分 幺鸡-2分", "uncalled charge+ordinary discard keeps both per-payer tile lines")
	t.expect(group.detail == "冲锋幺鸡-4分 幺鸡-2分", "click keeps the same two per-payer tile lines")
	t.expect(is_equal_approx(float(group.stages.chicken.amount), -18.0), "two tile lines still keep the real ledger total")
	f.players[1].discards.append("tiao1")
	f.players[1].discard_ids.append(2)
	f.result.transfers.clear()
	for receiver in [0, 2, 3]: _pay(f, 1, receiver, 8, "未叫牌出牌鸡")
	group = _find(_build(f), "1:chicken_tiao1")
	t.expect(group.detail == "冲锋幺鸡-4分 幺鸡-4分", "multiple ordinary copies keep the combined ordinary debt caption")
	_amount(group, "chicken", -24, "three discarded copies retain the full recorded debt")

func _test_uncalled_ordinary_chickens() -> void:
	for tile in ["tiao1", "tong8"]:
		var f := _fixture()
		f.result.called = [true, false, true, true]
		f.players[1].discards = [tile, tile]
		f.players[1].discard_ids = [0, 1]
		for receiver in [0, 2, 3]:
			_pay(f, 1, receiver, 4, "未叫牌出牌鸡")
		var group := _find(_build(f), "1:chicken_" + tile)
		var expected := "幺鸡-4分" if tile == "tiao1" else "八筒-4分"
		t.expect(group.stages.chicken.text == expected, "two ordinary same chickens show the per-called-player total")
		t.expect(is_equal_approx(float(group.stages.chicken.amount), -12.0), "two ordinary chicken debt keeps the real total")
	var mixed := _fixture()
	mixed.result.called = [true, false, true, true]
	mixed.players[1].discards = ["tiao1", "tong8"]
	mixed.players[1].discard_ids = [0, 1]
	for receiver in [0, 2, 3]:
		_pay(mixed, 1, receiver, 4, "未叫牌出牌鸡")
	t.expect(_find(_build(mixed), "1:chicken_tiao1").stages.chicken.text == "幺鸡-2分",
		"mixed ordinary chickens keep separate tiao1 line")
	t.expect(_find(_build(mixed), "1:chicken_tong8").stages.chicken.text == "八筒-2分",
		"mixed ordinary chickens keep separate tong8 line")

func _test_uncalled_pong_chicken() -> void:
	var f := _fixture()
	f.result.called = [true, false, true, false]
	f.players[1].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 0}]
	f.result.items[1] = [{"kind": "penalty", "label": "未叫牌碰鸡", "tile": "", "tiles": [], "amount": -6.0}]
	_pay(f, 1, 0, 6.0, "未叫牌碰鸡")
	_pay(f, 1, 2, 6.0, "未叫牌碰鸡")
	var group := _find(_build(f), "1:meld_0")
	_amount(group, "chicken", -12.0, "uncalled pong chicken keeps the real two-payer total")
	t.expect(group.stages.chicken.text == "碰幺鸡-6分" and group.detail == group.stages.chicken.text,
		"uncalled pong chicken shows one per-called-player debt line")

func _test_uncalled_kong_captions() -> void:
	var f := _fixture()
	f.result.called = [true, false, true, true]
	f.players[1].melds = [{"kind": "kong", "tile": "wan2", "concealed": true}]
	for receiver in [0, 2, 3]:
		_pay(f, 1, receiver, 4, "未叫牌杠分")
	var group := _find(_build(f), "1:meld_0")
	t.expect(group.stages.kong.text == "杠2万-4分" and group.detail == group.stages.kong.text, "uncalled own kong shows one negative tile line")
	t.expect(is_equal_approx(float(group.stages.kong.amount), -12.0), "negative kong short line keeps the real three-payer total")
	var exposed := _fixture()
	exposed.result.called = [true, false, true, true]
	exposed.players[1].melds = [{"kind": "kong", "tile": "wan2", "from_seat": 0}]
	_pay(exposed, 1, 0, 4, "未叫牌杠分")
	group = _find(_build(exposed), "1:meld_0")
	t.expect(group.stages.other.text == "杠上家2万-4分" and group.detail == group.stages.other.text, "uncalled exposed kong shows payer-relative direction")

func _test_burn_robbed_and_normal_pung() -> void:
	var f := _fixture()
	f.meta.burn_chicken_seat = 1
	f.players[1].concealed = ["tiao1"]
	f.players[1].melds = [{"kind": "kong", "tile": "tiao1", "concealed": true, "robbed": true}]
	f.result.items[1] = [_item("chicken", "普通鸡", ["tiao1"], 2), _kong("tiao1", "暗杠", -1, [0, 2, 3], 4, 8, 0, 1)]
	var groups := _build(f)
	for group in groups:
		t.expect(group.stages.is_empty(), "burned seat never gets positive presentation income")
		t.expect(group.detail == ("被抢杠0分" if group.id == "1:meld_0" else "烧鸡0分"), "burn and robbed captions stay compact")
	f.meta.erase("burn_chicken_seat")
	for payer in [0, 2, 3]: _pay(f, payer, 1, 4, "暗杠")
	t.expect(_find(_build(f), "1:meld_0").stages.is_empty(), "robbed kong never displays base even with stale item")
	f.players[0].melds = [{"kind": "pung", "tile": "wan9", "from_seat": 2}]
	t.expect(_find(_build(f), "0:meld_0").detail == "", "ordinary nonchicken pung has no detail text")
	# A robbed added kong is retained as its original pung in real results.
	f.meta.robbed_kong = true
	f.meta.discard_seat = 1
	f.meta.win_tile = "tiao1"
	f.meta.burn_chicken_seat = 1
	f.players[1].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 0}]
	t.expect(_find(_build(f), "1:meld_0").detail == "被抢杠0分", "robbed added kong is recognized from round metadata on the retained pung")
	# A burned uncalled player still pays recorded discarded-chicken debt.
	f.meta.burn_chicken_seat = 1
	f.result.called[1] = false
	f.players[1].discards = ["tong8"]
	_pay(f, 1, 0, 6, "未叫牌出牌鸡")
	_amount(_find(_build(f), "1:chicken_tong8"), "chicken", -6, "burn does not erase outflow")

func _test_resolved_and_multiwinner_snapshot() -> void:
	var f := _fixture()
	f.meta.winners = [0, 2]
	f.meta.win_tile = "tiao1"
	f.meta.resolved_chicken_discards = [{"owner": 1, "tile": "tiao1", "charge": false, "discard_id": 9}]
	f.players[1].discards = ["tiao1"]
	for seat in [0, 2]:
		f.players[seat].concealed = ["tiao1", "tiao1"]
		f.result.items[seat] = [_item("chicken", "普通鸡", ["tiao1", "tiao1"], 2)]
	f.result.items[1] = [_item("chicken", "普通鸡", ["tiao1", "tiao1"], 2)]
	f.result.players = f.players.duplicate(true)
	for player in f.result.players:
		player.erase("just_drew")
		player.erase("discard_ids")
	f.result.round_meta = f.meta.duplicate(true)
	var groups := _build(f)
	for seat in [0, 2]:
		_amount(_find(groups, "%d:draw" % seat), "chicken", 2, "each winning snapshot owns one logical win tile")
		_amount(_find(groups, "%d:hand_chicken" % seat), "chicken", 2, "winning duplicates remain in hand")
	_amount(_find(groups, "1:chicken_tiao1"), "chicken", 2, "resolved invisible occurrence does not inflate visible group")
	t.expect(_find(groups, "1:chicken_tiao1").tiles.size() == 1, "resolved discard never recreates original owner node")
	f.result.called[1] = false
	_pay(f, 1, 0, 4, "未叫牌出牌鸡")
	var group := _find(_build(f), "1:chicken_tiao1")
	t.expect(group.stages.is_empty(), "resolved plus visible debt not forced onto visible tile")
	t.expect(group.detail.contains("已被胡走"), "resolved debt limit clearly stated")

func _test_missing_data() -> void:
	var f := _fixture()
	f.players[0].concealed = ["tiao1"]
	f.result.items[0] = [_item("chicken", "普通鸡", ["tiao1", "tiao1"], 2)]
	var group := _find(_build(f), "0:hand_chicken")
	t.expect(group.stages.is_empty(), "missing source occurrence cannot inflate visible score")
	t.expect(group.detail.contains("该家普通鸡合计4分"), "aggregate amount remains inspectable")
	f.result.items[0][0].tiles = ["tiao1"]
	f.result.items[0][0].amount = 7
	group = _find(_build(f), "0:hand_chicken")
	t.expect(group.stages.is_empty(), "inconsistent unit amount is not silently repaired")
	for forbidden in ["来源不足", "快照", "未拆分到本组", "单张金额不足", "项目"]:
		t.expect(not group.detail.contains(forbidden), "player-facing detail avoids " + forbidden)
	# Snapshot draw values must not be borrowed from a different hand revision.
	f.result.items[0] = [_item("chicken", "普通鸡", ["tiao1"], 2)]
	f.result.players = f.players.duplicate(true)
	f.result.players[0].erase("just_drew")
	f.players[0].concealed = ["tong8"]
	f.players[0].just_drew = "tong8"
	t.expect(not _build(f).any(func(candidate): return candidate.area == "draw"), "stale live hand cannot supply snapshot draw identity")

func _test_debug_fallbacks_hidden() -> void:
	var f := _fixture()
	f.result.called = [true, false, true, true]
	f.players[1].discards = ["tiao1", "tong8"]
	f.players[1].discard_ids = [0, 1]
	for receiver in [0, 2, 3]: _pay(f, 1, receiver, 2, "未叫牌出牌鸡")
	DETAILS.set_debug_enabled(false)
	var hidden_group := _find(_build(f), "1:chicken_tiao1")
	t.expect(not hidden_group.detail.contains("本组暂无"), "debug off hides technical fallback lines")
	DETAILS.set_debug_enabled(true)
	var shown_group := _find(_build(f), "1:chicken_tiao1")
	t.expect(shown_group.detail.contains("本组暂无独立收付明细"), "debug on exposes attribution diagnostics")

func _test_requested_captions() -> void:
	for tile in ["tong8", "tiao1"]:
		var name := "八筒" if tile == "tong8" else "幺鸡"
		var f := _fixture()
		f.players[0].concealed = [tile, tile]
		f.result.items[0] = [_item("chicken", "普通鸡", [tile, tile], 2)]
		var group := _find(_build(f), "0:hand_chicken")
		t.expect(group.stages.chicken.text == name + "4分" and group.detail == name + "4分", "two ordinary chickens use the requested short label")
		f.players[0].concealed = []
		f.players[0].melds = [{"kind": "pung", "tile": tile, "from_seat": 2}]
		f.result.items[0] = [_item("chicken", "普通鸡", [tile, tile, tile], 2)]
		group = _find(_build(f), "0:meld_0")
		t.expect(group.stages.chicken.text == "碰" + name + "6分" and group.detail == "碰" + name + "6分", "chicken pung reports one group total with 碰")
		f.players[0].melds = []
		f.players[0].discards = [tile, tile]
		f.players[0].discard_ids = [1, 2]
		f.meta.charge_chickens = {tile: {"owner": 0, "location": "discard", "discard_id": 1}}
		f.result.items[0] = [_item("charge", "冲锋鸡", [tile], 4), _item("chicken", "普通鸡", [tile], 2)]
		group = _find(_build(f), "0:chicken_" + tile)
		t.expect(group.detail == "冲锋%s4分 %s2分" % [name, name], "charge and ordinary chickens are separately named")
	for count in [2, 4]:
		var f := _fixture()
		for index in count: f.players[0].concealed.append("wan5")
		f.result.items[0] = [_item("flip", "翻鸡", f.players[0].concealed, 1)]
		var group := _find(_build(f), "0:hand_flip")
		t.expect(group.detail == "翻鸡%d分" % count and group.stages.flip.text == group.detail, "flip group uses its exact recorded total")
	for owner in 4:
		for offset in [1, 2, 3]:
			var payer: int = (owner + offset) % 4
			var f := _fixture()
			f.players[owner].melds = [{"kind": "kong", "tile": "wan2", "from_seat": payer}]
			f.result.items[owner] = [_kong("wan2", "明杠", payer, [payer], 4, 0, 0, owner)]
			_pay(f, payer, owner, 4, "明杠")
			var group := _find(_build(f), "%d:meld_0" % owner)
			t.expect(group.detail == "杠%s2万4分" % ["", "下家", "对家", "上家"][offset], "exposed kong direction is relative to owner in all seats")
	for kind in ["kong", "add_kong"]:
		var label := "暗杠" if kind == "kong" else "加杠"
		var f := _fixture()
		f.players[0].melds = [{"kind": kind, "tile": "wan2", "concealed": kind == "kong"}]
		f.result.items[0] = [_kong("wan2", label, -1, [1, 2, 3])]
		for payer in [1, 2, 3]: _pay(f, payer, 0, 4, label)
		var group := _find(_build(f), "0:meld_0")
		t.expect(group.detail == "杠2万4分" and group.stages.kong.text == group.detail, "kong caption reports per-payer base without formula")
		t.expect(group.stages.kong.amount == 12.0, "short kong caption never changes the real three-payer income")

func _test_kong_chicken_captions() -> void:
	for tile in ["tiao1", "tong8"]:
		var name := "幺鸡" if tile == "tiao1" else "八筒"
		for is_draw in [false, true]:
			for gold in [false, true]:
				var f := _fixture()
				f.result.called = [true, false, true, true]
				f.meta.flip_tile = tile if gold else "wan5"
				if is_draw:
					f.meta.winner = -1
					f.meta.winners = []
				f.players[1].melds = [{"kind": "kong", "tile": tile, "from_seat": 0}]
				var unit := 16.0 if gold and not is_draw else 8.0
				for receiver in [0, 2, 3]: _pay(f, 1, receiver, unit, "未叫牌杠中鸡")
				var before := var_to_bytes(f)
				var group := _find(_build(f), "1:meld_0")
				var stage := "kong" if is_draw else ("flip" if gold else "chicken")
				_amount(group, stage, -unit * 3.0, "uncalled chicken kong keeps all real payments")
				t.expect(group.detail == name + str(int(-unit)) + "分", "uncalled/draw chicken kong uses tile and one negative rate")
				t.expect(var_to_bytes(f) == before, "short chicken kong captions never change the settlement")
		for multiplier in [1, 2]:
			var f := _fixture()
			f.meta.winner = -1
			f.meta.winners = []
			f.meta.chicken_multiplier = multiplier
			f.result.called = [true, true, false, false]
			f.players[0].melds = [{"kind": "kong", "tile": tile, "from_seat": 1}]
			var item := _kong(tile, "明杠", 1, [], 0, 8 * multiplier)
			item.chicken_payers = [2, 3]
			f.result.items[0] = [item]
			for payer in [2, 3]: _pay(f, payer, 0, 8 * multiplier, "杠中鸡")
			var group := _find(_build(f), "0:meld_0")
			_amount(group, "kong", 16 * multiplier, "called draw chicken kong retains the two payments")
			t.expect(group.detail == name + str(8 * multiplier) + "分", "called draw chicken kong shows one tile rate without flow text")

func _test_multiple_kong_debts() -> void:
	for is_draw in [false, true]:
		for multiplier in [1, 2]:
			var f := _fixture()
			f.result.called = [true, false, true, true]
			f.meta.chicken_multiplier = multiplier
			f.meta.flip_tile = "tiao1"
			if is_draw:
				f.meta.winner = -1
				f.meta.winners = []
			for tile in ["tiao1", "tong8"]:
				f.players[1].melds.append({"kind": "kong", "tile": tile, "from_seat": 0})
				var chicken := 16 if tile == "tiao1" and not is_draw else 8
				for receiver in [0, 2, 3]:
					_pay(f, 1, receiver, 4 * multiplier, "未叫牌杠分")
					_pay(f, 1, receiver, chicken * multiplier, "未叫牌杠中鸡")
			for index in 2:
				var name := "幺鸡" if index == 0 else "八筒"
				var unit: int = (16 if index == 0 and not is_draw else 8) * multiplier
				var group := _find(_build(f), "1:meld_%d" % index)
				var chicken_stage := "kong" if is_draw else ("flip" if index == 0 else "chicken")
				if not is_draw: _amount(group, chicken_stage, -unit * 3.0, "each kong gets only its recorded chicken debt")
				t.expect(group.detail.contains(name + str(-unit) + "分"), "multiple chicken kongs keep separate short tile debts")
				t.expect(group.detail.contains("杠上家" + name + str(-4 * multiplier) + "分"), "exposed debt direction follows the source, across all receivers")
				t.expect(not group.detail.contains("向") and not group.detail.contains("本组暂无"), "complete multiple kong debts need no flow or fallback")

func _test_draw_chicken_debts() -> void:
	for is_draw in [false, true]:
		for multiplier in [1, 2]:
			var f := _fixture()
			f.meta.chicken_multiplier = multiplier
			f.result.called = [true, false, true, true]
			f.players[1].discards = ["tiao1", "tong8"]
			f.players[1].discard_ids = [0, 1]
			f.players[1].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": 0}]
			f.result.items[1] = [{"kind": "penalty", "label": "未叫牌出牌鸡", "amount": -4.0 * multiplier},
				{"kind": "penalty", "label": "未叫牌碰鸡", "amount": -6.0 * multiplier}]
			if is_draw:
				f.meta.winner = -1
				f.meta.winners = []
			for receiver in [0, 2, 3]:
				if is_draw:
					# Includes the owner's 4 discard points, 6 pung points,
					# receiver's 2 discard points and the 4-point draw fee.
					_pay(f, 1, receiver, 16 * multiplier, "荒牌包鸡")
				else:
					_pay(f, 1, receiver, 4 * multiplier, "未叫牌出牌鸡")
					_pay(f, 1, receiver, 6 * multiplier, "未叫牌碰鸡")
			var before := var_to_bytes(f)
			var groups := _build(f)
			for tile in ["tiao1", "tong8"]:
				var group := _find(groups, "1:chicken_" + tile)
				var name := "幺鸡" if tile == "tiao1" else "八筒"
				t.expect(group.detail == name + str(-2 * multiplier) + "分", "discard debt and draw package show only the owner's short tile debt")
				_amount(group, "other" if is_draw else "chicken", -6 * multiplier, "tile debt keeps its three actual payments")
			var pung := _find(groups, "1:meld_0")
			t.expect(pung.detail == "碰幺鸡" + str(-6 * multiplier) + "分", "draw package pung follows the same short debt caption")
			t.expect(var_to_bytes(f) == before, "draw component display never changes package ledger amounts")

func _run() -> void:
	DETAILS.set_debug_enabled(true)
	_test_grouped_sources()
	_test_gold_charge_and_multiplier()
	_test_exposed_kong()
	_test_multiple_same_kongs()
	_test_draw()
	_test_uncalled_debts()
	_test_short_chicken_labels()
	_test_uncalled_charge_short_label()
	_test_uncalled_two_same_chickens()
	_test_uncalled_ordinary_chickens()
	_test_uncalled_pong_chicken()
	_test_uncalled_kong_captions()
	_test_burn_robbed_and_normal_pung()
	_test_resolved_and_multiwinner_snapshot()
	_test_missing_data()
	_test_debug_fallbacks_hidden()
	_test_requested_captions()
	_test_kong_chicken_captions()
	_test_multiple_kong_debts()
	_test_draw_chicken_debts()
	DETAILS.set_debug_enabled(false)
	quit(t.finish("settlement_score_details"))

