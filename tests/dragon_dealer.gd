extends SceneTree
## 龙七对计分、结算选庄、换庄发牌/牌墙和联机保留分数。
const H := preload("res://tests/test_harness.gd")
const DRAGON := ["tiao1", "tiao1", "tiao1", "tiao1", "wan2", "wan2", "wan5", "wan5", "tong3", "tong3", "tong6", "tong6", "tiao9", "tiao9"]
const CALLED := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tiao5"]
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_dragon()
	_test_next_dealer()
	_test_deal()
	_test_network_round()
	await _test_score_ui()
	quit(t.finish("dragon_dealer"))

func _fixture(dealer: int = 0) -> RoundState:
	var game := RoundState.new()
	game.dealer_seat = dealer
	game.next_dealer_seat = dealer
	game._reset_meta()
	game.build_players(0)
	game.controllers = [null, null, null, null]
	game.wall = WallRing.new(TileSetFactory.create_deck(), dealer)
	game.wall.set_head(0)
	game.phase = RoundState.Phase.PLAYING
	return game

func _test_dragon() -> void:
	var pattern := RuleEngine.analyze(DRAGON, [])
	t.expect(pattern.win and pattern.seven_pairs and pattern.dragon_seven_pairs, "四张同牌七对判龙七对")
	var ordinary := ["tiao1", "tiao1", "wan2", "wan2", "wan5", "wan5", "tong3", "tong3", "tong6", "tong6", "tiao9", "tiao9", "wan8", "wan8"]
	pattern = RuleEngine.analyze(ordinary, [])
	t.expect(pattern.seven_pairs and not pattern.dragon_seven_pairs, "普通七对仍为24分")
	var two_quads := ["tiao1", "tiao1", "tiao1", "tiao1", "tong3", "tong3", "tong3", "tong3", "wan2", "wan2", "wan5", "wan5", "tiao9", "tiao9"]
	t.expect(RuleEngine.analyze(two_quads, []).dragon_seven_pairs, "多个四张仍识别龙七对")
	var invalid := DRAGON.duplicate()
	invalid[4] = "tiao1"
	t.expect(not RuleEngine.analyze(invalid, []).win, "五张同牌不能胡")
	var fixed := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong2", "tong3", "tong4", "tiao9", "tiao9"]
	t.expect(not RuleEngine.analyze(fixed, [{"kind": "kong", "tile": "tiao1"}]).dragon_seven_pairs, "已杠出的四张不算手内龙七对")
	var game := _fixture()
	game.players[0].concealed = DRAGON.duplicate()
	game.round_meta.winner = 0
	game.round_meta.self_draw = true
	var scored := ScoringEngine.settle(game)
	t.expect(scored.deltas == [156.0, -52.0, -52.0, -52.0], "龙七对44含自摸基础，加手中鸡8，每家付52")
	var pattern_items: Array = scored.items[0].filter(func(item): return item.kind == "pattern")
	t.expect(pattern_items.size() == 1 and pattern_items[0].label == "龙七对" and pattern_items[0].amount == 44, "龙七对只记44，不叠普通七对24")
	t.expect(scored.status[0].contains("龙七对"), "结算显示龙七对")
	game.round_meta.self_draw = false
	game.round_meta.discard_seat = 2
	scored = ScoringEngine.settle(game)
	t.expect(scored.deltas == [68.0, -8.0, -52.0, -8.0], "每家付鸡8，放炮者另付龙七对44")
	game.players[0].concealed = DRAGON.slice(0, 13)
	t.expect(game.can_win_on_discard(0, 2, "tiao9"), "龙七对可直接胡别人")
	t.expect(RuleEngine.waiting_tiles(game.players[0].concealed, []).has("tiao9"), "龙七对听牌等待正确")
	game.players[0].concealed = ["wan1", "wan1", "wan1", "wan1", "wan2", "wan2", "wan4", "wan4", "wan6", "wan6", "wan8", "wan8", "wan9", "wan9"]
	scored = ScoringEngine.settle(game)
	pattern_items = scored.items[0].filter(func(item): return item.kind == "pattern")
	t.expect(pattern_items.size() == 1 and pattern_items[0].label == "清龙对" and scored.round_points[0] == 64, "清龙对64替代普通牌型，不叠加干扣")
	game.players[0].concealed = two_quads
	scored = ScoringEngine.settle(game)
	t.expect(scored.deltas == [68.0, -8.0, -52.0, -8.0], "两组四张龙七对牌型仍44，手中鸡8逐家收取")

func _test_next_dealer() -> void:
	for dealer in 4:
		for winner in 4:
			var self_draw := _fixture(dealer)
			self_draw.players[winner].concealed = DRAGON.duplicate()
			self_draw._do_self_win(winner)
			t.expect(self_draw.next_dealer_seat == winner and self_draw.dealer_seat == dealer, "自摸者下局为庄，本局庄家不变")
			for source in 4:
				if source == winner:
					continue
				var discard := _fixture(dealer)
				discard.players[winner].concealed = DRAGON.slice(0, 13)
				discard.players[source].discards = ["tiao9"]
				discard._discard_win(winner, source, "tiao9")
				t.expect(discard.next_dealer_seat == source, "放炮换庄优先于胡牌者")
		var draw := _fixture(dealer)
		for player in draw.players:
			player.concealed = CALLED.duplicate()
		draw._penzu()
		t.expect(draw.next_dealer_seat == dealer and draw.next_chicken_multiplier == 2, "四家叫牌流局连庄且鸡分两倍")
		for uncalled in 4:
			var mixed := _fixture(dealer)
			for player in mixed.players:
				player.concealed = CALLED.duplicate() if player.seat != uncalled else []
			mixed._penzu()
			t.expect(mixed.next_dealer_seat == uncalled and mixed.next_chicken_multiplier == 1, "未叫牌者下局为庄")
		var multiple := _fixture(dealer)
		multiple.players[dealer].concealed = CALLED.duplicate()
		multiple._penzu()
		t.expect(multiple.next_dealer_seat == posmod(dealer + GameConfig.TURN_DIRECTION, 4), "多人未叫按庄家后的摸牌方向选第一位")

func _test_deal() -> void:
	for dealer in 4:
		var wall := WallRing.new(TileSetFactory.create_deck(), dealer)
		for seat in 4:
			var size := 28 if posmod(seat - dealer, 2) == 0 else 26
			t.expect(wall.wall_remaining(seat) == size and wall.wall_stack_counts(seat).size() == size / 2, "换庄14和13墩随庄家调整")
		for die in range(1, 7):
			var target := posmod(dealer + (2 if die in [1, 3, 5] else (3 if die == 4 else 1)), 4)
			var segment: Dictionary = wall._wall_seg_for_seat(target)
			t.expect(WallRing.compute_break(die, dealer) == segment.start + die * 2, "换庄骰子按相对方位破墙")
			var game := _fixture()
			game.apply_scores([-24, 324, 500, 0])
			game.next_dealer_seat = dealer
			game.set_rng_seed(42)
			game.start_round(0, die)
			t.expect(game.current_turn == dealer and game.awaiting and game.wall.remaining == 55, "新庄摸14张首先出牌")
			var expected := [[], [], [], []]
			var ring: Array = game.wall._ring
			var index := WallRing.compute_break(die, dealer)
			for batch in 3:
				for offset in 4:
					for tile in 4:
						expected[posmod(dealer + GameConfig.TURN_DIRECTION * offset, 4)].append(ring[posmod(index, 108)])
						index += 1
			for offset in 4:
				expected[posmod(dealer + GameConfig.TURN_DIRECTION * offset, 4)].append(ring[posmod(index, 108)])
				index += 1
			expected[dealer].append(ring[posmod(index, 108)])
			for seat in 4:
				t.expect(game.players[seat].concealed == expected[seat] and game.players[seat].is_dealer == (seat == dealer), "从新庄顺时针发牌且庄家标记唯一")
			t.expect(game.players[0].score == -24 and game.players[2].score == 500, "换庄保留累计和负数分值")
			var client := RoundState.new()
			client.apply_sync(game.serialize_for_seat(1))
			t.expect(client.dealer_seat == dealer and client.next_dealer_seat == dealer and client.current_turn == dealer, "联机同步庄家与首出座位")
			t.expect(client.players[0].score == -24 and client.players[dealer].is_dealer, "客户端同步累计分数和庄家")

func _test_network_round() -> void:
	# 在 Autoload 注册完成后加载，避免 --script 的入口预编译形成单例依赖环。
	var node = load("res://scripts/online/NetGameNode.gd").new()
	root.add_child(node)
	t.expect(node.host(false, true, 7535), "换庄测试建立真实主机成员")
	node.game = _fixture()
	node._started = true
	node.round_number = 1
	node.game.players[2].concealed = DRAGON.duplicate()
	node.game._do_self_win(2)
	var scores: Array = node.game.players.map(func(player): return player.score)
	node.next_round()
	t.expect(node.round_number == 1 and node._countdown == 1.0, "主机准备后等待1秒，不立即开局")
	node._process(1.01)
	t.expect(node.game.dealer_seat == 2 and node.game.current_turn == 2, "主机下一局消费结算选庄")
	t.expect(node.game.players.map(func(player): return player.score) == scores, "联机下一局保留结算分数")
	node.free()
	root.multiplayer.multiplayer_peer = null

func _test_score_ui() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(900, 950)
	root.add_child(table)
	await process_frame
	table.round.phase = RoundState.Phase.IDLE
	table.round = _fixture(2)
	for player in table.round.players:
		player.concealed = CALLED.duplicate()
	table.round.apply_scores([-24, 324, 200, 300])
	table._refresh()
	await process_frame
	for seat in 4:
		t.expect(table.center_labels[seat].text.contains("%.0f分" % table.round.players[seat].score), "四家牌桌当前分数即时显示")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		t.expect(root.get_texture().get_image().save_png("res://docs/table_current_scores.png") == OK, "保存四家分数与新庄家截图")
	table.round.phase = RoundState.Phase.IDLE
	table.queue_free()
	await process_frame
	await create_timer(0.2).timeout
