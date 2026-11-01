extends RefCounted
## 固定长度、只含公开信息的特征编码。
## observation 来自 RlEnv，禁止在这里访问 round 的隐藏状态。

const FEATURE_DIM := 521
const TURN_FEATURE_DIM := 522

static func _counts(tiles: Array) -> Array:
	var out: Array = []
	out.resize(27)
	out.fill(0.0)
	for tile in tiles:
		var i := Tiles.value_index(str(tile))
		if i >= 0 and i < 27: out[i] += 1.0
	return out

static func _onehot(index: int, size: int) -> Array:
	var out: Array = []
	out.resize(size)
	out.fill(0.0)
	if index >= 0 and index < size: out[index] = 1.0
	return out

static func encode(obs: Dictionary) -> Array:
	var x: Array = []
	x.append_array(_counts(obs.get("hand", [])))
	var own_meld_tiles: Array = []
	for meld in obs.get("own_melds", []): own_meld_tiles.append(str(meld.get("tile", "")))
	x.append_array(_counts(own_meld_tiles))
	var kinds := [0.0, 0.0, 0.0, 0.0]
	for meld in obs.get("own_melds", []):
		match str(meld.get("kind", "")):
			"pung": kinds[0] += 1.0
			"kong": kinds[1 if bool(meld.get("concealed", false)) else 2] += 1.0
			"add_kong": kinds[3] += 1.0
	x.append_array(kinds)
	var players: Array = obs.get("players", [])
	x.append_array(_counts(players[obs.seat].get("discards", [])))
	for p in players: x.append_array(_counts(p.get("discards", [])))
	for p in players:
		var meld_tiles: Array = []
		for meld in p.get("melds", []):
			if str(meld.get("tile", "")) != "": meld_tiles.append(str(meld.get("tile", "")))
		x.append_array(_counts(meld_tiles))
	for p in players: x.append(float(p.get("score", 0.0)) / 100.0)
	for p in players: x.append(1.0 if bool(p.get("ready", false)) else 0.0)
	x.append(float(obs.get("wall_count", 0)) / 55.0)
	x.append_array(_onehot(int(obs.get("dealer", -1)), 4))
	x.append_array(_onehot(int(obs.get("seat", -1)), 4))
	var response: Dictionary = obs.get("response", {})
	x.append(1.0 if not response.is_empty() else 0.0)
	x.append_array(_onehot(Tiles.value_index(str(response.get("tile", ""))) if not response.is_empty() else -1, 27))
	x.append_array(_onehot(int(response.get("source", -1)), 4))
	var last: Dictionary = obs.get("last_discard", {})
	x.append_array(_onehot(Tiles.value_index(str(last.get("tile", ""))) if not last.is_empty() else -1, 27))
	x.append_array(_onehot(int(last.get("seat", -1)), 4))
	x.append_array(_onehot(Tiles.value_index(str(obs.get("just_drew", ""))) if str(obs.get("just_drew", "")) != "" else -1, 27))
	for value in obs.get("action_mask", []): x.append(float(value))
	return x

## turn-only 对照专用：在公共特征后追加向听数。
static func encode_turn(obs: Dictionary) -> Array:
	var x := encode(obs)
	x.append(float(Shanten.shanten(obs.get("hand", []), obs.get("own_melds", []))) / 8.0)
	return x
