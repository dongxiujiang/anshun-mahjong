extends SceneTree
const H := preload("res://tests/test_harness.gd")
const MCTS := preload("res://scripts/ai/AiMctsSearch.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var round := RoundState.new()
	round.build_players(0)
	round.wall_remain = {0: 30}
	round.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "tong9"]
	var ai := AiPlayer.new()
	var seen := ai._seen_map(round, 0)
	var context := ai.opponent_model.observe(round, 0, seen)
	var candidates: Array = []
	for tile in Tiles.to_counts(round.players[0].concealed): candidates.append({"tile": tile})
	var search := MCTS.new()
	var pool: Array[int] = search._pool(seen)
	var pool_before: Array[int] = pool.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var drawn := search._draw_and_consume(pool, rng)
	t.expect(drawn >= 0 and pool[drawn] == pool_before[drawn] - 1, "MCTS 摸牌必须立即扣减模拟牌池")
	var empty_pool: Array[int] = []
	empty_pool.resize(27)
	empty_pool.fill(0)
	t.expect(search._draw_and_consume(empty_pool, rng) == -1, "模拟牌池耗尽后不能继续摸牌")
	var rollout_pool: Array[int] = search._pool(seen)
	var rollout_before: Array[int] = rollout_pool.duplicate()
	search._simulate(round, 0, round.players[0].concealed.duplicate(), [], rollout_pool, rng, context)
	t.expect(rollout_pool == rollout_before, "每个 MCTS rollout 不能污染外部牌池")
	var result := search.rank(round, 0, round.players[0].concealed, [], seen, candidates, context)
	t.expect(result.size() == candidates.size(), "MCTS returns every legal discard root")
	var visits := 0
	for tile in result:
		visits += int(result[tile].visits)
		t.expect(int(result[tile].visits) > 0 and is_finite(float(result[tile].value)), "MCTS root has finite visits and value")
	t.expect(visits == search.ITERATIONS, "MCTS uses bounded iteration budget")
	var choice := ai._pick_discard(round, 0)
	t.expect(round.players[0].concealed.has(choice.tile), "MCTS-integrated AI chooses a legal discard")
	var hidden: Array = round.players[1].concealed.duplicate()
	round.players[1].concealed = ["wan9", "wan9", "wan9", "wan9"]
	t.expect(ai._pick_discard(round, 0).tile == choice.tile, "MCTS choice is independent of hidden opponent hand")
	round.players[1].concealed = hidden
	print("[ai_mcts] %d roots, %d visits" % [result.size(), visits])
	quit(t.finish("ai_mcts"))
