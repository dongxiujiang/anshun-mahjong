extends "res://scripts/ui/table/TableComponent.gd"
## Consumes authoritative events; owns presentation only, never waits in RoundState.
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const ANIMATION_LAYER := preload("res://scripts/ui/TableAnimationLayer.gd")
var _animation_layer
var _animation_busy := false
var _animation_last_id := 0
var _preview_last_id := 0
var _animation_queue: Array = []
var _skip_visual_once := false
var _session := ""
var _masked: Array[Control] = []
var _event := {}
var _opening := false
var _opening_speed_scale := 1.0
var _sorting := false
var _dealt := [0, 0, 0, 0]
## 开局实际拿到的牌，按拿牌顺序保存，用于测试校验。
var _dealt_cards := {0: [], 1: [], 2: [], 3: []}
## 分步实现期间：只打开当前步骤的动画，其余直接更新状态。
var animation_enabled := {
	"dice": true,
	"deal": false,
	"draw": false,
	"discard": false,
	"meld": false,
	"meld_reveal": false,
	"sort_hand": false,
	"win": true,
}
## 分步实现期间：骰子结束后暂停视觉推进，牌墙和手牌保持开局画面。
var pause_after_dice := false
## Seats whose persistent draw slot stays hidden until the draw flight lands.
## RoundState emits draw before state_update, so this closes the frame in which
## PlayerTileAreas could otherwise show the authoritative draw tile early.
var _held_draw_seats: Dictionary = {}
## Seats whose authoritative refresh must wait for the hand-discard animation.
## RoundState emits the event before state_update, so without this hold the
## final sorted hand would flash on screen before the old row can animate out.
var _held_refresh_seats: Dictionary = {}
# Discard flight + insert own a separate lane; claims and the next draw never
# wait for that lane. Only a subsequent action by the same seat reconciles it.
var _discard_tasks: Dictionary = {}
var _parallel_effects: Dictionary = {}
var _task_id := 0
var _tile_pool = preload("res://scripts/ui/TileViewPool.gd").new()

func has_pending() -> bool:
	return _native_actions_pending() or _animation_busy or not _animation_queue.is_empty() or not _discard_tasks.is_empty() or not _parallel_effects.is_empty()

func _native_actions_pending() -> bool:
	return is_instance_valid(table) and table._new_areas != null \
		and table._new_areas.native_presentation_pending()

func defers_discard_sound() -> bool:
	return DisplayServer.get_name() != "headless" and GameConfig.tile_motion_seconds() > 0.0 and not _animation_layer._skip

func dispose_pool() -> void:
	_tile_pool.clear()

func holds_meld_reveal(seat: int, index: int) -> bool:
	if DisplayServer.get_name() == "headless": return false
	var events: Array = _animation_queue.duplicate()
	if _animation_busy: events.append(_event)
	for effect in _parallel_effects.values(): events.append(effect.event)
	for event in events:
		if event.get("type", "") == "meld_reveal" and int(event.get("seat", -1)) == seat and int(event.get("index", -1)) == index:
			return true
	return false


func holds_seat_refresh(seat: int) -> bool:
	return _held_refresh_seats.has(seat)

func holds_draw_slot(seat: int) -> bool:
	return _held_draw_seats.has(seat)

func opening_active() -> bool:
	return _opening

func opening_deal_scale() -> float:
	return _opening_speed_scale

func sorting_active() -> bool:
	return _sorting

func dealt_count(seat: int) -> int:
	return int(_dealt[seat]) if seat in range(4) else 0

func dealt_cards(seat: int) -> Array:
	return _dealt_cards.get(seat, []).duplicate()

func _deal_display_order(cards: Array, indices: Array) -> Array:
	var entries: Array = []
	for i in cards.size():
		entries.append({"card": cards[i], "pos": i,
			"row": int(indices[i]) % 2 if i < indices.size() else 0})
	entries.sort_custom(func(a, b):
		if a.row == b.row: return a.pos < b.pos
		return a.row > b.row)
	var out: Array = []
	for e in entries: out.append(e.card)
	return out

func deal_sequence_active() -> bool:
	if _deal_animating or not _pending_test_deals.is_empty(): return true
	for seat in 4:
		if int(_dealt[seat]) < 13: return true
	return false

var _dice_pending := false
var _dice_gate_until := 0
var _pending_test_deals: Array = []
var _deal_animating := false
var _deal_tick_scheduled := false
var _deal_timeout_token := 0
var _deal_complete_callback := Callable()
var _draw_animating := false
var _draw_cards := {0: "", 1: "", 2: "", 3: ""}
var _insert_animating := false
var _meld_animating := false
var _pending_draw_after_meld := {}

func _apply_without_animation(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	if type == "deal":
		var seat := int(event.get("seat", 0))
		var cards: Array = event.get("cards", [])
		_dealt[seat] = int(_dealt[seat]) + cards.size()
		_dealt_cards[seat].append_array(cards)
	table.call_deferred("_refresh")

func visual_hold_active() -> bool:
	return pause_after_dice

func dice_gate_active() -> bool:
	return Time.get_ticks_msec() < _dice_gate_until

func _schedule_deal_tick() -> void:
	if _deal_tick_scheduled or table == null or not table.is_inside_tree(): return
	_deal_tick_scheduled = true
	var wait := maxi(0, _dice_gate_until - Time.get_ticks_msec()) / 1000.0
	table.get_tree().create_timer(wait).timeout.connect(_test_deal_tick)

func _test_deal_tick() -> void:
	_deal_tick_scheduled = false
	if not is_instance_valid(table) or not table.is_inside_tree():
		return
	if _pending_test_deals.is_empty():
		return
	# 自定义拿牌动画已经接管开局；不要再用旧 opening 锁触发取消动画。
	_opening = false
	if _deal_animating or Time.get_ticks_msec() < _dice_gate_until:
		_schedule_deal_tick()
		return
	if is_zero_approx(_opening_speed_scale):
		for packet in _pending_test_deals:
			var seat := int(packet.seat)
			_dealt[seat] += packet.cards.size()
			_dealt_cards[seat].append_array(_deal_display_order(packet.cards, packet.indices))
		_pending_test_deals.clear()
		table._refresh()
		return
	var event: Dictionary = _pending_test_deals.pop_front()
	if str(event.get("type", "")) == "deal" and table._new_areas != null \
			and table._new_areas.has_method("animate_deal_group") \
			and DisplayServer.get_name() != "headless":
		var deal_seat := int(event.get("seat", 0))
		var deal_cards: Array = event.get("cards", [])
		var deal_indices: Array = event.get("indices", [])
		var show_cards := _deal_display_order(deal_cards, deal_indices)
		_deal_animating = true
		_deal_timeout_token += 1
		var token := _deal_timeout_token
		var complete := func():
			if token != _deal_timeout_token: return
			_deal_timeout_token += 1
			_deal_complete_callback = Callable()
			_dealt[deal_seat] = int(_dealt[deal_seat]) + deal_cards.size()
			_dealt_cards[deal_seat].append_array(show_cards)
			_deal_animating = false
			table._refresh()
			if not _pending_test_deals.is_empty(): _schedule_deal_tick()
		_deal_complete_callback = complete
		var packet_seconds := (GameConfig.DEAL_FLIGHT_SECONDS + GameConfig.DEAL_RECENTER_SECONDS) * _opening_speed_scale
		var timeout: SceneTreeTimer = table.get_tree().create_timer(packet_seconds + 0.6)
		timeout.timeout.connect(_on_deal_timeout.bind(token))
		table._new_areas.animate_deal_group(deal_seat, deal_cards, deal_indices,
			int(_dealt[deal_seat]), complete, _opening_speed_scale)
	else:
		_apply_without_animation(event)
		_schedule_deal_tick()

func _on_deal_timeout(token: int) -> void:
	if token != _deal_timeout_token or not _deal_animating: return
	var callback := _deal_complete_callback
	_deal_complete_callback = Callable()
	if callback.is_valid(): callback.call()

func clear_dice() -> void:
	_dice_pending = false
	if is_instance_valid(_animation_layer):
		_animation_layer.clear_dice()
	if table != null and table._new_areas != null and table._new_areas.has_method("clear_dice_visual"):
		table._new_areas.clear_dice_visual()
	# 分步测试/旧层可能残留独立骰子节点，统一清理。
	if table != null and table.is_inside_tree():
		for node in table.find_children("*", "", true, false):
			if node.get_script() != null \
					and str(node.get_script().resource_path).ends_with("DiceView.gd"):
				node.queue_free()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not _deal_animating and not _pending_test_deals.is_empty() and now >= _dice_gate_until:
		_test_deal_tick()

func input_locked() -> bool:
	if table.round != null and table.round.phase == RoundState.Phase.DEALING: return true
	if _native_actions_pending(): return true
	if _opening or _sorting or _deal_animating or _draw_animating or _insert_animating or _meld_animating: return true
	var seat: int = table.human_seat
	# A response reads a discard, not the opponent's still-sorting hand.
	# For our turn, the draw/own meld must have finished before any button shows.
	if holds_draw_slot(seat): return true
	if table._selecting and holds_seat_refresh(seat): return true
	var events: Array = _animation_queue.duplicate()
	if _animation_busy: events.append(_event)
	for event in events:
		if int(event.get("seat", -1)) == seat and event.get("type", "") in ["draw", "meld"]:
			return true
	return false

func reset() -> void:
	cancel()
	_animation_last_id = 0
	_preview_last_id = 0
	_session = ""
	_skip_visual_once = false

func cancel(skip_next_event: bool = false) -> void:
	if _native_actions_pending() and table._new_areas.is_inside_tree():
		table._new_areas.recover_after_resume()
	var had_draw_holds := not _held_draw_seats.is_empty()
	var had_hand_holds := not _held_refresh_seats.is_empty() or _sorting
	if _sorting and is_instance_valid(table): table._seat_visual_keys.clear()
	if is_instance_valid(table):
		for seat in _held_refresh_seats: table._seat_visual_keys.erase(seat)
	_restore()
	for task in _discard_tasks.values():
		task.layer.cancel()
		task.layer.queue_free()
	_discard_tasks.clear()
	for effect in _parallel_effects.values():
		effect.layer.cancel()
		effect.layer.queue_free()
	_parallel_effects.clear()
	_animation_queue.clear()
	_animation_busy = false
	_event = {}
	_held_refresh_seats.clear()
	_held_draw_seats.clear()
	_opening = false
	_sorting = false
	_deal_animating = false
	_draw_animating = false
	_insert_animating = false
	_meld_animating = false
	_deal_timeout_token += 1
	_deal_complete_callback = Callable()
	_pending_test_deals.clear()
	_pending_draw_after_meld.clear()
	_draw_cards = {0: "", 1: "", 2: "", 3: ""}
	_dice_pending = false
	_dice_gate_until = 0
	_dealt = [0, 0, 0, 0]
	_dealt_cards = {0: [], 1: [], 2: [], 3: []}
	_skip_visual_once = skip_next_event
	if is_instance_valid(_animation_layer): _animation_layer.cancel()
	if (had_draw_holds or had_hand_holds) and is_instance_valid(table) and table.is_inside_tree():
		# Reconnects and explicit cancellation can interrupt a draw or a hand
		# movement before its completion callback. Rebuild once so hidden nodes and
		# partially moved persistent nodes cannot remain stuck.
		table.call_deferred("_refresh")

func recover_after_resume() -> void:
	# Mobile OSes can suspend Tweens indefinitely. Drop the interrupted visual
	# sequence, mark the authoritative opening as already presented, and let the
	# current RoundState snapshot become the new visual baseline.
	cancel()
	if table == null or table.round == null or table.round.players.size() != 4:
		return
	# The next live event belongs to this snapshot's session, even if none
	# of its historical events were replayed when opening the table.
	_session = table.round._presentation.session
	_animation_last_id = table.round.visual_event_id
	if table._new_areas != null: table._new_areas.recover_after_resume()
	for seat in 4:
		var cards: Array = table.round.players[seat].concealed
		var shown := mini(13, cards.size())
		# This is an already-dealt snapshot; a short hand after a meld must not
		# make deal_sequence_active() reopen the initial 13-tile deal gate.
		_dealt[seat] = 13
		_dealt_cards[seat] = cards.slice(0, shown)
	_opening = false
	_sorting = false
	_deal_animating = false
	_draw_animating = false
	_insert_animating = false
	_meld_animating = false
	_deal_timeout_token += 1
	_deal_complete_callback = Callable()
	_pending_test_deals.clear()
	_pending_draw_after_meld.clear()
	_draw_cards = {0: "", 1: "", 2: "", 3: ""}
	_dice_pending = false
	_dice_gate_until = 0
	table.call_deferred("_refresh")

func build() -> void:
	_animation_layer = ANIMATION_LAYER.new()
	_animation_layer.name = "AnimationLayer"
	_animation_layer.tile_pool = _tile_pool
	table.add_child(_animation_layer)

func _on_visual_event(event: Dictionary) -> void:
	if _animation_layer == null: return
	var incoming := str(event.get("session", ""))
	if incoming != "" and incoming != _session:
		if table._new_areas != null: table._new_areas._reset_round_visual_state()
		cancel()
		_animation_last_id = 0
		_session = incoming
	var event_id := int(event.get("id", 0))
	# Capture/review tools can inject local preview events without a round
	# session.  They must never advance the authoritative event cursor, or a
	# later network event with a small id would be mistaken for a duplicate.
	var authoritative_event := incoming != ""
	if authoritative_event:
		if event_id <= _animation_last_id: return
		_animation_last_id = event_id
	elif event_id > 0:
		if event_id <= _preview_last_id: return
		_preview_last_id = event_id
	if _skip_visual_once:
		_skip_visual_once = false
		return
	if event.get("fast_forward", false):
		recover_after_resume()
		return
	_dispatch_visual_event(event)

## Events enter this method only after receive-side deduplication. Deferred
## continuations must not consume their authoritative id a second time.
func _dispatch_visual_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if table._new_areas != null and table._new_areas.get("test_frozen") != null \
			and bool(table._new_areas.test_frozen):
		return
	if pause_after_dice and event_type != "dice":
		return
	if event_type == "discard" and _dice_pending and table.round != null \
			and int(event.get("seat", -1)) == int(table.round.dealer_seat):
		clear_dice()
	if event_type == "draw" and _meld_animating:
		_pending_draw_after_meld = event.duplicate(true)
		return
	if event_type == "meld" and DisplayServer.get_name() != "headless" \
			and table._new_areas != null and table._new_areas.has_method("animate_meld"):
		_meld_animating = true
		_animation_busy = true
		var meld_event := event.duplicate(true)
		table._new_areas.animate_meld(meld_event, func():
			_meld_animating = false
			_animation_busy = false
			table._refresh()
			if not _pending_draw_after_meld.is_empty():
				var pending := _pending_draw_after_meld
				_pending_draw_after_meld = {}
				_dispatch_visual_event(pending)
			table.call_deferred("_pump_visual_animation"))
		return
	if event_type == "draw" and DisplayServer.get_name() != "headless" \
			and table._new_areas != null and table._new_areas.has_method("animate_draw"):
		_draw_animating = true
		var draw_seat := int(event.get("seat", 0))
		var draw_card := str(event.get("tile", ""))
		_draw_cards[draw_seat] = draw_card
		var draw_index := int(event.get("wall_index", -1))
		table._new_areas.animate_draw(draw_seat, draw_card, draw_index, func():
			_draw_animating = false
			table._update_interactivity()
			table.call_deferred("_refresh"))
		return
	if event_type == "discard" and DisplayServer.get_name() != "headless" \
			and table._new_areas != null and table._new_areas.has_method("animate_draw_insert"):
		var discard_seat := int(event.get("seat", 0))
		if int(_pending_draw_after_meld.get("seat", -1)) == discard_seat:
			_pending_draw_after_meld.clear()
		var from_draw := bool(event.get("discard_from_draw", false))
		var draw_card := str(event.get("draw_tile", _draw_cards.get(discard_seat, "")))
		# Older servers also masked an empty draw after a pung as hidden0.
		if int(event.get("drawn_source_index", 0)) < 0: draw_card = ""
		if from_draw:
			table._new_areas.animate_draw_discard(discard_seat, func():
				_draw_cards[discard_seat] = ""
				table._update_interactivity()
				table.call_deferred("_refresh"), str(event.get("tile", "")))
			return
		if draw_card != "":
			_insert_animating = true
			table._new_areas.animate_draw_insert(discard_seat, str(event.get("tile", "")),
				draw_card, func():
					_insert_animating = false
					_draw_cards[discard_seat] = ""
					table._update_interactivity()
					table.call_deferred("_refresh"), int(event.get("discard_index", -1)),
				event.get("hand_slot_map", {}))
			return
		# 碰牌后的出牌没有摸牌位。第一段让选中的旧牌飞向弃牌区，
		# 第二段只平移其余手牌补位，不能整手重建后从左上角刷新。
		if bool(event.get("discard_from_hand", true)) \
				and table._new_areas.has_method("animate_hand_discard"):
			_insert_animating = true
			table._new_areas.animate_hand_discard(discard_seat,
				str(event.get("tile", "")), int(event.get("discard_index", -1)), func():
					_insert_animating = false
					table._update_interactivity()
					table.call_deferred("_refresh"))
			return
	if event_type == "deal_batch" and table._new_areas != null \
			and table._new_areas.has_method("animate_deal_group"):
		var deals: Array = event.get("deals", [])
		for deal in deals:
			_pending_test_deals.append({"type": "deal", "seat": deal.get("seat", 0),
				"cards": deal.get("cards", []), "indices": deal.get("indices", [])})
		_schedule_deal_tick()
		return
	if not bool(animation_enabled.get(event_type, true)):
		# 测试发牌统一排队：骰子停稳后逐组做拿牌动画。
		if event_type == "deal":
			_pending_test_deals.append(event)
			return
		_apply_without_animation(event)
		return
	var copy := event.duplicate(true)
	if event.get("type", "") == "dice":
		# 骰子固定在设计画布正中心，与牌桌缩放/偏移无关。
		copy["center_global"] = _animation_layer.get_global_transform() * UI.LANDSCAPE_CENTER
	if event.get("type", "") == "dice":
		_dice_pending = true
		_dice_gate_until = Time.get_ticks_msec() + int(
			(UI.DICE_DURATION + GameConfig.OPENING_DICE_HOLD_SECONDS) * 1000.0)
	if event.get("type", "") == "dice" and DisplayServer.get_name() != "headless":
		_opening = true
		# 联机使用房主设置的开局速度，服务器和所有客户端必须同速，
		# 否则一方动画结束、另一方还在理牌，就会出现空等。
		var speed := str(table.round.opening_speed) if table.round != null else GameConfig.opening_speed_key()
		_opening_speed_scale = GameConfig.opening_deal_scale(speed)
	var seat := int(event.get("seat", 0))
	if event.get("type", "") in ["draw", "meld", "discard"]:
		_finish_seat_discard(seat)
	if event.get("type", "") == "draw":
		# Set this before state_update.  The refresh that follows will create the
		# persistent node but PlayerTileAreas will keep it invisible until the
		# temporary flying tile reaches the same slot.
		_held_draw_seats[seat] = int(_held_draw_seats.get(seat, 0)) + 1
	if event.get("type", "") == "discard":
		# The authority may run faster than an observer's UI. Retire superseded
		# own draws/melds without delaying the real discard or rebuilding its source.
		if _animation_busy and int(_event.get("seat", -1)) == seat and _event.get("type", "") in ["draw", "meld"]:
			_animation_layer.finish_now()
		_animation_queue = _animation_queue.filter(func(pending): return not (int(pending.get("seat", -1)) == seat and pending.get("type", "") in ["draw", "meld"]))
		_held_draw_seats.erase(seat)
		var discard_tile := str(event.get("tile", ""))
		var from_draw := bool(event.get("discard_from_draw", false))
		copy["from"] = _animation_target_for_seat(seat) if from_draw else _discard_origin(seat, discard_tile, int(event.get("discard_index", -1)))
		if table._new_areas != null and table._new_areas.has_method("hand_source_global"):
			var v2_from := Vector2.ZERO
			if from_draw:
				v2_from = table._new_areas.draw_source_global(seat)
			else:
				v2_from = table._new_areas.hand_source_global(seat, int(event.get("discard_index", -1)))
			if v2_from != Vector2.ZERO:
				copy["from"] = _animation_layer.get_global_transform().affine_inverse() * v2_from
		copy["from_unit"] = table._hand_tile_unit(seat)
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(seat)]
		if not from_draw and int(event.get("discard_index", -1)) >= 0:
			copy["discard_from_hand"] = true
			copy["draw_from"] = _origin(table.draw_box[seat], str(event.get("draw_tile", "")))
			copy["hand_snapshot"] = _hand_snapshot(seat)
			# Hold the rendered old row while RoundState publishes its new
			# concealed array.  The animation must start from these exact nodes.
			_held_refresh_seats[seat] = int(_held_refresh_seats.get(seat, 0)) + 1
		# Materialize only public zones now: a following claim can remove this
		# discard before the deferred pump. Preserve its real landing coordinates.
		table._prepare_exposed_layouts()
		table._player_tile_areas._refresh_exposed(seat)
		table._player_tile_areas._refresh_discards(seat)
		copy["landing_destinations"] = _destinations(copy)
		if table._new_areas != null and table._new_areas.has_method("discard_target_global"):
			var target: Vector2 = table._new_areas.discard_target_global(seat, int(event.get("discard_id", -1)))
			if target != Vector2.ZERO:
				copy["landing_destinations"] = [{
					"to": target,
					"from": Vector2(copy.get("from", target)),
					"tile": discard_tile,
					"unit": table._hand_tile_unit(seat),
					"rotation": UI.ROTATIONS[table._relative_seat(seat)],
				}]
	elif event.get("type", "") == "meld" and event.has("source"):
		copy["from"] = _discard_visual_origin(int(event.get("source", -1)), str(event.get("tile", "")), int(event.get("source_discard_id", -1)))
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(int(event.get("source", -1)))] if int(event.get("source", -1)) in range(4) else UI.ROTATIONS[table._relative_seat(seat)]
		# The authority removes the two/three matching hand tiles before emitting
		# the meld event.  Capture their old screen positions before state_update
		# rebuilds the hand, so the visual can show the physical take-and-place.
		copy["meld_hand_snapshot"] = _hand_snapshot(seat, true)
	elif event.get("type", "") == "meld":
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(seat)]
		copy["meld_hand_snapshot"] = _hand_snapshot(seat, true)
	if copy.get("type", "") == "meld" and table._new_areas != null \
			and table._new_areas.has_method("meld_tile_global"):
		var v2_from := Vector2.ZERO
		if event.has("source"):
			v2_from = table._new_areas.discard_target_global(int(event.get("source", -1)),
				int(event.get("source_discard_id", -1)))
		else:
			var hand_indices: Array = event.get("hand_indices", [])
			if not hand_indices.is_empty():
				v2_from = table._new_areas.hand_source_global(seat, int(hand_indices[0]))
		if v2_from != Vector2.ZERO:
			copy["from"] = _animation_layer.get_global_transform().affine_inverse() * v2_from
		var slot := 3 if str(event.get("kind", "")) == "add_kong" else -1
		var target: Vector2 = table._new_areas.meld_tile_global(seat, int(event.get("index", -1)), slot)
		if target != Vector2.ZERO:
			copy["landing_destinations"] = [{
				"to": target,
				"from": Vector2(copy.get("from", target)),
				"tile": str(event.get("tile", "")),
				"unit": table._hand_tile_unit(seat),
				"rotation": UI.ROTATIONS[table._relative_seat(seat)],
			}]
	if copy.get("type", "") == "meld" and copy.has("source"):
		_claim_discard(copy)
	if copy.get("type", "") == "discard":
		if table._new_areas != null:
			# V2 自己处理弃牌飞行；旧 DiscardLane 绝不能启动。
			table.call_deferred("_refresh")
			table._update_interactivity()
			return
		copy["destinations"] = copy.get("landing_destinations", [])
		if copy.get("discard_from_hand", false): _prepare_hand_discard_motion(copy)
		_start_discard(copy)
		return
	_animation_queue.append(copy)
	table._update_interactivity()
	refresh_masks()
	table.call_deferred("_pump_visual_animation")

func _pump_visual_animation() -> void:
	if _animation_busy or _animation_queue.is_empty() or _animation_layer == null: return
	_event = _animation_queue.pop_front()
	if _event.get("type", "") == "deal_batch":
		var deals: Array = _event.get("deals", [])
		# Reverse insertion keeps the original clockwise deal order.
		for index in range(deals.size() - 1, -1, -1):
			var deal: Dictionary = deals[index]
			_animation_queue.push_front({"type": "deal", "seat": deal.get("seat", 0),
				"cards": deal.get("cards", []), "indices": deal.get("indices", [])})
		_pump_visual_animation()
		return
	_animation_busy = true
	if _event.get("type", "") == "dice" and table._new_areas != null \
			and table._new_areas.has_method("animate_dice"):
		var dice_value := int(_event.get("value", 1))
		var dice_white := int(_event.get("white", _event.get("die_white", 1)))
		table._new_areas.animate_dice(dice_value, dice_white)
		_event = {}
		_animation_busy = false
		table.call_deferred("_pump_visual_animation")
		return
	# V2 接管牌桌后，其余牌动画由 V2 负责。
	if table._new_areas != null and _event.get("type", "") != "dice":
		_apply_without_animation(_event)
		_event = {}
		_animation_busy = false
		table.call_deferred("_pump_visual_animation")
		return
	if _event.get("type", "") == "dice" and is_instance_valid(_animation_layer):
		_animation_layer.show()
	if _event.get("type", "") == "dice":
		_opening = DisplayServer.get_name() != "headless"
	var seat := int(_event.get("seat", 0))
	_event["to"] = _animation_target_for_seat(seat)
	if not _event.has("from"):
		_event["from"] = _source_for_event(_event)
	_event["badge_at"] = table._table_center() + [Vector2(0,170), Vector2(250,0), Vector2(0,-170), Vector2(-250,0)][table._relative_seat(seat)]
	_event["destinations"] = _event.get("landing_destinations", _destinations(_event))
	if _event.get("type", "") == "discard" and bool(_event.get("discard_from_hand", false)):
		_prepare_hand_discard_motion(_event)
	if _event.get("type", "") == "draw" and seat != table.human_seat: _event["tile"] = ""
	if _event.get("type", "") == "discard":
		var discard := _event
		_event = {}
		_animation_busy = false
		_start_discard(discard)
		table.call_deferred("_pump_visual_animation")
		return
	if _event.get("type", "") in ["ready", "meld_reveal"]:
		var effect := _event
		_event = {}
		_animation_busy = false
		_start_parallel_effect(effect)
		table.call_deferred("_pump_visual_animation")
		return
	if _opening and _event.get("type", "") == "deal": _event["speed_scale"] = _opening_speed_scale
	refresh_masks()
	_animation_layer.play(_event, Callable(table, "_on_visual_animation_finished"))

func _tiles_in(node: Node) -> Array[TileView]:
	var tiles: Array[TileView] = []
	for child in node.get_children():
		if child is TileView: tiles.append(child)
		else: tiles.append_array(_tiles_in(child))
	return tiles

func _tile_with_concealed_index(box: Control, source_index: int) -> TileView:
	if box == null or source_index < 0: return null
	for tile in _tiles_in(box):
		if int(tile.get_meta("concealed_index", -1)) == source_index:
			return tile
	return null

func _position(node: Control) -> Vector2:
	return _animation_layer.get_global_transform().affine_inverse() * node.global_position

func _origin(box: Control, card: String, discard_id: int = -1) -> Vector2:
	var tiles := _tiles_in(box)
	if discard_id >= 0:
		for tile in tiles:
			if int(tile.get_meta("discard_id", -1)) == discard_id:
				return _position(tile)
	for tile in tiles:
		if tile.tile == card and tile.face_up: return _position(tile)
	return _position(tiles.back()) if not tiles.is_empty() else table._table_center()

func _hand_snapshot(seat: int, include_draw: bool = false) -> Array:
	var result: Array = []
	if seat < 0 or seat >= table.hand_box.size(): return result
	var tiles := _tiles_in(table.hand_box[seat])
	if include_draw: tiles.append_array(_tiles_in(table.draw_box[seat]))
	for tile in tiles:
		var source_index := int(tile.get_meta("concealed_index", -1))
		if source_index < 0: continue
		result.append({
			"index": source_index,
			"from": _position(tile),
			"tile": tile.tile if tile.face_up else "",
			"unit": tile.unit,
			"rotation": tile.get_global_transform().get_rotation() - _animation_layer.get_global_transform().get_rotation()
		})
	return result

func _discard_origin(seat: int, card: String, concealed_index: int = -1) -> Vector2:
	if seat < 0 or seat >= 4 or seat >= table.hand_box.size():
		return table._table_center()
	var tiles := _tiles_in(table.hand_box[seat]) + _tiles_in(table.draw_box[seat])
	if concealed_index >= 0:
		for tile in tiles:
			if int(tile.get_meta("concealed_index", -1)) == concealed_index:
				return _position(tile)
	# Prefer the separate draw slot only while the snapshot still identifies this
	# card as the tile just drawn.  A normal discard should fall back to the hand
	# row; using _animation_target_for_seat() here would incorrectly send it from
	# the draw slot after a late network refresh.
	var prefer_draw := false
	if table.round != null and seat < table.round.players.size():
		prefer_draw = str(table.round.players[seat].just_drew) == card
	if prefer_draw:
		for tile in _tiles_in(table.draw_box[seat]):
			if tile.face_up and tile.tile == card:
				return _position(tile)
	for tile in _tiles_in(table.hand_box[seat]):
		if tile.face_up and tile.tile == card:
			return _position(tile)
	if not prefer_draw:
		for tile in _tiles_in(table.draw_box[seat]):
			if tile.face_up and tile.tile == card:
				return _position(tile)
	# A late snapshot can replace the old hand before a visual event is handled.
	# Keep the fallback in the same visual region even when the exact source tile
	# is gone.  This is presentation-only and never changes the authoritative
	# discard index.
	var draw_tiles := _tiles_in(table.draw_box[seat])
	if prefer_draw and not draw_tiles.is_empty(): return _position(draw_tiles[0])
	if not tiles.is_empty():
		return _position(tiles[0])
	return _hand_animation_target_for_seat(seat)

func _discard_visual_origin(seat: int, card: String, discard_id: int = -1) -> Vector2:
	if seat < 0 or seat >= 4:
		return table._table_center()
	var tiles := _tiles_in(table.chicken_box[seat]) + _tiles_in(table.discard_scroll[seat])
	if discard_id >= 0:
		for tile in tiles:
			if int(tile.get_meta("discard_id", -1)) == discard_id:
				return _position(tile)
	for tile in tiles:
		if tile.tile == card and tile.face_up:
			return _position(tile)
	if not tiles.is_empty():
		return _position(tiles.back())
	if seat >= 0 and seat < 4 and is_instance_valid(table.discard_scroll[seat]):
		var river: Control = table.discard_scroll[seat]
		var center_global: Vector2 = river.global_position + river.size / 2.0
		return _animation_layer.get_global_transform().affine_inverse() * center_global
	return table._table_center()

func _targets(event: Dictionary) -> Array[TileView]:
	var seat := int(event.get("seat", 0))
	var type := str(event.get("type", ""))
	if type == "draw":
		if table._new_areas != null and table._new_areas.get("draw_boxes") != null:
			return _tiles_in(table._new_areas.draw_boxes[seat])
		return _tiles_in(table.draw_box[seat])
	if type in ["meld", "meld_reveal"]:
		var group: Array[TileView] = []
		for tile in _tiles_in(table.meld_box[seat]):
			if int(tile.get_meta("meld_index", -1)) == int(event.get("index", -2)):
				if type == "meld" and event.get("kind", "") == "add_kong" and int(tile.get_meta("meld_slot", -1)) != 3: continue
				group.append(tile)
		return group
	if type == "discard":
		var candidates := _tiles_in(table.chicken_box[seat]) + _tiles_in(table.discard_scroll[seat])
		for index in range(candidates.size() - 1, -1, -1):
			var candidate: TileView = candidates[index]
			if event.has("discard_id") and int(candidate.get_meta("discard_id", -1)) == int(event.get("discard_id", -2)):
				return [candidate]
			if not event.has("discard_id") and candidate.tile == str(event.get("tile", "")) and bool(candidate.get_meta("charge_chicken", false)) == bool(event.get("charge", false)): return [candidate]
	return []

func _destinations(event: Dictionary) -> Array:
	var result: Array = []
	var type := str(event.get("type", ""))
	var seat := int(event.get("seat", 0))
	if type == "meld" and table._new_areas != null \
			and table._new_areas.has_method("meld_tile_global"):
		var slot := 3 if str(event.get("kind", "")) == "add_kong" else -1
		var target_global: Vector2 = table._new_areas.meld_tile_global(seat,
			int(event.get("index", -1)), slot)
		if target_global != Vector2.ZERO:
			var layer_inv: Transform2D = _animation_layer.get_global_transform().affine_inverse()
			return [{
				"to": layer_inv * target_global,
				"from": Vector2(event.get("from", layer_inv * target_global)),
				"tile": str(event.get("tile", "")),
				"unit": table._hand_tile_unit(seat),
				"rotation": UI.ROTATIONS[table._relative_seat(seat)],
			}]
	if type == "deal":
		var cards: Array = event.get("cards", [])
		var indices: Array = event.get("indices", [])
		for index in cards.size():
			# Opening hands are rendered in physical deal order.  The target is a
			# deterministic empty-hand slot, so the animation never needs a masked
			# copy of the final sorted hand underneath it.
			var count := int(_dealt[seat]) + index
			var to := _opening_hand_slot_target(seat, count)
			var from := Vector2(event.get("from", _source_for_event(event))) + Vector2(index * 8.0, -index * 5.0)
			if index < indices.size() and table._new_areas != null:
				from = table._new_areas.wall_center_for_index(int(indices[index]))
			result.append({"to": to, "from": from, "tile": cards[index] if seat == table.human_seat else "", "unit": table._hand_tile_unit(seat), "rotation": UI.ROTATIONS[table._relative_seat(seat)]})
	else:
		var targets := _targets(event)
		var hand_origins: Array = []
		if type == "meld":
			var meld_card := str(event.get("tile", ""))
			for item in event.get("meld_hand_snapshot", []):
				var item_card := str(item.get("tile", ""))
				var indices: Array = event.get("hand_indices", [])
				if (indices.has(int(item.get("index", -1))) if not indices.is_empty() else ((meld_card != "" and item_card == meld_card) or (meld_card == "" and item_card == ""))):
					hand_origins.append(item)
			# A hidden opponent hand has no tile names.  Its rightmost old tiles
			# still give us a stable physical origin without leaking their values.
			if hand_origins.is_empty(): hand_origins = event.get("meld_hand_snapshot", []).duplicate()
		var source_slot := -1
		if type == "meld" and event.has("source") and str(event.get("kind", "")) in ["kong", "pung"]:
			for index in targets.size():
				if int(targets[index].get_meta("meld_sideways", -1)) == int(targets[index].get_meta("meld_slot", -2)):
					source_slot = index
					break
			if source_slot < 0 and not targets.is_empty(): source_slot = targets.size() - 1
		for index in targets.size():
			var tile: TileView = targets[index]
			var card := str(event.get("tile", ""))
			if type == "draw" and seat != table.human_seat: card = ""
			var to := _position(tile)
			if type == "draw" and table._new_areas != null:
				var board_global: Vector2 = table._new_areas.get_global_transform() * table._new_areas.draw_slot_center(seat)
				to = _animation_layer.get_global_transform().affine_inverse() * board_global
			var origin := Vector2(event.get("from", table._table_center()))
			var origin_rotation := float(event.get("from_rotation", tile.get_global_transform().get_rotation() - _animation_layer.get_global_transform().get_rotation()))
			if type == "meld" and index == source_slot and event.has("source"):
				origin = Vector2(event.get("from", origin))
			elif type == "meld" and not hand_origins.is_empty():
				var hand_item: Dictionary = hand_origins.pop_back()
				origin = Vector2(hand_item.get("from", origin))
				origin_rotation = float(hand_item.get("rotation", origin_rotation))
			result.append({"to": to, "from": origin, "tile": card, "unit": tile.unit, "rotation": tile.get_global_transform().get_rotation() - _animation_layer.get_global_transform().get_rotation(), "from_rotation": origin_rotation})
	return result

func _source_for_event(event: Dictionary) -> Vector2:
	var type := str(event.get("type", ""))
	var seat := int(event.get("seat", 0))
	if type in ["deal", "draw"] and seat in range(4):
		# 从这张牌实际所在的牌墙块位置飞出。
		if event.has("wall_index") and table._new_areas != null:
			return table._new_areas.wall_center_for_index(int(event.wall_index))
		if type == "draw" and str(event.get("kind", "head")) == "tail":
			var relative: int = posmod(table._relative_seat(seat) + 2, 4)
			return Vector2(UI.ANIMATION_TARGETS[relative])
		return Vector2(UI.ANIMATION_TARGETS[table._relative_seat(seat)])
	return table._table_center()

func _prepare_hand_discard_motion(event: Dictionary) -> void:
	var seat := int(event.get("seat", 0))
	var source_index := int(event.get("discard_index", -1))
	var drawn_hand_index := int(event.get("drawn_hand_index", -1))
	var row_count := int(event.get("hand_row_count", 0))
	var slot_map: Dictionary = event.get("hand_slot_map", {})
	var snapshot: Array = event.get("hand_snapshot", [])
	var discard_node: TileView = _tile_with_concealed_index(table.hand_box[seat], source_index)
	var drawn_source_index := int(event.get("drawn_source_index", -1))
	var draw_node: TileView = _tile_with_concealed_index(table.draw_box[seat], drawn_source_index)
	event["discard_node"] = discard_node
	event["draw_node"] = draw_node
	if row_count <= 0: row_count = snapshot.size()
	if drawn_source_index < 0:
		# A post-pung discard has no draw to insert, but still closes its hole.
		row_count = maxi(0, snapshot.size() - 1)
		event["hand_row_count"] = row_count
		slot_map = {}
		for item in snapshot:
			var old_index := int(item.get("index", -1))
			if old_index != source_index: slot_map[old_index] = slot_map.size()
	var moves: Array = []
	for item in snapshot:
		var old_index := int(item.get("index", -1))
		if old_index < 0 or old_index == source_index or old_index == drawn_source_index:
			continue
		var final_slot := _slot_map_value(slot_map, old_index)
		if final_slot < 0: continue
		moves.append({
			"node": _tile_with_concealed_index(table.hand_box[seat], old_index),
			"old_index": old_index,
			"slot": final_slot,
			"from": item.get("from", table._table_center()),
			"to": _hand_slot_target(seat, final_slot, row_count),
			"tile": str(item.get("tile", "")),
			"unit": float(item.get("unit", table._hand_tile_unit(seat))),
			"rotation": float(item.get("rotation", UI.ROTATIONS[table._relative_seat(seat)]))
		})
	event["hand_moves"] = moves
	event["hand_move_required"] = moves.any(func(data): return not Vector2(data.from).is_equal_approx(Vector2(data.to)))
	# The real drawn tile is now part of the hand snapshot.  Compute its final
	# sorted slot in the same coordinate system used by PlayerTileAreas.
	if drawn_hand_index < 0:
		event["hand_insert"] = {}
		return
	var unit: float = table._hand_tile_unit(seat)
	var target: Vector2 = _hand_slot_target(seat, drawn_hand_index, row_count)
	var reveal: bool = seat == table.human_seat
	event["hand_insert"] = {
		"from": event.get("draw_from", table._table_center()),
		"to": target,
		"tile": str(event.get("draw_tile", "")) if reveal else "",
		"unit": unit,
		"rotation": UI.ROTATIONS[table._relative_seat(seat)],
		"from_unit": table._hand_tile_unit(seat),
		"source_node": draw_node
	}

func _slot_map_value(slot_map: Dictionary, source_index: int) -> int:
	if slot_map.has(source_index): return int(slot_map[source_index])
	var key := str(source_index)
	return int(slot_map[key]) if slot_map.has(key) else -1

func _hand_slot_target(seat: int, slot: int, count: int) -> Vector2:
	if seat < 0 or seat >= table.seat_roots.size() or count <= 0: return table._table_center()
	var local := _hand_slot_local_target(seat, slot, count)
	var global_target: Vector2 = table.seat_roots[seat].get_global_transform() * local
	return _animation_layer.get_global_transform().affine_inverse() * global_target

func _hand_slot_local_target(seat: int, slot: int, count: int) -> Vector2:
	if seat < 0 or seat >= table.seat_roots.size() or count <= 0: return Vector2.ZERO
	var unit: float = table._hand_tile_unit(seat)
	var width := TileView.BASE_W * unit
	var span := maxf(0.0, count * (width + UI.TILE_GAP) - UI.TILE_GAP)
	var right := (span + UI.DRAW_GAP + width) / 2.0
	var hand_x := right - width - UI.DRAW_GAP - span
	return Vector2(hand_x + slot * (width + UI.TILE_GAP), float(table._seat_metrics(seat).hand_y))

func _opening_hand_slot_local(seat: int, slot: int) -> Vector2:
	if seat < 0 or seat >= table.seat_roots.size(): return Vector2.ZERO
	var layout: Dictionary = table._hand_layout(seat)
	var unit: float = table._hand_tile_unit(seat)
	var width := TileView.BASE_W * unit
	return Vector2(float(layout.get("hand_x", 0.0)) + slot * (width + UI.TILE_GAP), float(table._seat_metrics(seat).hand_y))

func _opening_hand_slot_target(seat: int, slot: int) -> Vector2:
	# 终点必须直接取新牌区真实手牌槽中心，不能再用旧 seat_roots 动态布局。
	if table._new_areas != null:
		var board_local: Vector2 = table._new_areas.hand_slot_center(seat, slot)
		var board_global: Vector2 = table._new_areas.get_global_transform() * board_local
		return _animation_layer.get_global_transform().affine_inverse() * board_global
	var local := _opening_hand_slot_local(seat, slot)
	if seat < 0 or seat >= table.seat_roots.size(): return table._table_center()
	var global_target: Vector2 = table.seat_roots[seat].get_global_transform() * local
	return _animation_layer.get_global_transform().affine_inverse() * global_target

func _all_opening_tiles_dealt() -> bool:
	if table.round == null or table.round.players.size() != 4: return false
	for seat in 4:
		if int(_dealt[seat]) < 13: return false
	return true

func _sort_destinations() -> Array:
	var result: Array = []
	for seat in 4:
		if seat >= table.hand_box.size() or seat >= table.round.players.size(): continue
		var player: PlayerState = table.round.players[seat]
		var entries: Array = []
		for tile in _tiles_in(table.hand_box[seat]):
			var source_index := int(tile.get_meta("concealed_index", -1))
			if source_index < 0 or source_index >= player.concealed.size(): continue
			entries.append({"node": tile, "source_index": source_index, "card": str(player.concealed[source_index])})
		entries.sort_custom(func(a, b):
			var av := Tiles.value_index(str(a.get("card", "")))
			var bv := Tiles.value_index(str(b.get("card", "")))
			return int(a.get("source_index", 0)) < int(b.get("source_index", 0)) if av == bv else av < bv)
		for slot in entries.size():
			var item: Dictionary = entries[slot]
			var tile: TileView = item.get("node")
			result.append({
				"node": tile,
				"to": _opening_hand_slot_local(seat, slot),
				"rotation": 0.0,
				"delay": float(slot) * UI.SORT_TILE_STAGGER
			})
	return result

func _start_sorting_animation() -> void:
	if _sorting: return
	_sorting = true
	_event = {"type": "sort_hand", "destinations": _sort_destinations()}
	if _opening: _event["speed_scale"] = _opening_speed_scale
	_animation_busy = true
	table._update_interactivity()
	_animation_layer.play(_event, Callable(table, "_on_visual_animation_finished"))

func refresh_masks() -> void:
	_restore()
	if DisplayServer.get_name() == "headless": return
	var events: Array = _animation_queue.duplicate()
	if _animation_busy: events.append(_event)
	for effect in _parallel_effects.values():
		if effect.event.get("type", "") == "meld_reveal":
			for tile in _targets(effect.event): _mask(tile)
	for task in _discard_tasks.values():
		var event: Dictionary = task.event
		if not task.landed and not event.get("claimed", false):
			for tile in _targets(event): _mask(tile)
		var source_node = event.get("discard_node")
		if is_instance_valid(source_node): _mask(source_node)
	for event in events:
		if event.get("type", "") in ["draw", "discard", "meld"]:
			for tile in _targets(event): _mask(tile)
		if event.get("type", "") == "meld_reveal" and _animation_busy and event == _event:
			for tile in _targets(event): _mask(tile)

func _start_parallel_effect(event: Dictionary) -> void:
	_task_id += 1
	var id := _task_id
	var layer = ANIMATION_LAYER.new()
	layer.name = "TableEffect%d" % id
	layer.tile_pool = _tile_pool
	layer.set_skip(_animation_layer._skip)
	_animation_layer.add_child(layer)
	_parallel_effects[id] = {"event": event, "layer": layer}
	refresh_masks()
	layer.play(event, _finish_parallel_effect.bind(id))

func _finish_parallel_effect(id: int) -> void:
	if not _parallel_effects.has(id): return
	var effect: Dictionary = _parallel_effects[id]
	_parallel_effects.erase(id)
	effect.layer.queue_free()
	refresh_masks()
	table.call_deferred("_refresh")

func _start_discard(event: Dictionary) -> void:
	_task_id += 1
	var id := _task_id
	var layer = ANIMATION_LAYER.new()
	layer.name = "DiscardLane%d" % id
	layer.tile_pool = _tile_pool
	layer.set_skip(_animation_layer._skip)
	# Child of the design-space layer: resize/letterboxing applies to all lanes.
	_animation_layer.add_child(layer)
	_discard_tasks[id] = {"event": event, "layer": layer, "landed": false, "sound": defers_discard_sound()}
	layer.discard_landed.connect(_discard_landed.bind(id))
	refresh_masks()
	layer.play(event, _finish_discard.bind(id))
	table._update_interactivity()

func _discard_landed(id: int) -> void:
	if not _discard_tasks.has(id): return
	var task: Dictionary = _discard_tasks[id]
	if task.landed: return
	task.landed = true
	if not task.event.get("claimed", false) and task.sound:
		AudioManager.play_discard_impact(table)
	# 落地后才把新弃牌节点显示出来。
	table.call_deferred("_refresh")
	refresh_masks()

func _finish_discard(id: int, refresh: bool = true) -> void:
	if not _discard_tasks.has(id): return
	var task: Dictionary = _discard_tasks[id]
	_discard_tasks.erase(id)
	var event: Dictionary = task.event
	var seat := int(event.get("seat", -1))
	task.layer.cancel()
	task.layer.queue_free()
	_restore()
	if event.get("discard_from_hand", false):
		var committed := _commit_hand_discard_visual(event)
		_held_refresh_seats.erase(seat)
		if committed and refresh and table.round.phase == RoundState.Phase.PLAYING: table._player_tile_areas.cache_current_hand(seat)
		if not committed: table._seat_visual_keys.erase(seat)
		# Refresh only on failure or future state changes. Successful commits keep
		# the physical entities; update the key on the next normal refresh.
	refresh_masks()
	table._update_interactivity()
	if refresh: table.call_deferred("_refresh")

func _finish_seat_discard(seat: int) -> void:
	for id in _discard_tasks.keys():
		if int(_discard_tasks[id].event.get("seat", -1)) == seat:
			_finish_discard(id, false)

func _claim_discard(claim: Dictionary) -> void:
	var source := int(claim.get("source", -1))
	var discard_id := int(claim.get("source_discard_id", -1))
	for event in _animation_queue:
		if event.get("type", "") == "discard" and int(event.get("seat", -2)) == source and int(event.get("discard_id", -2)) == discard_id:
			event["claimed"] = true
	for task in _discard_tasks.values():
		var event: Dictionary = task.event
		if int(event.get("seat", -2)) != source or int(event.get("discard_id", -2)) != discard_id: continue
		if not task.landed:
			claim["from"] = task.layer.discard_position(Vector2(claim.get("from", Vector2.ZERO)))
			event["claimed"] = true
			task.layer.hide_discard_flight()

func _mask(tile: Control) -> void:
	if not _masked.has(tile): _masked.append(tile)
	tile.modulate.a = 0.0
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _restore() -> void:
	for node in _masked:
		if is_instance_valid(node):
			node.modulate.a = 1.0
			if node is TileView: node.mouse_filter = Control.MOUSE_FILTER_STOP if node.interactive else Control.MOUSE_FILTER_IGNORE
	_masked.clear()

func _commit_hand_discard_visual(event: Dictionary) -> bool:
	var seat := int(event.get("seat", -1))
	if seat < 0 or seat >= table.hand_box.size(): return false
	var hand_box: Control = table.hand_box[seat]
	var source_index := int(event.get("discard_index", -1))
	var drawn_source_index_after := int(event.get("drawn_index_after", -1))
	var drawn_slot := int(event.get("drawn_hand_index", -1))
	var row_count := int(event.get("hand_row_count", 0))
	var slot_nodes: Dictionary = {}
	var source_indices: Dictionary = {}
	var draw_node = event.get("draw_node")
	if drawn_slot >= 0:
		if drawn_source_index_after < 0 or not is_instance_valid(draw_node): return false
		slot_nodes[drawn_slot] = draw_node
		source_indices[drawn_slot] = drawn_source_index_after
	for data in event.get("hand_moves", []):
		var node = data.get("node")
		var slot := int(data.get("slot", -1))
		var old_index := int(data.get("old_index", -1))
		if slot < 0 or not is_instance_valid(node): return false
		slot_nodes[slot] = node
		source_indices[slot] = old_index - (1 if old_index > source_index else 0)
	var discard_node = event.get("discard_node")
	if not is_instance_valid(discard_node) or slot_nodes.size() != row_count: return false
	for slot in row_count:
		if not slot_nodes.has(slot): return false
	# Validate the entire row before mutating any UI entity. Rules are untouched.
	if discard_node.get_parent() != null: discard_node.get_parent().remove_child(discard_node)
	discard_node.queue_free()
	for slot in row_count:
		var node: TileView = slot_nodes[slot]
		if node.get_parent() != hand_box:
			if node.get_parent() != null: node.get_parent().remove_child(node)
			hand_box.add_child(node)
		node.visible = true
		node.modulate.a = 1.0
		node.set_meta("concealed_index", source_indices[slot])
		node.set_meta("drawn", false)
		hand_box.move_child(node, mini(slot, hand_box.get_child_count() - 1))
		node.set_table_position(_hand_slot_local_target(seat, slot, row_count))
	if seat == table.human_seat: table._selected_tile = null
	return true

func _on_visual_animation_finished() -> void:
	var finished_type := str(_event.get("type", ""))
	if finished_type == "sort_hand":
		for data in _event.get("destinations", []):
			var tile = data.get("node")
			if is_instance_valid(tile) and tile is TileView:
				tile.set_table_position(Vector2(data.get("to", tile.position)))
		_sorting = false
		_opening = false
		_animation_busy = false
		if table.has_method("_on_opening_visual_finished"):
			table.call_deferred("_on_opening_visual_finished")
		table._update_interactivity()
		# The physical nodes have just reached their sorted slots.  Rebuild the
		# authoritative hand once so metadata, selection and hit areas match the
		# sorted logical order without any opening mask.
		table.call_deferred("_refresh")
		table.call_deferred("_pump_visual_animation")
		return
	if _event.get("type", "") == "deal":
		var deal_seat := int(_event.get("seat", 0))
		var dealt_now: Array = _event.get("cards", [])
		_dealt[deal_seat] += dealt_now.size()
		_dealt_cards[deal_seat].append_array(dealt_now)
		# Commit this packet to the persistent hand immediately.  The hand area is
		# rendered only up to _dealt[seat], so the just-landed cards remain visible
		# without covering a prebuilt final hand.
		table._refresh()
		if _opening and _all_opening_tiles_dealt():
			_start_sorting_animation()
			return
	if finished_type == "draw" or _animation_queue.is_empty():
		_opening = false
	_restore()
	_animation_busy = false
	table._update_interactivity()
	refresh_masks()
	if finished_type == "draw":
		var draw_seat := int(_event.get("seat", -1))
		if draw_seat >= 0:
			var remaining_draw_holds := int(_held_draw_seats.get(draw_seat, 1)) - 1
			if remaining_draw_holds <= 0:
				_held_draw_seats.erase(draw_seat)
				for draw_tile in _tiles_in(table.draw_box[draw_seat]):
					draw_tile.visible = true
				# Rebuild after landing so the persistent draw node becomes visible
				# exactly when the flying tile finishes.
				table.call_deferred("_refresh")
			else:
				_held_draw_seats[draw_seat] = remaining_draw_holds
	table._update_interactivity()
	if finished_type == "meld_reveal": table.call_deferred("_refresh")
	table.call_deferred("_pump_visual_animation")
	if _animation_queue.is_empty() and table.round.phase == RoundState.Phase.SETTLED:
		table._refresh.call_deferred()

func _animation_target_for_seat(seat: int) -> Vector2:
	var tiles: Array[TileView] = []
	if table._new_areas != null and table._new_areas.get("draw_boxes") != null:
		tiles = _tiles_in(table._new_areas.draw_boxes[seat])
	else:
		tiles = _tiles_in(table.draw_box[seat])
	if not tiles.is_empty(): return _position(tiles[0])
	var layout: Dictionary = table._hand_layout(seat) if table.round.players.size() == 4 else {"draw_x": 0}
	var local := Vector2(float(layout.draw_x), float(table._seat_metrics(seat).hand_y))
	return _animation_layer.get_global_transform().affine_inverse() * (table.seat_roots[seat].get_global_transform() * local)

func _hand_animation_target_for_seat(seat: int) -> Vector2:
	if seat < 0 or seat >= 4 or seat >= table.hand_box.size():
		return table._table_center()
	var tiles := _tiles_in(table.hand_box[seat])
	if not tiles.is_empty(): return _position(tiles[0])
	var layout: Dictionary = table._hand_layout(seat) if table.round.players.size() == 4 else {"hand_x": 0}
	var local := Vector2(float(layout.get("hand_x", 0.0)), float(table._seat_metrics(seat).hand_y))
	return _animation_layer.get_global_transform().affine_inverse() * (table.seat_roots[seat].get_global_transform() * local)
