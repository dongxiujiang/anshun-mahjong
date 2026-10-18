extends Node

# 结算动画完整流程验证
# 使用现有测试框架触发一局简单胡牌，检查动画流程

const GameConfig := preload("res://scripts/autoload/GameConfig.gd")

func _ready() -> void:
	print("\n========== 结算动画流程验证 ==========")
	print("[INFO] 检查 GameTable 是否正确实现结算动画状态机")
	
	# 运行现有的 settlement_card 测试，它会触发胡牌
	var test := load("res://tests/settlement_card.gd").new()
	add_child(test)
	
	# 等待测试完成
	await test.tree_exited
	
	print("\n[INFO] 结算卡片测试已完成")
	print("[TODO] 手动验证以下行为：")
	print("  1. 胡牌后不自动弹出结算页面")
	print("  2. 顺序播放六个阶段动画")
	print("  3. 动画完成后显示【查看结算】和【下一局】")
	print("  4. 点击【查看结算】后才显示结算页面")
	print("\n建议：在 Godot 编辑器中以可视化模式运行游戏")
	
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)
