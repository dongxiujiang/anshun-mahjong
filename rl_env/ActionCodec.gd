extends RefCounted
## 固定动作编码：只描述动作，不判断规则。
## 规则合法性始终来自 RoundState.legal_* / allowed_actions。

const TILE_COUNT := 27

const DISCARD_BASE := 0
const READY_BASE := 27
const KONG_BASE := 54
const ADD_KONG_BASE := 81
const SELF_WIN := 108
const PONG := 109
const RESPONSE_KONG := 110
const RESPONSE_WIN := 111
const PASS := 112
const ACTION_COUNT := 113

static func index_of(tile: String) -> int:
	return Tiles.value_index(tile)

static func tile_of(index: int) -> String:
	return Tiles.from_index(index)

static func turn_actions(options: Dictionary) -> Array:
	var out: Array = []
	for tile in options.get("discards", []):
		out.append({"code": DISCARD_BASE + index_of(str(tile)), "kind": "discard", "tile": str(tile)})
		if (options.get("ready_discards", []) as Array).has(tile):
			out.append({"code": READY_BASE + index_of(str(tile)), "kind": "ready_discard", "tile": str(tile)})
	for tile in options.get("kong_declares", []):
		out.append({"code": KONG_BASE + index_of(str(tile)), "kind": "kong", "tile": str(tile)})
	for tile in options.get("add_kong", []):
		out.append({"code": ADD_KONG_BASE + index_of(str(tile)), "kind": "add_kong", "tile": str(tile)})
	if bool(options.get("self_win", false)):
		out.append({"code": SELF_WIN, "kind": "self_win", "tile": ""})
	return out

static func response_actions(options: Dictionary) -> Array:
	var out: Array = []
	if bool(options.get("can_win", false)):
		out.append({"code": RESPONSE_WIN, "kind": "win", "tile": ""})
	if bool(options.get("can_pong", false)):
		out.append({"code": PONG, "kind": "pong", "tile": ""})
	if bool(options.get("can_kong", false)):
		out.append({"code": RESPONSE_KONG, "kind": "kong_response", "tile": ""})
	out.append({"code": PASS, "kind": "pass", "tile": ""})
	return out

static func mask(actions: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(ACTION_COUNT)
	out.fill(0)
	for action in actions:
		var code := int(action.get("code", -1))
		if code >= 0 and code < ACTION_COUNT:
			out[code] = 1
	return out

static func action_for_code(code: int, actions: Array) -> Dictionary:
	for action in actions:
		if int(action.get("code", -1)) == code:
			return action
	return {}

static func decision_for(action: Dictionary) -> Dictionary:
	match str(action.get("kind", "")):
		"discard":
			return {"discard": str(action.get("tile", ""))}
		"ready_discard":
			return {"discard": str(action.get("tile", "")), "ready": true}
		"kong":
			return {"kong_declares": [str(action.get("tile", ""))]}
		"add_kong":
			return {"add_kong": [str(action.get("tile", ""))]}
		"self_win":
			return {"self_win": true}
		"win":
			return {"action": "win"}
		"pong":
			return {"action": "pong"}
		"kong_response":
			return {"action": "kong"}
		"pass":
			return {"action": "pass"}
	return {}
