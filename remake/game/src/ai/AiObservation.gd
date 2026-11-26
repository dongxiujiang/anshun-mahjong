extends RefCounted
## 模型只接收本家牌面、公开牌面与公开计分信息。

var viewer_seat: int
var players: Array = []
var own_values := {} # 实体牌 ID → 牌值，只含本家牌。
var wall_remaining: int
var chicken_multiplier: int
var charge_chickens: Dictionary
var last_discard: Dictionary
var draw_kind: String
var choices: Dictionary

func _init(view: Dictionary) -> void:
	viewer_seat = view.viewer_seat
	wall_remaining = view.wall_remaining
	chicken_multiplier = view.chicken_multiplier
	charge_chickens = view.charge_chickens.duplicate(true)
	last_discard = view.last_discard.duplicate()
	draw_kind = view.draw_kind
	choices = view.choices.duplicate(true)
	for row in view.players:
		var own: bool = row.seat == viewer_seat
		var player := {
			"seat": row.seat, "ready": row.ready, "discard_count": row.discard_count,
			"concealed": [], "melds": [], "discards": [], "discard_ids": [],
		}
		if own:
			for face in row.hand:
				own_values[face.id] = face.value
				player.concealed.append(face.value)
		for face in row.discards:
			player.discards.append(face.value)
			player.discard_ids.append(face.id)
		for meld in row.melds:
			var concealed: bool = meld.get("concealed", false)
			var visible: bool = own or not concealed or row.discard_count >= int(meld.get("formed_at", row.discard_count)) + 2
			player.melds.append({"kind": meld.kind, "concealed": concealed,
				"tile": meld.get("tile", "hidden0") if visible else "hidden0",
				"from_seat": meld.get("from_seat", -1) if visible else -1})
		players.append(player)

func values_for(action: String) -> Array:
	var values := []
	for id in _ids_for(action):
		if own_values.has(id) and not values.has(own_values[id]):
			values.append(own_values[id])
	return values

func id_for(action: String, value: String) -> int:
	for id in _ids_for(action):
		if own_values.get(id) == value:
			return id
	return -1

func _ids_for(action: String) -> Array:
	return choices.get(action + "_ids", []) if action in choices.actions else []

func is_charge_discard(seat: int, index: int) -> bool:
	var player: Dictionary = players[seat]
	var charge: Dictionary = charge_chickens.get(player.discards[index], {})
	return charge.get("owner", -1) == seat and charge.get("location", "") == "discard" \
		and charge.get("discard_id", -1) == player.discard_ids[index]
