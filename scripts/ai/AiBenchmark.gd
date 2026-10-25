extends RefCounted
## 临时测试模式：主线程按时间片推进 AI 对局，避免阻塞牌桌。

const AI := preload("res://scripts/ai/AiPlayer.gd")
const LEVELS := ["medium", "low", "medium", "high"]
const LEVEL_NAMES := {"low": "低", "medium": "中", "high": "高"}

var total := 10000
var done := 0
var running := false
var cancel := false
var report := {}
var _round: RoundState = null
var _actors: Array = []
var _levels: Array = []
var _game_index := 0
var _start_index := 0
var _stats := {}
var _started_ms := 0
var _aborted := false

func start(games: int = 10000, start_index: int = 0) -> void:
	total = maxi(1, games)
	done = 0
	running = true
	cancel = false
	report = {}
	_round = null
	_actors.clear()
	_levels.clear()
	_start_index = maxi(0, start_index)
	_game_index = _start_index
	_aborted = false
	_stats = {}
	for level in LEVEL_NAMES:
		_stats[level] = {"games": 0, "wins": 0, "deal_ins": 0, "score": 0.0}
	_started_ms = Time.get_ticks_msec()
	_begin_next_game()

func stop() -> void:
	cancel = true
	running = false

func snapshot() -> Dictionary:
	return {"done": done, "total": total, "running": running, "report": report.duplicate(true),
		"elapsed_ms": Time.get_ticks_msec() - _started_ms}

func step(budget_ms: int = 20) -> void:
	if not running:
		return
	var deadline := Time.get_ticks_msec() + maxi(1, budget_ms)
	while running and not cancel and Time.get_ticks_msec() < deadline:
		if done >= total:
			_finish()
			return
		if _round == null and not _begin_next_game():
			_finish()
			return
		if _round.phase == RoundState.Phase.SETTLED:
			_record_game()
			continue
		if not _advance_one_action():
			_aborted = true
			_record_game()
			continue
	_finish_if_done()

func _begin_next_game() -> bool:
	if done + (1 if _round != null else 0) >= total and _round == null:
		return false
	_levels = LEVELS.duplicate()
	for shift in _game_index % 4:
		_levels.append(_levels.pop_front())
	_actors.clear()
	for seat in 4:
		_actors.append(AI.new("AI%d" % seat, str(_levels[seat])))
	_round = RoundState.new()
	_round.build_players(0)
	_round.controllers = [null, null, null, null]
	_round.ai_delay_seconds = 0.0
	_round.ai_response_delay_seconds = 0.0
	_round.opening_delay_seconds = 0.0
	_round.start_round(_game_index % 4, _game_index % 6 + 1)
	_game_index += 1
	_aborted = false
	return true

func _advance_one_action() -> bool:
	if _round == null or _round.phase != RoundState.Phase.PLAYING:
		return false
	if _round.awaiting and not _round._awaiting_response.is_empty():
		var prompt: Dictionary = _round._awaiting_response
		var seat := int(prompt.get("seat", -1))
		if seat < 0 or seat >= 4:
			return false
		var source := int(prompt.get("disc_seat", -1))
		var tile := str(prompt.get("tile", ""))
		var options: Dictionary = prompt.get("options", {})
		var decision: Dictionary = _actors[seat].decide_response(_round, seat, source, tile, options)
		return _round.submit_response(seat, tile, decision)
	var seat := int(_round.current_turn)
	if seat < 0 or seat >= 4:
		return false
	var decision: Dictionary = _actors[seat].decide_turn(_round, seat)
	return _round.submit_turn(seat, decision)

func _record_game() -> void:
	if _round == null:
		return
	if _aborted or _round.last_result.is_empty():
		_round = null
		done += 1
		_finish_if_done()
		return
	var meta: Dictionary = _round.last_result.get("round_meta", {})
	var winners: Array = meta.get("winners", [])
	if winners.is_empty() and int(meta.get("winner", -1)) >= 0:
		winners = [int(meta.get("winner", -1))]
	var discard_seat := int(meta.get("discard_seat", -1))
	var self_draw := bool(meta.get("self_draw", false))
	var deltas: Array = _round.last_result.get("deltas", [0.0, 0.0, 0.0, 0.0])
	for seat in 4:
		var level := str(_levels[seat])
		var data: Dictionary = _stats[level]
		data.games = int(data.games) + 1
		data.score = float(data.score) + float(deltas[seat])
		if winners.has(seat):
			data.wins = int(data.wins) + 1
		if not self_draw and discard_seat == seat and not winners.is_empty():
			data.deal_ins = int(data.deal_ins) + 1
		_stats[level] = data
	done += 1
	_round = null
	_finish_if_done()

func _finish_if_done() -> void:
	if done >= total:
		_finish()

func _finish() -> void:
	if not running:
		return
	running = false
	report = {"games": done, "start_index": _start_index, "levels": _stats.duplicate(true)}

static func format_report(data: Dictionary) -> String:
	var games := int(data.get("games", 0))
	var text := "AI测试：%d 局\n" % games
	for level in ["low", "medium", "high"]:
		var item: Dictionary = data.get("levels", {}).get(level, {})
		var n := int(item.get("games", 0))
		var win_rate := 100.0 * float(item.get("wins", 0)) / float(maxi(1, n))
		var deal_rate := 100.0 * float(item.get("deal_ins", 0)) / float(maxi(1, n))
		var avg := float(item.get("score", 0.0)) / float(maxi(1, n))
		text += "%s：胜率 %.1f%%  放炮 %.1f%%  均分 %.1f\n" % [LEVEL_NAMES[level], win_rate, deal_rate, avg]
	return text.strip_edges()
