class_name AiTeaching
extends RefCounted
## AI 教打入口。当前只返回一个可用的占位建议，真正的进张数、危险度
## 和牌效比较后续在这里接入；UI/高亮/消息接口已经固定。

static func recommend(round, seat: int) -> Dictionary:
	if round == null or seat < 0 or seat >= round.players.size():
		return {}
	if round.phase != RoundState.Phase.PLAYING or not round.awaiting or round.current_turn != seat:
		return {"message": "AI教打：当前不是你的出牌回合"}
	var player: PlayerState = round.players[seat]
	var options: Dictionary = round.legal_turn_options(seat)
	var discards: Array = options.get("discards", [])
	if discards.is_empty():
		return {"message": "AI教打：当前没有可分析的出牌"}
	var tile := str(player.just_drew)
	if tile == "" or not discards.has(tile):
		tile = str(discards[0])
	return {"tile": tile, "message": "AI教打：建议打%s；牌效与进张分析待接入" % _display(tile)}

static func _display(tile: String) -> String:
	var suit := Tiles.suit(tile)
	var rank := Tiles.rank(tile)
	return "%d%s" % [rank, {"wan": "万", "tiao": "条", "tong": "筒"}.get(suit, "")]
