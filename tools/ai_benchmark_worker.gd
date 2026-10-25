extends SceneTree
## 并行批量 worker：复用权威 RoundState/评分/AI，只跑指定局数分片。

const BENCH := preload("res://scripts/ai/AiBenchmark.gd")

func _initialize() -> void:
	var start := 0
	var count := 100
	var output := ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--start" and index + 1 < args.size():
			start = int(args[index + 1])
		elif args[index] == "--count" and index + 1 < args.size():
			count = int(args[index + 1])
		elif args[index] == "--output" and index + 1 < args.size():
			output = args[index + 1]
	if count <= 0:
		quit(2)
		return
	var bench = BENCH.new()
	bench.start(count, start)
	while bench.running:
		bench.step(100)
	var report: Dictionary = bench.report.duplicate(true)
	report["worker_start"] = start
	report["worker_count"] = count
	if output != "":
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report))
			file.close()
	print("AI_WORKER_DONE start=%d count=%d games=%d" % [start, count, int(report.get("games", 0))])
	quit(0)
