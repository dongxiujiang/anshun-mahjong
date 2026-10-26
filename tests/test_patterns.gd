extends SceneTree
## 联机测试牌型只发指定座位，且不能破坏牌张总数。

const H := preload("res://tests/test_harness.gd")
const PATTERNS := preload("res://scripts/core/TestPatterns.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for entry in PATTERNS.CATALOG:
		var hand := PATTERNS.hand(str(entry.id))
		t.expect(hand.size() == 13, "%s 必须发 13 张" % entry.name)
		t.expect(hand.all(func(card): return Tiles.all_values().has(card)), "%s 只包含合法牌" % entry.name)
		var counts := {}
		for card in hand: counts[card] = int(counts.get(card, 0)) + 1
		t.expect(counts.values().all(func(count): return count <= 4), "%s 单张不能超过 4 张" % entry.name)

	var round := RoundState.new()
	round.set_rng_seed(20261026)
	round.test_hand_seat = 1
	round.test_hand = PATTERNS.hand("ready")
	round.build_players(0)
	round.start_round(0, 3)
	t.expect(round.players[1].concealed == PATTERNS.hand("ready"), "指定座位拿到测试牌")
	t.expect(round.players[0].concealed.size() in [13, 14], "其他座位仍是正常发牌张数")
	t.expect(round.test_hand.is_empty() and round.test_hand_seat == -1, "测试手牌只用一局")
	var total := 0
	for player in round.players: total += player.concealed.size()
	for seat in 4: total += round.wall.wall_remaining(seat)
	t.expect(total == 108, "测试发牌后牌张总数仍为 108")
	if t.failures == 0:
		print("[test_patterns] passed")
	await H.quit_cleanly(self, 0 if t.failures == 0 else 1)

