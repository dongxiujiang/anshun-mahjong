class_name AiTeaching
extends RefCounted
## AI 教打入口：复用现有 AI 的公开信息模型，分析自己手牌（含刚摸到的牌）
## 后给出推荐。不会读取对手暗手或牌墙顺序。

const AI_PLAYER := preload("res://scripts/ai/AiPlayer.gd")
const CONFIG := preload("res://scripts/autoload/GameConfig.gd")

static func turn_message(decision: Dictionary) -> String:
	if bool(decision.get("self_win", false)):
		return "这张正好可以自摸，胡吧。"
	if not decision.get("kong_declares", []).is_empty():
		return "%s有四张，可以暗杠，再补一张。" % _display(str(decision.kong_declares[0]))
	if not decision.get("add_kong", []).is_empty():
		return "%s可以加杠，留意别人抢杠。" % _display(str(decision.add_kong[0]))
	var tile := str(decision.get("discard", decision.get("tile", "")))
	if tile.is_empty(): return "先看看手里的搭配。"
	if bool(decision.get("ready", false)):
		return "打%s报听，之后就只能摸打了。" % _display(tile)
	var message := "先打%s" % _display(tile)
	var alternatives: Array = []
	for item in decision.get("recommendations", []):
		var other := str(item.get("tile", "")) if item is Dictionary else str(item)
		if other == tile and item is Dictionary:
			var distance := int(item.get("distance", -1))
			if distance == 0 and int(item.get("outs", 0)) > 0:
				message += "，打完就能叫牌"
			elif distance > 0:
				message += "，至少还差%d张叫牌" % distance
		elif not other.is_empty() and not alternatives.has(other):
			alternatives.append(other)
	if not alternatives.is_empty():
		message += "。\n也可以考虑" + "、".join(alternatives.slice(0, 3).map(func(value): return _display(str(value))))
	return message + "。"

static func response_message(action: String, tile: String) -> String:
	var name := _display(tile)
	match action:
		"win": return "这张%s可以胡。" % name
		"kong": return "%s可以明杠，杠完再补一张。" % name
		"pong": return "%s可以碰，碰完记得打一张。" % name
	return "先过这张%s，保留手里的搭配。" % name

static func recommend(round, seat: int, level_override: String = "") -> Dictionary:
	if round == null or seat < 0 or seat >= round.players.size():
		return {}
	if round.phase != RoundState.Phase.PLAYING or not round.awaiting or round.current_turn != seat:
		return {"message": "还没轮到你，先看看大家打什么。"}
	var player: PlayerState = round.players[seat]
	var options: Dictionary = round.legal_turn_options(seat)
	if options.get("self_win", false):
		return {"action": "win", "label": "自摸", "message": turn_message({"self_win": true})}
	if not options.get("kong_declares", []).is_empty():
		return {"action": "kong", "label": "暗杠", "tile": str(options.kong_declares[0]),
			"message": turn_message({"kong_declares": options.kong_declares})}
	if not options.get("add_kong", []).is_empty():
		return {"action": "kong", "label": "加杠", "tile": str(options.add_kong[0]),
			"message": turn_message({"add_kong": options.add_kong})}
	var discards: Array = options.get("discards", [])
	if discards.is_empty():
		return {"message": "现在还不能出牌，稍等一下。"}
	# 教打与正式 AI 共用同一套公开信息推理；刚摸到的牌已经在
	# player.concealed 中，这里显式复制，避免后续误改权威手牌。
	var level: String = level_override
	if level == "":
		level = {"weak": "low", "medium": "medium", "strong": "high"}.get(CONFIG.ai_strength, "low")
	var ai := AI_PLAYER.new("AI教学", level)
	# 教打可选择工作线程执行；无 MCTS 的价值分析本身保持纯读快照。
	ai.use_mcts = false
	var decision: Dictionary = ai.decide_turn(round, seat)
	var tile := str(decision.get("discard", ""))
	if tile == "" or not discards.has(tile):
		tile = str(player.just_drew)
	if tile == "" or not discards.has(tile):
		tile = str(discards[0])
	var detail: Array = []
	for candidate in ai.last_analysis:
		if str(candidate.get("tile", "")) == tile:
			detail.append(candidate)
			break
	return {"action": "discard", "tile": tile, "message": turn_message({"discard": tile, "recommendations": detail})}

## 高频教打：只做出牌向听/进张分析，不启动 AI 决策线程，避免 120Hz 掉帧。
static func recommend_fast(round, seat: int) -> Dictionary:
	if round == null or seat < 0 or seat >= round.players.size():
		return {}
	if round.phase != RoundState.Phase.PLAYING or not round.awaiting or round.current_turn != seat:
		return {"message": "还没轮到你，先看看大家打什么。"}
	var player: PlayerState = round.players[seat]
	var options: Dictionary = round.legal_turn_options(seat)
	if options.get("self_win", false):
		return {"action": "win", "label": "自摸", "message": turn_message({"self_win": true})}
	if not options.get("kong_declares", []).is_empty():
		return {"action": "kong", "label": "暗杠", "tile": str(options.kong_declares[0]),
			"message": turn_message({"kong_declares": options.kong_declares})}
	if not options.get("add_kong", []).is_empty():
		return {"action": "kong", "label": "加杠", "tile": str(options.add_kong[0]),
			"message": turn_message({"add_kong": options.add_kong})}
	var discards: Array = options.get("discards", [])
	if discards.is_empty():
		return {"message": "现在还不能出牌，稍等一下。"}
	var best_tile := str(discards[0])
	var best_distance := 99
	for tile in discards:
		var hand: Array = player.concealed.duplicate()
		hand.erase(str(tile))
		var distance := Shanten.shanten(hand, player.melds)
		if distance < best_distance:
			best_distance = distance
			best_tile = str(tile)
	return {"action": "discard", "tile": best_tile,
		"message": turn_message({"discard": best_tile, "recommendations": [{"tile": best_tile, "distance": best_distance}]})}

## 碰杠响应只在动作条出现时使用；优先级判断足够，不要启动完整 AI 评估。
static func recommend_response_fast(round, seat: int, source: int, tile: String, options: Dictionary) -> Dictionary:
	if round == null or seat < 0 or seat >= round.players.size():
		return {}
	if options.get("can_win", false):
		return {"action": "win", "label": "胡", "message": response_message("win", tile)}
	if options.get("can_kong", false):
		return {"action": "kong", "label": "杠", "message": response_message("kong", tile)}
	if options.get("can_pong", false):
		return {"action": "pong", "label": "碰", "message": response_message("pong", tile)}
	return {"action": "pass", "label": "", "message": response_message("pass", tile)}

static func _display(tile: String) -> String:
	var suit := Tiles.suit(tile)
	var rank := Tiles.rank(tile)
	return "%d%s" % [rank, {"wan": "万", "tiao": "条", "tong": "筒"}.get(suit, "")]


