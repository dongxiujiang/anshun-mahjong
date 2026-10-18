## 验证 multiplier 应用到牌型分
extends SceneTree

func _init():
	print("=== 测试流局和胡牌的倍率应用 ===\n")
	
	# 测试 1：流局时 multiplier 不应用
	print("【测试1：流局，multiplier=2，应该不翻倍】")
	var draw_result = ScoringEngine._result(
		[10.0, -5.0, -2.5, -2.5],
		["流局测试"],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
		[true, false, false, false],
		[{"from": 1, "to": 0, "amount": 5.0}],
		[[], [], [], []],
		["", "", "", ""],
		false,
		1,
		[],
		2
	)
	var draw_pass = (
		draw_result.deltas == [10.0, -5.0, -2.5, -2.5] and
		draw_result.transfers[0].amount == 5.0
	)
	print("  结果: ", "✓ PASS" if draw_pass else "✗ FAIL")
	print("  deltas: ", draw_result.deltas)
	
	# 测试 2：胡牌时 multiplier 应用
	print("\n【测试2：胡牌，multiplier=2，应该翻倍】")
	var win_result = ScoringEngine._result(
		[10.0, -5.0, -2.5, -2.5],
		["胡牌测试"],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
		[true, true, true, true],
		[{"from": 1, "to": 0, "amount": 5.0}],
		[[], [], [], []],
		["", "", "", ""],
		false,
		1,
		[0],
		2
	)
	var win_pass = (
		win_result.deltas == [20.0, -10.0, -5.0, -5.0] and
		win_result.transfers[0].amount == 10.0
	)
	print("  结果: ", "✓ PASS" if win_pass else "✗ FAIL")
	print("  deltas: ", win_result.deltas)
	
	# 测试 3：multiplier=1 时不改变
	print("\n【测试3：胡牌，multiplier=1，不应翻倍】")
	var no_mult = ScoringEngine._result(
		[10.0, -5.0, -2.5, -2.5],
		["无倍率"],
		[0, 0, 0, 0],
		[0, 0, 0, 0],
		[true, true, true, true],
		[{"from": 1, "to": 0, "amount": 5.0}],
		[[], [], [], []],
		["", "", "", ""],
		false,
		1,
		[0],
		1
	)
	var no_mult_pass = (no_mult.deltas == [10.0, -5.0, -2.5, -2.5])
	print("  结果: ", "✓ PASS" if no_mult_pass else "✗ FAIL")
	
	print("\n=== 总结 ===")
	var all_pass = draw_pass and win_pass and no_mult_pass
	if all_pass:
		print("✓ 所有测试通过")
		quit(0)
	else:
		print("✗ 部分测试失败")
		quit(1)
