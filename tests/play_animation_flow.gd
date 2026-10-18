extends SceneTree
## Deterministic presentation regression: run headless AND with a real renderer.
## Real Tween clocks are paused/custom-stepped; no sleeps determine assertions.
const H := preload("res://tests/test_harness.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const BASE := ["wan1","wan2","wan3","wan4","wan5","wan6","tiao2","tiao3","tiao4","tong1","tong2","tong3","wan9"]
var t := H.new()
var table
var controller
var graphical := false
var cfg
var impacts: Array = []

func _initialize() -> void: call_deferred("_run")

func game() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.controllers = [null,null,null,null]
	r.phase = RoundState.Phase.PLAYING
	r.awaiting = true
	r.current_turn = 0
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	for p in r.players: p.concealed = BASE.duplicate()
	return r

func fixture(cards: Array = BASE, drew: String = "") -> void:
	controller.cancel()
	if table.round.state_update.is_connected(table._refresh): table.round.state_update.disconnect(table._refresh)
	table.round = game()
	table.round.players[0].concealed = cards.duplicate()
	table.round.players[0].just_drew = drew
	table._connect_audio_round()
	table.round.state_update.connect(table._refresh)
	table.round.require_turn.connect(table._on_require_turn)
	table.round.require_response.connect(table._on_require_response)
	table._clear_actions()
	table._selecting = false
	table._refresh()

func step(layer, seconds: float) -> void:
	if layer._active != null:
		var tween: Tween = layer._active
		tween.pause()
		tween.custom_step(seconds)

func drain() -> void:
	for attempt in 100:
		for task in controller._discard_tasks.values().duplicate(): step(task.layer, 10.0)
		for effect in controller._parallel_effects.values().duplicate(): step(effect.layer, 10.0)
		controller._pump_visual_animation()
		if controller._animation_busy: step(table._animation_layer, 20.0)
		if not controller.has_pending(): break
	table._refresh()
	t.expect(not controller.has_pending(), "all lanes drain within a bounded number of steps")
	t.expect(controller._held_draw_seats.is_empty(), "drained lanes release draw holds")
	t.expect(controller._held_refresh_seats.is_empty(), "drained lanes release hand holds")
	var total := 0.0
	for player in table.round.players: total += player.score
	t.expect(is_equal_approx(total, 800.0), "presentation preserves total score 800")

func task_for(seat: int) -> Dictionary:
	for task in controller._discard_tasks.values():
		if int(task.event.get("seat", -1)) == seat: return task
	return {}

func test_draw() -> void:
	fixture()
	table.round.wall._ring[table.round.wall._head] = "wan9"
	table.round._begin_turn()
	t.expect(table.action_bar.get_child_count() > 0, "fixture really offers self-win/ready actions")
	t.expect(not table.action_bar.visible, "own actions stay invisible before draw completion")
	t.expect(not table.draw_box[0].get_child(0).visible, "persistent draw stays hidden before flight")
	var baseline := var_to_bytes(table.round.serialize())
	controller._pump_visual_animation()
	if graphical:
		var layer = table._animation_layer
		t.expect(not layer._temporary[0].face_up, "own draw flies face-down")
		step(layer, 0.24)
		t.expect(not table.action_bar.visible, "arrival alone does not expose buttons before flip")
		step(layer, 0.19)
		t.expect(layer._temporary[0].face_up, "own draw turns face-up after arrival")
		t.expect(not table.action_bar.visible, "readable hold precedes own buttons")
	drain()
	t.expect(table.action_bar.visible, "own actions appear after flip and readable hold")
	t.expect(table.draw_box[0].get_child(0).visible, "persistent draw shown after landing")
	t.expect(var_to_bytes(table.round.serialize()) == baseline, "draw animation does not advance authority")

func test_chickens_and_parallel() -> void:
	for chicken in ["tiao1", "tong8"]:
		for seat in 4:
			fixture()
			var player: PlayerState = table.round.players[seat]
			player.concealed = [chicken] + BASE.slice(1) + ["tong7"]
			player.just_drew = "tong7"
			table.round.current_turn = seat
			table._refresh()
			table.round._discard(seat, chicken, 0)
			var label := "%s seat%d" % [chicken, seat]
			t.expect(table.chicken_box[seat].get_child_count() == 1, "chicken target exists during held hand: " + label)
			var target: TileView = table.chicken_box[seat].get_child(0)
			t.expect(target.get_meta("charge_chicken", false), "first chicken retains charge identity: " + label)
			t.expect(is_equal_approx(target.rotation, -PI/2), "charge chicken lands sideways: " + label)
			t.expect(table.round.current_turn == (seat+1)%4, "authority has already advanced to next seat: " + label)
			if graphical:
				var task := task_for(seat)
				t.expect(not task.is_empty(), "discard owns an independent lane: " + label)
				if task.is_empty(): continue
				t.expect(task.event.destinations.size() == 1, "chicken has exactly one real destination: " + label)
				t.expect(Vector2(task.event.destinations[0].to).is_equal_approx(controller._position(target)), "flight ends at chicken, not draw slot: " + label)
				controller._pump_visual_animation()
				t.expect(controller._event.get("type", "") == "draw", "next draw starts before discard finishes: " + label)
				t.expect(not task.landed, "next draw starts even before old discard landing: " + label)
			drain()
			t.expect(table.chicken_box[seat].get_child_count() == 1, "chicken remains after insertion: " + label)

func prepare_claim(caller: int, source: int, card: String, count: int) -> Vector2:
	fixture()
	var hand: Array = []
	for i in count: hand.append(card)
	table.round.players[caller].concealed = hand + BASE.slice(count)
	table.round.players[source].discards = [card]
	table.round.players[source].discard_ids = [0]
	table.round.players[source].discard_count = 1
	table.round.last_discard = {"seat": source, "tile": card}
	table.round.round_meta.charge_chickens = {card: {"owner": source, "location": "discard", "discard_id": 0}}
	table._refresh()
	return controller._discard_visual_origin(source, card, 0)

func test_meld_sources() -> void:
	for caller in [0,1]:
		for action in ["pong", "kong"]:
			var source: int = (caller+1)%4
			var origin := prepare_claim(caller, source, "tong8", 3)
			table.round._response_stage = RoundState.ResponseStage.MELD
			table.round._process_response(caller, source, "tong8", {"action": action})
			var event: Dictionary = controller._animation_queue[0]
			var destinations: Array = controller._destinations(event)
			t.expect(destinations.size() == (3 if action == "pong" else 4), "correct moving meld size " + action)
			t.expect(destinations.filter(func(d): return Vector2(d.from).is_equal_approx(origin)).size() == 1, "exactly one meld tile comes from source discard " + action)
			t.expect(table.chicken_box[source].get_child_count() == 0, "claimed charge chicken removed from former owner")
			for tile in table.meld_box[caller].get_children():
				t.expect(not tile.get_meta("charge_chicken", false), "claimed chicken loses charge marker")
			drain()
	fixture(BASE.slice(0,10)+["tong8"], "tong8")
	table.round.players[0].melds = [{"kind":"pung", "tile":"tong8", "from_seat":1, "after_discard":0}]
	table._refresh()
	var draw_from: Vector2 = controller._position(table.draw_box[0].get_child(0))
	table.round._pending_kong = {"seat":0,"tile":"tong8","index":0}
	table.round._complete_add_kong()
	var event: Dictionary = controller._animation_queue[0]
	var destinations: Array = controller._destinations(event)
	t.expect(destinations.size() == 1, "added kong only flies its new fourth tile")
	t.expect(Vector2(destinations[0].from).is_equal_approx(draw_from), "added fourth tile starts at real draw slot")
	t.expect(controller._targets(event).size() == 1, "added kong does not mask three existing tiles")
	drain()
	fixture(["tiao1","tiao1","tiao1","tiao1"]+BASE.slice(4)+["tong9"], "tong9")
	var origins: Array = []
	for tile in table.hand_box[0].get_children():
		if tile.tile == "tiao1": origins.append(controller._position(tile))
	table.round._do_concealed_kong(0,"tiao1",table.round.players[0])
	event = controller._animation_queue[0]
	destinations = controller._destinations(event)
	t.expect(destinations.size() == 4, "concealed kong moves four entities")
	t.expect(destinations.filter(func(d): return origins.any(func(o): return Vector2(o).is_equal_approx(d.from))).size() == 4, "concealed kong uses exact removed indices, not rightmost hand tiles")
	t.expect(destinations.all(func(d): return d.tile == ""), "concealed animation never leaks its tile value")
	for wire_event in table.round.serialize_for_seat(1).visual_events:
		if wire_event.get("kind", "") == "concealed":
			t.expect(wire_event.tile == "" and not wire_event.has("cards"), "public concealed-kong metadata exposes positions only")
	drain()

func test_hand_clock_and_refresh() -> void:
	fixture(BASE + ["tong7"], "tong7")
	table.round._discard(0, "wan3", 2)
	if not graphical:
		drain()
		return
	var task := task_for(0)
	var event: Dictionary = task.event
	var tracked: Dictionary = {}
	for data in event.hand_moves:
		if not Vector2(data.from).is_equal_approx(data.to): tracked = data; break
	t.expect(not tracked.is_empty(), "fixture requires an actual gap move")
	if tracked.is_empty(): return
	var before: Vector2 = tracked.node.global_position
	step(task.layer, 0.27)
	t.expect(tracked.node.global_position.is_equal_approx(before), "hand gap does not move before 0.28s landing")
	t.expect(event.draw_node.visible, "draw source is retained before insertion")
	step(task.layer, 0.15)
	t.expect(not tracked.node.global_position.is_equal_approx(before), "hand moves during gap phase")
	var during: Vector2 = tracked.node.global_position
	table._refresh()
	t.expect(tracked.node.global_position.is_equal_approx(during), "refresh does not snap moving hand to stale layout")
	t.expect(event.draw_node.visible, "insert waits for full 0.56s discard-and-gap phases")
	step(task.layer, 0.15)
	t.expect(not event.draw_node.visible, "insert begins after gap is ready")
	var local_before: Vector2 = controller._position(tracked.node)
	table.size = Vector2(1000,600)
	table._layout()
	step(task.layer, 0.0)
	t.expect(controller._position(tracked.node).distance_to(local_before) < 0.1, "resize preserves design-space hand position")
	var kept = tracked.node
	var inserted = event.draw_node
	drain()
	t.expect(is_instance_valid(kept) and kept.get_parent() == table.hand_box[0], "hand commit reuses remaining physical nodes")
	t.expect(is_instance_valid(inserted) and inserted.get_parent() == table.hand_box[0], "insert transfers the actual drawn entity")
	t.expect(table.hand_box[0].get_child_count() == table.round.players[0].concealed.size(), "hand entity count matches authority after insert")
	table.size = Vector2(1280,720)
	table._layout()

func test_no_draw_discard_and_settlement() -> void:
	fixture(BASE.slice(0,11))
	table.round.players[0].melds = [{"kind":"pung","tile":"tiao1","from_seat":1,"after_discard":0}]
	table._refresh()
	var kept = table.hand_box[0].get_child(4)
	table.round._discard(0,"wan3",2)
	if graphical:
		var task := task_for(0)
		t.expect(task.event.hand_insert.is_empty(), "post-pung discard has no invented inserted tile")
		t.expect(task.event.hand_moves.size() == 10, "post-pung discard closes gap with ten actual remaining nodes")
		t.expect(task.event.hand_move_required, "post-pung discard animates gap closing")
	drain()
	t.expect(table.hand_box[0].get_child_count() == 10, "post-pung discard leaves correct hand count")
	t.expect(is_instance_valid(kept) and kept.get_parent() == table.hand_box[0], "post-pung discard reuses existing hand nodes")
	fixture(BASE.slice(0,12)+["tiao1"])
	table.round.players[0].ready = true
	table.round.players[1].concealed = ["tiao1"]+BASE.slice(1)+["tong7"]
	table.round.players[1].just_drew = "tong7"
	table.round.current_turn = 1
	table._refresh()
	table.round._discard(1,"tiao1",0)
	t.expect(table.action_bar.visible, "winning response need not wait for discard landing")
	table._commit_response("win")
	t.expect(table.round.phase == RoundState.Phase.SETTLED, "win settles authority while discard animation remains")
	drain()
	table._settlement_animation_controller.skip()
	for seat in 4:
		t.expect(table.hand_box[seat].get_children().all(func(tile): return tile.face_up), "settlement reveals all hands including the held discarder seat%d" % seat)

func test_live_claim() -> void:
	fixture(["tiao1","tiao1","tiao1"]+BASE.slice(3))
	table.round.players[1].concealed = ["tiao1"] + BASE.slice(1) + ["tong7"]
	table.round.players[1].just_drew = "tong7"
	table.round.current_turn = 1
	table._refresh()
	table.round._discard(1,"tiao1",0)
	t.expect(table.action_bar.visible, "response buttons appear while opponent discard is flying")
	t.expect(not controller.input_locked(), "opponent insertion cannot lock our claim")
	var task := task_for(1)
	if graphical: step(task.layer, 0.1)
	table._commit_response("pong")
	t.expect(table.round.players[0].melds.size() == 1, "pong is accepted before discard completes")
	if graphical:
		t.expect(task.event.get("claimed", false), "live claim transfers ownership of flying discard")
		t.expect(task.layer._flight_tiles.all(func(tile): return not tile.visible), "no duplicate flying source after claim")
		t.expect(not table.action_bar.visible, "own meld must settle before own turn buttons")
	drain()
	t.expect(table.chicken_box[1].get_child_count() == 0, "claimed chicken never reappears at old owner")

func test_reveal_and_sort() -> void:
	fixture(BASE + ["tong7"], "tong7")
	table.round.players[0].melds = [{"kind":"kong","tile":"tiao1","concealed":true,"after_discard":0}]
	table.round.players[0].discard_count = 1
	table._refresh()
	table.round._discard(0,"wan3",2)
	if graphical:
		t.expect(table.meld_box[0].get_children().all(func(tile): return not tile.face_up), "queued reveal stays face-down after second discard")
		controller._pump_visual_animation()
		t.expect(controller._parallel_effects.size() == 1, "second discard schedules one parallel reveal")
		var effect: Dictionary = controller._parallel_effects.values()[0]
		t.expect(effect.layer._temporary.all(func(tile): return not tile.face_up), "reveal animation starts from back, never face-back-face")
		controller._pump_visual_animation()
		t.expect(controller._event.get("type", "") == "draw", "next draw does not wait for unrelated kong reveal")
	drain()
	t.expect(table.meld_box[0].get_children().all(func(tile): return tile.face_up), "revealed kong stays face-up on completion")
	fixture()
	for data in controller._sort_destinations():
		t.expect(is_zero_approx(float(data.rotation)), "persistent sort uses local zero rotation on every seat")
	if graphical:
		controller._start_sorting_animation()
		step(table._animation_layer,0.25)
		for seat in 4:
			t.expect(table.hand_box[seat].get_children().all(func(tile): return is_zero_approx(tile.rotation)), "sort never double-rotates seat%d" % seat)
	drain()

func test_network_and_pool() -> void:
	fixture()
	var host := game()
	host.current_turn = 1
	table.round.apply_sync(host.serialize_for_seat(0))
	table._refresh()
	host.wall._ring[host.wall._head] = "tong8"
	host._begin_turn()
	host._discard(1,"tong8",13)
	table.round.apply_sync(host.serialize_for_seat(0))
	table._refresh()
	t.expect(not controller.has_pending(), "merged draw-discard snapshot fast-forwards, no fictitious centre flight")
	t.expect(table.draw_box[1].get_child_count() == 0, "merged final state has no stale draw entity")
	t.expect(table.chicken_box[1].get_child_count() == 1, "merged final state retains real discarded chicken")
	var serialized := var_to_bytes(table.round.serialize())
	table.round._presentation.sync_initialized = false
	table.round.apply_sync(host.serialize_for_seat(0))
	t.expect(not controller.has_pending(), "reconnect does not replay history")
	t.expect(var_to_bytes(table.round.serialize()) == serialized, "repeated snapshot stays idempotent")
	fixture()
	var unchanged = table.hand_box[2].get_child(0)
	table.round.players[1].discards.append("wan5")
	table.round.last_discard = {"seat":1,"tile":"wan5"}
	table._refresh()
	t.expect(table.hand_box[2].get_child(0) == unchanged, "unrelated discard does not rebuild another hand")
	t.expect(table._animation_layer.tile_pool != null, "temporary animation pool is wired after layer construction")
	var pool = table._animation_layer.tile_pool
	var tile: TileView = pool.acquire()
	tile.rotation = 2.0
	tile.scale = Vector2(0.2,0.2)
	tile.pivot_offset = Vector2(10,10)
	tile.set_meta("charge_chicken",true)
	tile.set_meta("concealed_index",5)
	pool.release(tile)
	var recycled: TileView = pool.acquire()
	t.expect(recycled == tile, "temporary pool actually reuses entities")
	t.expect(recycled.rotation == 0 and recycled.scale == Vector2.ONE and recycled.pivot_offset == Vector2.ZERO, "pool resets all transforms")
	t.expect(recycled.get_meta_list().is_empty(), "pool clears old identity and chicken metadata")
	pool.release(recycled)

func test_speed_and_cancel() -> void:
	for speed in ["standard", "fast", "instant"]:
		cfg.animation_speed = speed
		fixture(BASE + ["tong7"], "tong7")
		table.round._discard(0,"wan3",2)
		var baseline := var_to_bytes(table.round.serialize())
		if speed == "instant":
			t.expect(controller._discard_tasks.is_empty(), "instant discard never creates a live Tween")
			controller._pump_visual_animation()
			t.expect(not controller.has_pending(), "instant draw drains synchronously")
		elif graphical:
			var task := task_for(0)
			step(task.layer,0.28 * float(cfg.ANIMATION_SPEEDS[speed]) - 0.01)
			t.expect(not task.landed, "speed scales landing once: " + speed)
			step(task.layer,0.02)
			t.expect(task.landed, "scaled landing deadline: " + speed)
		controller.cancel()
		table._refresh()
		t.expect(not controller.has_pending(), "cancel clears main and independent lanes: " + speed)
		t.expect(controller._masked.is_empty(), "cancel restores masks: " + speed)
		t.expect(table._animation_layer._temporary.is_empty(), "cancel releases temporary tiles: " + speed)
		t.expect(var_to_bytes(table.round.serialize()) == baseline, "cancel is presentation-only: " + speed)
	cfg.animation_speed = "standard"

func test_opening_speed() -> void:
	for speed in ["instant", "fast", "standard"]:
		cfg.animation_speed = speed
		fixture()
		# Fixed seed + no authority sleep exercises the race where the dealer's
		# draw is already published before the last deal packet is rendered.
		table.round.start_round(0,3)
		controller._pump_visual_animation()
		if graphical:
			t.expect(is_equal_approx(controller._opening_speed_scale,float(cfg.ANIMATION_SPEEDS[speed])), "offline opening captures one speed factor: " + speed)
		drain()
		t.expect(table.hand_box[0].get_child_count() == 13, "opening ends with 13 sorted dealer hand tiles: " + speed)
		t.expect(table.draw_box[0].get_child_count() == 1, "opening preserves separate dealer draw: " + speed)
		t.expect(not controller.opening_active() and not controller.sorting_active(), "opening unlocks after final visuals: " + speed)
	if graphical:
		cfg.animation_speed = "instant"
		fixture()
		root.get_node("Network").mode = "host"
		controller._on_visual_event({"type":"dice","value":3,"id":1})
		controller._pump_visual_animation()
		t.expect(is_equal_approx(table._animation_layer._speed_scale,1.0), "online opening retains shared timing despite local instant setting")
		controller.cancel()
		root.get_node("Network").mode = ""
	cfg.animation_speed = "standard"

func capture_frame(label: String) -> void:
	if table._animation_layer._active != null: table._animation_layer._active.pause()
	for task in controller._discard_tasks.values():
		if task.layer._active != null: task.layer._active.pause()
	for effect in controller._parallel_effects.values():
		if effect.layer._active != null: effect.layer._active.pause()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ui_review/play_animation/" + label + ".png")

func capture_review() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/ui_review/play_animation"))
	fixture()
	table.round.wall._ring[table.round.wall._head] = "wan9"
	table.round._begin_turn()
	controller._pump_visual_animation()
	step(table._animation_layer,0.12)
	await capture_frame("01_draw_back_buttons_hidden")
	step(table._animation_layer,0.32)
	await capture_frame("02_draw_front_readable_hold")
	drain()
	await capture_frame("03_draw_complete_buttons_visible")
	fixture(["tiao1"]+BASE.slice(1)+["tong7"],"tong7")
	table.round._discard(0,"tiao1",0)
	var task := task_for(0)
	controller._pump_visual_animation()
	step(task.layer,0.14)
	step(table._animation_layer,0.10)
	await capture_frame("04_chicken_and_next_draw_parallel")
	step(task.layer,0.30)
	await capture_frame("05_chicken_landed_hand_closing_gap")
	drain()
	fixture(BASE.slice(0,10)+["tong8"],"tong8")
	table.round.players[0].melds = [{"kind":"pung","tile":"tong8","from_seat":1,"after_discard":0}]
	table._refresh()
	table.round._pending_kong = {"seat":0,"tile":"tong8","index":0}
	table.round._complete_add_kong()
	controller._pump_visual_animation()
	step(table._animation_layer,0.14)
	await capture_frame("06_added_kong_only_fourth_tile")
	drain()

func test_impact_timing() -> void:
	if not graphical: return
	fixture(BASE+["tong7"], "tong7")
	var audio = root.get_node("AudioManager")
	audio.enabled.effects = true
	audio.volumes.effects = 0.5
	audio.discard_impact_played.connect(func(): impacts.append(true))
	impacts.clear()
	table.round._discard(0,"wan3",2)
	t.expect(impacts.is_empty(), "discard announcement does not play impact before landing")
	var task := task_for(0)
	step(task.layer,0.27)
	t.expect(impacts.is_empty(), "no early landing sound")
	step(task.layer,0.02)
	t.expect(impacts.size() == 1, "impact fires exactly at tile landing")
	drain()
	t.expect(impacts.size() == 1, "insertion completion does not replay landing sound")
	fixture(BASE+["tong7"], "tong7")
	table.round._discard(0,"wan3",2)
	controller.cancel()
	t.expect(impacts.size() == 1, "cancel does not invent a late impact")
	audio.enabled.effects = false

func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	root.get_node("UpdateManager").auto_check = false
	cfg = root.get_node("GameConfig")
	cfg.animation_speed = "standard"
	# Hundreds of fixtures in one frame must not queue real voice/music streams.
	root.get_node("AudioManager").enabled = {"music":false,"voice":false,"effects":false}
	var network = root.get_node("Network")
	network.mode = "host"
	network.net_node.game = game()
	network.net_node.my_seat = 0
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	root.get_node("AudioManager").music_player.stop()
	network.mode = ""
	controller = table._table_animation_controller
	await process_frame
	test_draw()
	test_chickens_and_parallel()
	test_meld_sources()
	test_hand_clock_and_refresh()
	test_live_claim()
	test_no_draw_discard_and_settlement()
	test_reveal_and_sort()
	test_network_and_pool()
	test_speed_and_cancel()
	test_opening_speed()
	test_impact_timing()
	if graphical and OS.get_cmdline_user_args().has("--capture"): await capture_review()
	controller.cancel()
	table.queue_free()
	await create_timer(0.6).timeout
	print("[play_animation_flow] renderer=", DisplayServer.get_name(), " seed=20261018")
	quit(t.finish("play_animation_flow"))

