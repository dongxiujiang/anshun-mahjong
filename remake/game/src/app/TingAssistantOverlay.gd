extends Control
## 常驻叫牌胶囊（固定于本家姓名/分数上方，摸牌出牌不消失、改听实时更新）与手牌抬起已出张数轻提示。
## 严格仅基于本家可见手牌与场上已公开牌计算，复用权威 RuleEngine / WinScoring / Shanten，绝不读取暗手或牌墙。

const UI := preload("res://src/app/AppTheme.gd")
const Rules := preload("res://src/anshun/scoring/RuleEngine.gd")
const Win := preload("res://src/anshun/scoring/WinScoring.gd")
const Shanten := preload("res://src/anshun/scoring/Shanten.gd")
const Tiles := preload("res://src/anshun/scoring/Tiles.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")
const TileArt := preload("res://src/presentation/TileArt.gd")

var _popup := PanelContainer.new()
var _popup_label: Label
var _badge := PanelContainer.new()
var _badge_box := HBoxContainer.new()
var _toast := PanelContainer.new()
var _toast_label: Label
var _toast_tween: Tween

var _cache_key := ""
var _cache_seen := {}
var _cache_played := {}
var _cache_ready_waits := []
var _last_ting_waits := []
var _badge_signature := ""
var _badge_anchor := Rect2()
var _lifted_anchor := Vector2(-1.0, -1.0)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 14
	# 1. 手牌抬起时的精简已出计数胶囊（仅显示场上已打出张数，绝不在牌桌中央弹出长段出牌建议）
	_popup.mouse_filter = MOUSE_FILTER_IGNORE
	_popup.add_theme_stylebox_override("panel", UI.card(Color("#0d2820eb"), 10, 7, Color("#d4b163"), 1))
	_popup_label = UI.label("", 15, Color("#ffe8b0"))
	_popup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup.add_child(_popup_label)
	_popup.hide()
	add_child(_popup)
	# 2. 常驻叫牌胶囊（固定在玩家名字和分数正上方，摸牌/出牌持续显示，换听实时更新）
	_badge.mouse_filter = MOUSE_FILTER_IGNORE
	_badge.add_theme_stylebox_override("panel", UI.elevated_card(Color("#0d2a22eb"), 11, 7, Color("#cfa758"), 1, 5))
	_badge_box.mouse_filter = MOUSE_FILTER_IGNORE
	_badge_box.add_theme_constant_override("separation", 5)
	_badge.add_child(_badge_box)
	_badge.hide()
	add_child(_badge)
	# 3. 顶部轻提示自动淡出胶囊
	_toast.mouse_filter = MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", UI.card(Color("#122e26eb"), 14, 8, Color("#d9b96d"), 1))
	_toast_label = UI.label("", 16, Color("#f7e8be"))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	_toast.hide()
	add_child(_toast)
	resized.connect(_reposition)


func _exit_tree() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = null


func clear_all() -> void:
	_cache_key = ""
	_cache_seen.clear()
	_cache_played.clear()
	_cache_ready_waits.clear()
	_last_ting_waits.clear()
	_badge_signature = ""
	_popup.hide()
	_badge.hide()


func show_toast(message: String, seconds: float = 1.9) -> void:
	if message.is_empty():
		return
	_toast_label.text = message
	_toast.modulate = Color.WHITE
	_toast.show()
	_reposition()
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.28)
	_toast_tween.tween_callback(_toast.hide)


static func played_counts(round_view: Dictionary, viewer: int) -> Dictionary:
	## 仅统计牌桌上所有已打出弃牌与公开可见的碰/杠牌（不含本家手中暗牌，严禁偷看别家未亮暗杠）。
	var played := {}
	var players: Array = round_view.get("players", [])
	for p in players:
		var seat := int(p.get("seat", -1))
		for face in p.get("discards", []):
			var val := str(face.get("value", ""))
			if Catalog.valid_value(val):
				played[val] = int(played.get(val, 0)) + 1
		var dcount := int(p.get("discard_count", 0))
		for meld in p.get("melds", []):
			var hidden: bool = seat != viewer and bool(meld.get("concealed", false)) and dcount < int(meld.get("formed_at", dcount)) + 2
			if hidden:
				continue
			var val := str(meld.get("tile", ""))
			if Catalog.valid_value(val):
				var cnt := 3 if str(meld.get("kind", "")) == "pung" else 4
				played[val] = int(played.get(val, 0)) + cnt
	return played


static func visible_counts(round_view: Dictionary, viewer: int) -> Dictionary:
	var seen := played_counts(round_view, viewer)
	var players: Array = round_view.get("players", [])
	for p in players:
		if int(p.get("seat", -1)) == viewer:
			for face in p.get("hand", []):
				var val := str(face.get("value", ""))
				if Catalog.valid_value(val):
					seen[val] = int(seen.get(val, 0)) + 1
	return seen


static func waits_for_hand(concealed: Array, melds: Array, seen: Dictionary) -> Array:
	var waits := []
	if Shanten.shanten(concealed, melds) != 0:
		return waits
	for tile in Tiles.all_values():
		var pattern: Dictionary = Rules.hand_pattern(concealed + [tile], melds, tile)
		if not pattern.get("win", false):
			continue
		var info: Dictionary = Win._pattern_info(pattern)
		var label: String = str(info.get("label", "平胡")) if not info.is_empty() else "平胡"
		var score: int = int(info.get("score", 1)) if not info.is_empty() else 1
		var rem := maxi(0, 4 - int(seen.get(tile, 0)))
		waits.append({"tile": tile, "remaining": rem, "label": label, "score": score})
	waits.sort_custom(func(a, b):
		if a.score != b.score:
			return a.score > b.score
		if a.remaining != b.remaining:
			return a.remaining > b.remaining
		return a.tile < b.tile)
	return waits


static func analyze_discards(round_view: Dictionary, viewer: int) -> Dictionary:
	var players: Array = round_view.get("players", [])
	if viewer < 0 or viewer >= players.size():
		return {}
	var own: Dictionary = players[viewer]
	var hand: Array = own.get("hand", [])
	if hand.size() % 3 != 2:
		return {}
	var melds: Array = own.get("melds", [])
	var seen := visible_counts(round_view, viewer)
	var discard_ids: Array = round_view.get("choices", {}).get("discard_ids", [])
	var result := {}
	var checked := {}
	for face in hand:
		var id := int(face.get("id", -1))
		var val := str(face.get("value", ""))
		if not Catalog.valid_value(val) or checked.has(val):
			continue
		if not discard_ids.is_empty() and not discard_ids.has(id):
			continue
		checked[val] = true
		var after: Array = []
		var removed := false
		for item in hand:
			if not removed and int(item.get("id", -1)) == id:
				removed = true
				continue
			after.append(str(item.get("value", "")))
		var waits := waits_for_hand(after, melds, seen)
		if not waits.is_empty():
			var total := 0
			var best_score := 0
			var best_label := "平胡"
			for w in waits:
				total += int(w.remaining)
				if int(w.score) > best_score:
					best_score = int(w.score)
					best_label = str(w.label)
			result[val] = {"waits": waits, "total": total, "best_score": best_score, "best_label": best_label}
	return result


func sync_state(round_view: Dictionary, viewer: int, selected_id: int, enabled: bool, badge_anchor: Rect2 = Rect2(), lifted_point: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if not enabled or round_view.is_empty() or str(round_view.get("phase", "")) not in ["turn", "response", "ready_draw"]:
		clear_all()
		return
	var players: Array = round_view.get("players", [])
	if viewer < 0 or viewer >= players.size():
		clear_all()
		return
	_badge_anchor = badge_anchor
	_lifted_anchor = lifted_point
	var own: Dictionary = players[viewer]
	var hand: Array = own.get("hand", [])
	var key := "%s|%d|%d|%d|%d" % [str(round_view.get("prompt_id", -1)), viewer, hand.size(), own.get("melds", []).size(), int(own.get("discard_count", 0))]
	if key != _cache_key:
		_cache_key = key
		_cache_played = played_counts(round_view, viewer)
		_cache_seen = visible_counts(round_view, viewer)
		if hand.size() % 3 == 1:
			# 出牌后 / 非摸牌态：重新精确计算当前听牌；若换听则立即刷新，若破听则自动隐藏
			var vals := hand.map(func(f): return str(f.get("value", "")))
			_cache_ready_waits = waits_for_hand(vals, own.get("melds", []), _cache_seen)
			_last_ting_waits = _cache_ready_waits.duplicate(true)
		elif not _last_ting_waits.is_empty():
			# 摸牌态（14/11/8/5/2张）：持续保留听牌显示不闪烁不消失，同时刷新场上实时余张
			var refreshed := []
			for w in _last_ting_waits:
				var copy: Dictionary = w.duplicate()
				copy.remaining = maxi(0, 4 - int(_cache_seen.get(str(copy.tile), 0)))
				refreshed.append(copy)
			_last_ting_waits = refreshed
			_cache_ready_waits = refreshed
		else:
			_cache_ready_waits = []

	# 1. 常驻听牌胶囊（位于玩家名字和分数正上方）
	if not _cache_ready_waits.is_empty():
		var is_ready := bool(own.get("ready", false))
		var sig := "%s|%s" % [str(is_ready), JSON.stringify(_cache_ready_waits)]
		if sig != _badge_signature:
			_badge_signature = sig
			_rebuild_badge(_cache_ready_waits, is_ready)
		_badge.show()
	else:
		_badge_signature = ""
		_badge.hide()

	# 2. 手牌抬起时仅显示场上已打出该牌的张数，不在牌桌中央弹出出牌建议
	var selected_val := ""
	if selected_id >= 0:
		for face in hand:
			if int(face.get("id", -1)) == selected_id:
				selected_val = str(face.get("value", ""))
				break
	if selected_val.is_empty():
		_popup.hide()
	else:
		var count := int(_cache_played.get(selected_val, 0))
		_popup_label.text = "%s · 已出 %d 张" % [_tile_name(selected_val), count]
		_popup.show()
	_reposition()


func _clear_box(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _tile_chip(tile_value: String, remaining: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	var card := PanelContainer.new()
	card.mouse_filter = MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(28, 38)
	card.add_theme_stylebox_override("panel", UI.card(Color("#f3ebd6"), 3, 2, Color("#cfb98b"), 1))
	var tex := TileArt.face(tile_value)
	if tex != null:
		var icon := TextureRect.new()
		icon.mouse_filter = MOUSE_FILTER_IGNORE
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.add_child(icon)
	else:
		card.add_child(UI.label(_tile_name(tile_value), 11, Color("#1f2e26")))
	col.add_child(card)
	var rem_color := Color("#ff9885") if remaining == 0 else Color("#ffe294")
	var rem_label := UI.label("余%d" % remaining, 11, rem_color)
	rem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(rem_label)
	return col


func _rebuild_badge(waits: Array, is_ready: bool) -> void:
	_clear_box(_badge_box)
	var total := 0
	for w in waits:
		total += int(w.remaining)
	var lead := VBoxContainer.new()
	lead.mouse_filter = MOUSE_FILTER_IGNORE
	lead.alignment = BoxContainer.ALIGNMENT_CENTER
	lead.add_theme_constant_override("separation", 1)
	lead.add_child(UI.label("报听中" if is_ready else "听牌中", 13, Color("#ffe39b")))
	lead.add_child(UI.label("余 %d 张" % total, 12, Color("#8ceec2")))
	_badge_box.add_child(lead)
	var shown := mini(waits.size(), 5)
	for i in shown:
		var w: Dictionary = waits[i]
		_badge_box.add_child(_tile_chip(str(w.tile), int(w.remaining)))
	if waits.size() > shown:
		_badge_box.add_child(UI.label("+%d" % (waits.size() - shown), 12, UI.MUTED))


func _reposition() -> void:
	if size.x < 10 or size.y < 10:
		return
	if _badge.visible:
		_badge.size = _badge.get_combined_minimum_size()
		if _badge_anchor.has_area():
			var bx := clampf(_badge_anchor.position.x, 8.0, maxf(8.0, size.x - _badge.size.x - 8.0))
			var by := maxf(64.0, _badge_anchor.position.y - _badge.size.y - 6.0)
			_badge.position = Vector2(bx, by)
		else:
			_badge.position = Vector2(10.0, maxf(64.0, size.y - _badge.size.y - 76.0))
	if _popup.visible:
		_popup.size = _popup.get_combined_minimum_size()
		var px: float
		var py: float
		if _lifted_anchor.x >= 0.0 and _lifted_anchor.y >= 0.0:
			px = clampf(_lifted_anchor.x - _popup.size.x * 0.5, 12.0, maxf(12.0, size.x - _popup.size.x - 12.0))
			py = clampf(_lifted_anchor.y - _popup.size.y - 10.0, 64.0, maxf(64.0, size.y - _popup.size.y - 110.0))
		else:
			px = clampf((size.x - _popup.size.x) * 0.5, 12.0, maxf(12.0, size.x - _popup.size.x - 12.0))
			py = maxf(64.0, size.y - _popup.size.y - 146.0)
		_popup.position = Vector2(px, py)
	if _toast.visible:
		_toast.size = _toast.get_combined_minimum_size()
		_toast.position = Vector2((size.x - _toast.size.x) * 0.5, 10.0)


static func _tile_name(value: String) -> String:
	if not Catalog.valid_value(value):
		return ""
	return value.right(1) + str({"wan": "万", "tiao": "条", "tong": "筒"}[value.left(-1)])
