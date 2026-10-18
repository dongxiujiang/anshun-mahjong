extends SceneTree
## 一次跑完所有 headless 单测：任一测试失败则整体以退出码 1 结束，可直接用于 CI。
##
## 运行： godot --headless --script res://tests/run_all.gd
## 注意：联机测试（host/client 配对）需要两个进程，不在这里跑，见 README 第七节。

const SUITES: Array[String] = [
	"res://tests/smoke_lan_discovery.gd",
	"res://tests/lan_join_perf.gd",
	"res://tests/smoke_lobby.gd",
	"res://tests/smoke_lobby_flow.gd",
	"res://tests/smoke_update.gd",
	"res://tests/update_download_routes.gd",
	"res://tests/smoke_hot_update.gd",
	"res://tests/smoke_tiles.gd",
	"res://tests/smoke_wall.gd",
	"res://tests/smoke_logic.gd",
	"res://tests/shanten_cache.gd",
	"res://tests/smoke_scoring.gd",
	"res://tests/settlement_card.gd",
	"res://tests/settlement_animation_flow.gd",
	"res://tests/settlement_score_details.gd",
	"res://tests/settlement_score_inspection.gd",
	"res://tests/scoring_audit.gd",
	"res://tests/scoring_pairwise.gd",
	"res://tests/smoke_ready.gd",
	"res://tests/rules_complete.gd",
	"res://tests/rules_update.gd",
	"res://tests/rules_v2.gd",
	"res://tests/rules_spec.gd",
	"res://tests/rules_randomized.gd",
	"res://tests/dragon_dealer.gd",
	"res://tests/smoke_round.gd",
	"res://tests/round_sync.gd",
	"res://tests/legal_actions.gd",
	"res://tests/round_replay.gd",
	"res://tests/replay_export.gd",
	"res://tests/ai_inference.gd",
	"res://tests/ai_value.gd",
	"res://tests/ai_mcts.gd",
	"res://tests/smoke_ai.gd",
	"res://tests/sweep.gd",
	"res://tests/smoke_table_layout.gd",
	"res://tests/table_components.gd",
	"res://tests/ui_presentation.gd",
	"res://tests/play_animation_flow.gd",
	"res://tests/animation_speed_settings.gd",
	"res://tests/table_interaction.gd",
	"res://tests/focus_return_input.gd",
	"res://tests/discard_identity.gd",
	"res://tests/center_dashboard.gd",
	"res://tests/table_controls_perf.gd",
	"res://tests/network_latency.gd",
	"res://tests/reconnect_control.gd",
	"res://tests/smoke_ui.gd",
	"res://tests/smoke_audio.gd",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var godot := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var failed: Array[String] = []
	var passed := 0
	print("════ 全部测试 共 %d 套 ════" % SUITES.size())
	for suite in SUITES:
		# --quit 只跑一帧，会把异步UI测试中途退出误判成通过。
		var args := ["--headless", "--path", project, "--script", suite, "--quit-after", "10000"]
		var output: Array = []
		var code := OS.execute(godot, args, output, true)
		var text := "".join(output)
		var name := suite.get_file()
		var completed := false
		for line in text.split("\n"):
			if line.begins_with("[%s]" % name.get_basename()) and (line.contains("通过") or line.contains("passed") or line.contains("0 failures")):
				completed = true
		if code == 0 and (not completed or text.contains("SCRIPT ERROR:") or text.contains("\nERROR:")):
			code = 1
			text += "\n测试未完整结束，或输出中包含脚本错误。\n"
		if code == 0:
			passed += 1
		else:
			failed.append(name)
			print("---- %s 失败 (退出码 %d) ----" % [name, code])
			print(text)
		print("%s %s" % ["[ok]  " if code == 0 else "[FAIL]", name])
	print("════ 结果: 通过 %d / 失败 %d ════" % [passed, failed.size()])
	if failed.is_empty():
		quit(0)
		return
	print("失败套件: %s" % ", ".join(failed))
	quit(1)
