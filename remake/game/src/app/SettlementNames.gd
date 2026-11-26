extends Control

const Badge := preload("res://src/app/PlayerBadge.gd")
const Result := preload("res://src/app/SettlementView.gd")
var badges: Array[Badge] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for anchor in [PRESET_CENTER_BOTTOM, PRESET_CENTER_RIGHT, PRESET_CENTER_TOP, PRESET_CENTER_LEFT]:
		var badge := Badge.new()
		add_child(badge)
		badge.set_anchors_and_offsets_preset(anchor)
		badge.grow_horizontal = GROW_DIRECTION_BOTH if anchor in [PRESET_CENTER_TOP, PRESET_CENTER_BOTTOM] else GROW_DIRECTION_END
		badge.grow_vertical = GROW_DIRECTION_BOTH
		if anchor == PRESET_CENTER_RIGHT:
			badge.grow_horizontal = GROW_DIRECTION_BEGIN
		elif anchor == PRESET_CENTER_TOP:
			badge.grow_vertical = GROW_DIRECTION_END
		elif anchor == PRESET_CENTER_BOTTOM:
			badge.grow_vertical = GROW_DIRECTION_BEGIN
		badges.append(badge)

func show_result(result: Dictionary, viewer: int) -> void:
	for position in 4:
		var seat := posmod(viewer - position, 4)
		var member: Dictionary = result.seats[seat].duplicate()
		member.score = result.scores[seat]
		var badge := badges[position]
		badge.show_player(member, PackedStringArray(), false,
			{"seat": seat, "player_id": member.player_id}, false)
		var meta: Dictionary = result.get("round_meta", {})
		var is_dealer: bool = seat == int(meta.get("dealer_seat", meta.get("dealer", -1)))
		var players_meta: Array = result.get("players", [])
		var is_ready: bool = seat < players_meta.size() and bool(players_meta[seat].get("ready", false))
		badge.set_role_seals(is_dealer, is_ready)
		badge.score_label.text = "%d 分 %s" % [int(member.score), Result.delta_text(int(result.ledger.deltas[seat]))]
		badge.set_mic_active(false)
		badge.tooltip_text = "本局结束时的累计分与本局增减"

func table_insets() -> Vector4:
	var row_height := 0.0
	for badge in badges:
		row_height = maxf(row_height, badge.get_combined_minimum_size().y)
	return Vector4(8, row_height * 2 + 16, 8, row_height + 8)

func arrange(table_rect: Rect2) -> void:
	# The narrow result pane has room above the table, not beside the tiles.
	for badge in badges:
		badge.set_anchors_preset(PRESET_TOP_LEFT)
		badge.size = badge.get_combined_minimum_size()
	badges[2].position = Vector2((size.x - badges[2].size.x) * 0.5, maxf(0, table_rect.position.y - badges[2].size.y * 2 - 12))
	badges[3].position = Vector2(0, maxf(badges[2].position.y + badges[2].size.y + 4, table_rect.position.y - badges[3].size.y - 4))
	badges[1].position = Vector2(size.x - badges[1].size.x, maxf(badges[2].position.y + badges[2].size.y + 4, table_rect.position.y - badges[1].size.y - 4))
	badges[0].position = Vector2((size.x - badges[0].size.x) * 0.5, minf(size.y - badges[0].size.y, table_rect.end.y + 4))
