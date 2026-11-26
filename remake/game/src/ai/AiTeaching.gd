extends RefCounted
## The action comes from the production AI. Teaching only translates and explains it.

const Ai = preload("res://src/ai/AiPlayer.gd")
const Observation = preload("res://src/ai/AiObservation.gd")
const Shanten = preload("res://src/anshun/scoring/Shanten.gd")
const Rules = preload("res://src/anshun/scoring/RuleEngine.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const TURN_ACTIONS := ["discard", "ready", "add_kong", "concealed_kong", "self_win", "pass"]
const RESPONSES := ["win", "kong", "pong", "pass"]

static func _fields(source: Dictionary, names: Array) -> Dictionary:
	var result := {}
	for key in names:
		if source.has(key):
			result[key] = source[key]
	return result

static func _tile_id(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= 0 and value < Catalog.COUNT and value == floorf(value)

## Mask again before crossing the worker boundary. Clock, wall slots, visual keys,
## credentials, selections and mouse motion are not decision inputs.
static func job_for(full_view: Dictionary, level: String) -> Dictionary:
	var room: Dictionary = full_view.get("room", {})
	var state: Dictionary = full_view.get("round", {})
	var seat := int(full_view.get("seat", -1))
	var choices: Dictionary = state.get("choices", {})
	var actions: Array = choices.get("actions", [])
	var prompt := int(state.get("prompt_id", -1))
	var phase: String = state.get("phase", "")
	if full_view.get("paused", false) or seat not in range(4) or state.get("viewer_seat") != seat or level not in Ai.DIFFICULTIES or actions.is_empty():
		return {}
	if room.get("room_instance_id", "") == "" or room.get("round_number", 0) < 1 or prompt < 0 or choices.get("prompt_id") != prompt:
		return {}
	if phase not in ["turn", "response"] or (phase == "turn" and state.get("turn") != seat) or state.get("players", []).size() != 4:
		return {}
	var legal := {"actions": actions.duplicate(), "prompt_id": prompt}
	for action in actions:
		if action not in (TURN_ACTIONS if phase == "turn" else RESPONSES):
			return {}
		if action in ["discard", "ready", "add_kong", "concealed_kong"]:
			var ids: Array = choices.get(action + "_ids", [])
			if ids.is_empty() or not ids.all(_tile_id):
				return {}
			legal[action + "_ids"] = ids.map(func(id): return int(id))
	if phase == "response":
		if choices.get("source", -1) not in range(4) or choices.source == seat or not Catalog.valid_value(choices.get("value", "")) or not _tile_id(choices.get("tile_id")):
			return {}
		legal.merge(_fields(choices, ["source", "value", "tile_id"]))
	var safe := _fields(state, ["phase", "viewer_seat", "wall_remaining", "chicken_multiplier", "draw_kind"])
	safe.choices = legal
	safe.last_discard = _fields(state.get("last_discard", {}), ["seat", "tile", "tile_id", "after_kong", "kong_kind"])
	safe.charge_chickens = {}
	var charges: Dictionary = state.get("charge_chickens", {})
	for tile in ["tiao1", "tong8"]:
		if charges.has(tile):
			safe.charge_chickens[tile] = _fields(charges[tile], ["owner", "location", "discard_id"])
	safe.players = []
	for position in 4:
		var row: Dictionary = state.players[position]
		if row.get("seat") != position:
			return {}
		var player := _fields(row, ["seat", "ready", "discard_count"])
		player.hand = []
		if position == seat:
			for face in row.hand:
				player.hand.append({"id": int(face.id), "value": face.value})
		player.discards = row.discards.map(func(face): return {"id": int(face.id), "value": face.value})
		player.melds = []
		for meld in row.melds:
			var visible: bool = position == seat or not meld.get("concealed", false) or (meld.has("formed_at") and row.discard_count >= meld.formed_at + 2)
			player.melds.append(_fields(meld, ["kind", "concealed", "tile", "from_seat", "formed_at"] if visible else ["kind", "concealed"]))
		safe.players.append(player)
	return {"room_instance_id": room.room_instance_id, "round_number": int(room.round_number), "seat": seat, "prompt_id": prompt, "view": safe}

static func recommend_one(view: Dictionary, level: String) -> Dictionary:
	return explain(view, level, Ai.decide(view, level))

static func explain(view: Dictionary, level: String, decision: Dictionary) -> Dictionary:
	var legal: Dictionary = view.choices
	var action: String = decision.get("action", "")
	var id: int = decision.get("tile_id", -1)
	if decision.get("prompt_id", -1) != legal.prompt_id or not legal.actions.has(action):
		return {}
	var tile := ""
	var message := ""
	if view.phase == "response":
		if id != legal.tile_id:
			return {}
		tile = legal.value
		var name := _name(tile)
		message = {"win": "这张%s可以胡。", "kong": "%s可以明杠。", "pong": "%s可以碰。", "pass": "先过这张%s。"}[action] % name
	elif action in ["self_win", "pass"]:
		if id != -1:
			return {}
		message = "可以自摸。" if action == "self_win" else "这次可以过。"
	else:
		if not legal.get(action + "_ids", []).has(id):
			return {}
		var observation := Observation.new(view)
		tile = observation.own_values.get(id, "")
		if not Catalog.valid_value(tile):
			return {}
		var name := _name(tile)
		match action:
			"ready": message = "打%s报听。" % name
			"concealed_kong": message = "%s可以暗杠。" % name
			"add_kong": message = "%s可以加杠。" % name
			"discard":
				var player: Dictionary = observation.players[observation.viewer_seat]
				var after: Array = player.concealed.duplicate()
				after.erase(tile)
				var distance := Shanten.shanten(after, player.melds)
				message = "先打" + name
				if distance > 0:
					message += "，至少还差%d张叫牌" % distance
				elif distance == 0:
					var seen := Ai.new(level)._seen_map(observation, observation.viewer_seat)
					if Rules.waiting_tiles(after, player.melds).any(func(value): return seen.get(value, 0) < 4):
						message += "，打完就能叫牌"
				message += "。"
	return {"prompt_id": legal.prompt_id, "action": action, "tile_id": id, "tile": tile, "message": message}

static func _name(tile: String) -> String:
	return tile.right(1) + str({"wan": "万", "tiao": "条", "tong": "筒"}[tile.left(-1)])
