extends SceneTree
## 一次跑完所有 headless 单测：任一测试失败则整体以退出码 1 结束，可直接用于 CI。
##
## 运行： godot --headless --script res://tests/run_all.gd
## 注意：联机测试（host/client 配对）需要两个进程，不在这里跑，见 README 第七节。

const SUITES: Array[String] = [
	"res://tests/smoke_tiles.gd",
	"res://tests/smoke_wall.gd",
	"res://tests/smoke_logic.gd",
	"res://tests/smoke_scoring.gd",
	"res://tests/smoke_ready.gd",
	"res://tests/rules_complete.gd",
	"res://tests/rules_update.gd",
	"res://tests/smoke_round.gd",
	"res://tests/smoke_ai.gd",
	"res://tests/sweep.gd",
	"res://tests/smoke_table_layout.gd",
	"res://tests/smoke_ui.gd",
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
		var args := ["--headless", "--path", project, "--script", suite, "--quit"]
		var output: Array = []
		var code := OS.execute(godot, args, output, true)
		var text := "".join(output)
		var name := suite.get_file()
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
	print("失败套件: %s" % ", ".join(failed))
	quit(1)
