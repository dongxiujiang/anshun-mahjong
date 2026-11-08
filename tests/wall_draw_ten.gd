extends SceneTree
## 10局真实 AI 对局：独立核验发牌、牌头、普通摸牌、杠后补牌和翻鸡。
## 参考模型：poker 两行54列，北14/东13/南14/西13，列优先。
const H := preload("res://tests/test_harness.gd")
const ROUNDS := 10

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var t := H.new()
	for game in ROUNDS:
		var dealer := game % 4
		var die := game % 6 + 1
		var r := RoundState.new()
		r.set_rng_seed(4000 + game)
		r.next_dealer_seat = dealer
		r.opening_delay_seconds = 0.0
		var ai := []
		for seat in 4:
			ai.append(AiPlayer.new("AI%d" % seat))
		r.controllers = ai
		var batches: Array = []
		r.dealt.connect(func(info): batches.append_array(info.batches))
		r.start_round(0, die)
		if not t.expect(r.phase == RoundState.Phase.SETTLED, "第%d局应结算" % game):
			continue
		_check_layout(t, r, game)
		_check_deal(t, r, batches, dealer, game)
		_check_draw_log(t, r, game)
		_check_flip(t, r, game)
		print("[wall10] game=%d dealer=%d die=%d draws=%d tail=%d flip=%s remaining=%d" % [
			game, dealer, die, r.wall.draw_log.size(), _tail_count(r.wall), str(r.round_meta.flip_tile), r.wall.remaining])
	quit(t.finish("wall_draw_ten"))

func _check_layout(t, r: RoundState, game: int) -> void:
	var sizes := {3: 14, 0: 13, 1: 14, 2: 13}
	for seat in 4:
		t.expect(r.wall.wall_stack_counts(seat).size() == sizes[seat], "第%d局座%d墙列数" % [game, seat])
	t.expect(r.wall.draw_log.size() == 108 - r.wall.remaining, "第%d局取牌日志与剩余一致" % game)

func _check_deal(t, r: RoundState, batches: Array, dealer: int, game: int) -> void:
	t.expect(batches.size() == 7, "第%d局发牌批次为3轮+最后4家" % game)
	for round_index in 3:
		var group: Array = batches[round_index]
		for offset in 4:
			var batch: Dictionary = group[offset]
			var expected_seat := posmod(dealer + GameConfig.TURN_DIRECTION * offset, 4)
			t.expect(int(batch.seat) == expected_seat, "第%d局轮%d第%d家逆时针发牌" % [game, round_index, offset])
			t.expect(batch.cards.size() == 4, "第%d局发牌两蹲四张" % game)
	for offset in 4:
		var group: Array = batches[3 + offset]
		var batch: Dictionary = group[0]
		var expected_seat := posmod(dealer + GameConfig.TURN_DIRECTION * offset, 4)
		t.expect(int(batch.seat) == expected_seat and batch.cards.size() == 1, "第%d局最后单张按顺序" % game)
	var break_index := WallRing.compute_break(int(r.round_meta.die), dealer)
	for index in 52:
		t.expect(int(r.wall.draw_log[index].index) == posmod(break_index + index, 108), "第%d局发牌从破墙点连续取52张" % game)

func _check_draw_log(t, r: RoundState, game: int) -> void:
	var break_index := WallRing.compute_break(int(r.round_meta.die), int(r.round_meta.dealer_seat))
	var removed := []
	removed.resize(108)
	removed.fill(false)
	var head := break_index
	for index in r.wall.draw_log.size():
		var entry: Dictionary = r.wall.draw_log[index]
		var actual := int(entry.index)
		var is_tail := bool(entry.tail)
		var expected := -1
		if is_tail:
			expected = _last_undrawn(removed)
		else:
			while removed[head]:
				head = (head + 1) % 108
			expected = head
			head = (head + 1) % 108
		t.expect(actual == expected, "第%d局第%d次%s取牌位置" % [game, index, "杠尾" if is_tail else "牌头"])
		removed[actual] = true
	t.expect(r.wall.remaining == 108 - r.wall.draw_log.size(), "第%d局剩余张数与取牌数一致" % game)

func _last_undrawn(removed: Array) -> int:
	for col in range(53, -1, -1):
		for row in 2:
			var index := col * 2 + row
			if not removed[index]:
				return index
	return -1

func _tail_count(wall) -> int:
	var n := 0
	for entry in wall.draw_log:
		if bool(entry.tail):
			n += 1
	return n

func _check_flip(t, r: RoundState, game: int) -> void:
	var expected := r.wall.peek_head() if int(r.round_meta.winner) >= 0 else ""
	t.expect(str(r.round_meta.flip_tile) == str(expected), "第%d局翻鸡为牌头下一张且不消耗" % game)
