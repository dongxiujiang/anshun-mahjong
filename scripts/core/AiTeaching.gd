class_name AiTeaching
extends RefCounted
## AI 教打入口：复用现有 AI 的公开信息模型，分析自己手牌（含刚摸到的牌）
## 后给出推荐。不会读取对手暗手或牌墙顺序。

const AI_PLAYER := preload("res://scripts/ai/AiPlayer.gd")

static func recommend(round, seat: int) -> Dictionary:
	if round == null or seat < 0 or seat >= round.players.size():
		return {}
	if round.phase != RoundState.Phase.PLAYING or not round.awaiting or round.current_turn != seat:
		return {"message": "AI教打：当前不是你的出牌回合"}
	var player: PlayerState = round.players[seat]
	var options: Dictionary = round.legal_turn_options(seat)
	if options.get("self_win", false):
		return {"message": "AI教打：建议自摸；当前手牌已经满足胡牌条件"}
	if not options.get("kong_declares", []).is_empty():
		return {"message": "AI教打：建议暗杠 %s；完成后从牌尾补牌" % _display(str(options.kong_declares[0]))}
	if not options.get("add_kong", []).is_empty():
		return {"message": "AI教打：建议加杠 %s；注意可能被抢杠" % _display(str(options.add_kong[0]))}
	var discards: Array = options.get("discards", [])
	if discards.is_empty():
		return {"message": "AI教打：当前没有可分析的出牌"}
	# 教打与正式 AI 共用同一套公开信息推理；刚摸到的牌已经在
	# player.concealed 中，这里显式复制，避免后续误改权威手牌。
	var ai := AI_PLAYER.new("AI教打")
	# Teaching runs on the UI thread. Use the value model's bounded candidate
	# analysis without an MCTS rollout so clicking 教打 cannot freeze a frame.
	ai.use_mcts = false
	var decision: Dictionary = ai.decide_turn(round, seat)
	var tile := str(decision.get("discard", ""))
	if tile == "" or not discards.has(tile):
		tile = str(player.just_drew)
	if tile == "" or not discards.has(tile):
		tile = str(discards[0])
	var detail := ""
	for candidate in ai.last_analysis:
		if str(candidate.get("tile", "")) == tile:
			detail = "；向听%d，进张%d" % [int(candidate.get("distance", 0)), int(candidate.get("outs", 0))]
			break
	return {"tile": tile, "message": "AI教打：建议打%s%s" % [_display(tile), detail]}

static func _display(tile: String) -> String:
	var suit := Tiles.suit(tile)
	var rank := Tiles.rank(tile)
	return "%d%s" % [rank, {"wan": "万", "tiao": "条", "tong": "筒"}.get(suit, "")]
