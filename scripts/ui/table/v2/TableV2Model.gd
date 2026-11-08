class_name TableV2Model
extends RefCounted
const TILES := preload("res://scripts/core/Tiles.gd")
## RoundState -> 只读快照。视图层不再直接遍历 round.players。

static func flip_wall_index(round) -> int:
	if str(round.round_meta.get("flip_tile", "")) == "":
		return -1
	var index := int(round.round_meta.get("flip_wall_index", -1))
	if index in range(WallRing.N):
		return index
	if round.wall != null:
		return round.wall.peek_head_index()
	# An older remote result may only have the latest public head draw and
	# remaining stack counts. Recover the next occupied slot from those.
	var events: Array = round.visual_events
	for i in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[i]
		index = int(event.get("wall_index", -1))
		if event.get("type", "") != "draw" or event.get("kind", "") != "head" or index not in range(WallRing.N):
			continue
		for step in range(1, WallRing.N):
			var next := posmod(index + step, WallRing.N)
			for segment in WallRing.SEG.values():
				var offset := next - int(segment.start)
				if offset < 0 or offset >= int(segment.len):
					continue
				var counts: Array = round.wall_stacks.get(int(segment.seat), [])
				var slot := offset >> 1
				if int(segment.seat) in [1, 2]:
					slot = (int(segment.len) >> 1) - 1 - slot
				if slot in range(counts.size()) and int(counts[slot]) >= (2 if offset % 2 == 0 else 1):
					return next
				break
		break
	return -1

static func build(round, human_seat: int) -> Dictionary:
	var seats: Array = []
	for player in round.players:
		var charges: Array = []
		var timeline: Array = []
		var exposed: Array = []
		var melds_out: Array = []
		for index in player.discards.size():
			var charge: bool = round.is_charge_discard(player.seat, index)
			charges.append(charge)
			var card := str(player.discards[index])
			if not TILES.is_chicken(card): continue
			timeline.append({"kind": "charge" if charge else "ordinary", "tile": card,
				"order": int(player.discard_ids[index]) if index < player.discard_ids.size() else index})
			exposed.append(timeline.back().duplicate())
		for mi in player.melds.size():
			var meld: Dictionary = player.melds[mi]
			var shown := meld.duplicate(true)
			shown["revealed"] = round.is_meld_revealed(player.seat, mi)
			melds_out.append(shown)
			var exposed_kind := str(meld.get("kind", ""))
			exposed.append({"kind": "pung" if exposed_kind == "add_kong" else exposed_kind,
				"tile": str(meld.get("tile", "")), "meld_index": mi,
				"order": int(meld.get("formed_at", meld.get("after_discard", player.discard_count))),
				"add_kong": exposed_kind == "add_kong", "concealed": bool(meld.get("concealed", false)),
				"from_seat": int(meld.get("from_seat", -1)),
				"revealed": bool(shown.revealed)})
			if not TILES.is_chicken(str(meld.get("tile", ""))): continue
			var kind := str(meld.get("kind", ""))
			var formed := int(meld.get("formed_at", meld.get("after_discard", player.discard_count)))
			if kind == "add_kong":
				timeline.append({"kind": "pung", "tile": str(meld.get("tile", "")),
					"order": formed, "add_kong": true, "meld_index": mi})
			elif kind in ["pung", "kong"]:
				timeline.append({"kind": kind, "tile": str(meld.get("tile", "")),
					"order": formed, "meld_index": mi,
					"concealed": bool(meld.get("concealed", false)),
					"revealed": bool(shown.revealed)})
		timeline.sort_custom(func(a, b): return int(a.order) < int(b.order))
		exposed.sort_custom(func(a, b): return int(a.order) < int(b.order))
		seats.append({
			"seat": player.seat,
			"name": player.name_label,
			"is_human": player.is_human,
			"score": player.score,
			"is_dealer": player.is_dealer,
			"hand": player.concealed.duplicate(),
			"hand_count": player.concealed.size(),
			"just_drew": player.just_drew,
			"ready": player.ready,
			"discards": player.discards.duplicate(),
			"discard_ids": player.discard_ids.duplicate(),
			"discard_charge": charges,
			"red_timeline": timeline,
			"exposed_timeline": exposed,
			"melds": melds_out,
		})
	var wall_slots: Array = []
	if round.wall != null:
		for seat in 4:
			wall_slots.append(round.wall.wall_stack_slots(seat))
	else:
		for seat in 4:
			var slots: Array = []
			for count in round.wall_stacks.get(seat, []):
				slots.append([int(count) >= 2, int(count) >= 1])
			wall_slots.append(slots)
	var flip_tile := str(round.round_meta.get("flip_tile", ""))
	return {
		"phase": round.phase,
		"flip_tile": flip_tile,
		"flip_tiles": TILES.flip_related(flip_tile) if flip_tile != "" else [],
		"human_seat": human_seat,
		"dealer": int(round.dealer_seat),
		"turn": int(round.current_turn),
		"wall_slots": wall_slots,
		"wall_remaining": int(round.wall.remaining) if round.wall != null else 0,
		"die_red": int(round.round_meta.get("die", 1)),
		"die_white": int(round.round_meta.get("die_white", 1)),
		"seats": seats,
	}
