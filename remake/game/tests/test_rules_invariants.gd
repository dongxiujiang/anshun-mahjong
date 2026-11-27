extends SceneTree

const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Ai = preload("res://src/ai/AiPlayer.gd")
const Scoring = preload("res://src/anshun/scoring/ScoringEngine.gd")
const Rules = preload("res://src/anshun/scoring/RulesConfig.gd")

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _initialize() -> void:
	for seed_value in range(25):
		var ledger := play_round(seed_value * 173 + 4)
		if not ledger.is_empty():
			check_ledger(ledger, seed_value)
	for seed_value in [4, 177, 350]:
		var first := play_round(seed_value)
		var second := play_round(seed_value)
		if not first.is_empty() and not second.is_empty():
			for field in ["deltas", "winners", "multiplier"]:
				check(first[field] == second[field], "seed %d replay differs in %s" % [seed_value, field])
	check_documents()
	print("Rules invariants: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func play_round(seed_value: int) -> Dictionary:
	var game := Round.new()
	if not game.start(seed_value % 4, seed_value % 6 + 1, 2, Catalog.values(seed_value)) or not game.begin_dealer_turn():
		check(false, "seed %d could not start" % seed_value)
		return {}
	for step in 400:
		if game.phase == "settled":
			return Scoring.settle(game.settlement_facts())
		if game.phase == "ready_draw":
			if not game.finish_draw_animation(game.turn, game.prompt_id):
				check(false, "seed %d could not complete draw" % seed_value)
				return {}
			continue
		var acted := false
		for seat in 4:
			var decision := Ai.decide(game.snapshot_for(seat), "low")
			if decision.is_empty():
				continue
			if not game.submit(seat, decision.prompt_id, decision.action, decision.tile_id):
				check(false, "seed %d rejected AI action" % seed_value)
				return {}
			acted = true
			break
		if not acted:
			check(false, "seed %d has no AI action" % seed_value)
			return {}
	check(false, "seed %d did not settle" % seed_value)
	return {}

func check_ledger(ledger: Dictionary, seed_value: int) -> void:
	var total := 0.0
	for seat in 4:
		total += ledger.deltas[seat]
		var row_total := 0.0
		for other in 4:
			check(ledger.pairwise[seat][other] == -ledger.pairwise[other][seat], "seed %d pairwise mismatch" % seed_value)
			row_total += ledger.pairwise[seat][other]
		check(row_total == ledger.deltas[seat], "seed %d row mismatch" % seed_value)
	check(total == 0, "seed %d is not zero sum" % seed_value)
	for winner in ledger.winners:
		var count := 0
		for item in ledger.items[winner]:
			if item.kind == "pattern":
				count += 1
		check(count <= 1, "seed %d stacks patterns" % seed_value)

func check_documents() -> void:
	var doc_path := ProjectSettings.globalize_path("res://../../docs/规则玩法与计分.md")
	check(FileAccess.file_exists(doc_path), "rules document missing")
	var doc := FileAccess.get_file_as_string(doc_path)
	var expected := {"大对子": 14, "大对子单吊": 24, "小七对": 24, "清一色": 24, "清大对": 34, "龙七对": 44, "清七对": 44, "清单吊": 54, "清龙七对": 64}
	check(Rules.PATTERNS.size() == expected.size(), "pattern count differs")
	for pattern in Rules.PATTERNS:
		check(expected.has(pattern.label) and expected.get(pattern.label) == pattern.score, "unexpected code pattern: %s" % pattern.label)
		var found := false
		for line in doc.split("\n"):
			for cell_pair in [[0, 1], [2, 3]]:
				var cells := line.trim_prefix("|").trim_suffix("|").split("|")
				if cells.size() > cell_pair[1] and cells[cell_pair[0]].strip_edges().split("（")[0] == pattern.label and cells[cell_pair[1]].strip_edges() == str(int(pattern.score)):
					found = true
		check(found, "document pattern mismatch: %s" % pattern.label)
	for requirement in [["冲锋鸡", "+4"], ["冲锋金鸡", "+8"], ["干扣 / 大干扣", "14 / 24"], ["自摸基础分", "+4"], ["报听 / 杀报", "+24"], ["抢杠胡", "12"], ["杠开 / 海底捞月", "+5"], ["独立杠分", "4"]]:
		var found := false
		for line in doc.split("\n"):
			if requirement[0] in line and requirement[1] in line:
				found = true
		check(found, "document base score mismatch: %s" % requirement[0])
	var last_four_found := false
	for line in doc.split("\n"):
		if "杠开 / 海底捞月" in line and line.count("+5") == 2:
			last_four_found = true
	check(last_four_found, "document must give both 杠开 and 海底 +5")
	check(Rules.SCORE_CHARGE_CHICKEN == 4 and Rules.SCORE_CHARGE_CHICKEN * Rules.SCORE_FLIP_DOUBLE == 8 and Rules.SCORE_NO_CHICKEN == 14 and Rules.SCORE_BIG_NO_CHICKEN == 24 and Rules.SCORE_SELF_DRAW == 4 and Rules.SCORE_READY == 24 and Rules.SCORE_ROB_KONG == 12 and Rules.SCORE_KONG_DRAW == 5 and Rules.SCORE_LAST_FOUR == 5 and Rules.SCORE_DRAW_KONG == 4, "code base scores differ")
	var version_path := ProjectSettings.globalize_path("res://../version.json")
	var version = JSON.parse_string(FileAccess.get_file_as_string(version_path))
	var presets := ConfigFile.new()
	var loaded := presets.load("res://export_presets.cfg") == OK
	check(version is Dictionary and loaded, "version metadata could not be read")
	if version is Dictionary and loaded:
		check(str(ProjectSettings.get_setting("application/config/version", "")) == str(version.get("version", "")), "project version differs from version metadata")
		for section in ["preset.0.options", "preset.1.options"]:
			check(presets.get_value(section, "version/name") == version.get("version"), "%s version name mismatch" % section)
			check(presets.get_value(section, "version/code") == version.get("version_code"), "%s version code mismatch" % section)
