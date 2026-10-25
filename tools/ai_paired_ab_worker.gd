extends SceneTree
## 配对 A/B 分片 worker：同一 seed 的候选局 + baseline 局。

const PAIRED := preload("res://scripts/ai/AiPairedAB.gd")

func _initialize() -> void:
	var start := 0
	var pairs := 20
	var candidate := "medium"
	var baseline := "low"
	var defense := 0.0
	var inference := 1.0
	var calibrated := false
	var risk_aversion := 1.0
	var output := ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--start" and index + 1 < args.size():
			start = int(args[index + 1])
		elif args[index] == "--pairs" and index + 1 < args.size():
			pairs = int(args[index + 1])
		elif args[index] == "--candidate" and index + 1 < args.size():
			candidate = args[index + 1]
		elif args[index] == "--baseline" and index + 1 < args.size():
			baseline = args[index + 1]
		elif args[index] == "--defense" and index + 1 < args.size():
			defense = float(args[index + 1])
		elif args[index] == "--inference" and index + 1 < args.size():
			inference = float(args[index + 1])
		elif args[index] == "--calibrated":
			calibrated = true
		elif args[index] == "--risk-aversion" and index + 1 < args.size():
			risk_aversion = float(args[index + 1])
		elif args[index] == "--output" and index + 1 < args.size():
			output = args[index + 1]
	if pairs <= 0:
		quit(2)
		return
	var results: Array = []
	for offset in pairs:
		var seed := start + offset
		results.append(PAIRED.run_pair(seed, candidate, baseline, seed % 4, defense, inference, calibrated, risk_aversion))
	var report := PAIRED.summarize(results, candidate, baseline)
	report["defense_weight"] = defense
	report["inference_weight"] = inference
	report["calibrated"] = calibrated
	report["risk_aversion"] = risk_aversion
	report["worker_start"] = start
	report["worker_pairs"] = pairs
	if output != "":
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report))
			file.close()
	print("AI_PAIRED_DONE start=%d pairs=%d" % [start, pairs])
	quit(0)
