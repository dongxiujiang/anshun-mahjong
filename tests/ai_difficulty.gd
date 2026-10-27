extends SceneTree

const H := preload("res://tests/test_harness.gd")
const AI := preload("res://scripts/ai/AiPlayer.gd")
const BENCH := preload("res://scripts/ai/AiBenchmark.gd")
var t := H.new()

func _initialize() -> void:
	var low := AI.new("low", "low")
	var medium := AI.new("medium", "medium")
	var high := AI.new("high", "high")
	t.expect(low.mcts.iterations == 16, "低难度保持 16 次搜索")
	t.expect(medium.mcts.iterations == 16, "中难度不靠盲目增加搜索量")
	t.expect(high.mcts.iterations == 32, "高难度是低的 2 倍搜索量")
	t.expect(medium.defense_weight > low.defense_weight and medium.risk_inflation > low.risk_inflation,
		"中难度明显加强防守权重")
	t.expect(medium.ready_bonus > 0.0, "中难度兼顾报听速度")
	var report := BENCH.format_report({"games": 4, "levels": {
		"low": {"games": 4, "wins": 1, "deal_ins": 1, "score": 8.0},
		"medium": {"games": 8, "wins": 2, "deal_ins": 2, "score": 0.0},
		"high": {"games": 4, "wins": 1, "deal_ins": 0, "score": -8.0},
	}})
	t.expect(report.contains("低：胜率 25.0%") and report.contains("中：胜率 25.0%") and report.contains("高：胜率 25.0%"), "测试模式输出每个 AI 的胜率、放炮和均分")
	quit(t.finish("ai_difficulty"))
