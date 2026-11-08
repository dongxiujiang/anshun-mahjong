extends Node
## Device-only visual acceptance harness. Not included in production exports.
const TABLE = preload("res://scenes/GameTable.tscn")
const AI = preload("res://scripts/ai/AiPlayer.gd")
const SCENARIO = "natural"
var scenario = SCENARIO
var table
var output = "/sdcard/Android/data/com.anshun.mahjong/files/phone-review"
var started = 0
var frame_index = 0
var finished = false
var events: Array = []
var manifest: FileAccess
var last_stage = ""

class CoverageActor extends RefCounted:
	var normal
	func _init(): normal = AI.new("Coverage", "low")
	func decide_turn(round, seat):
		var options = round.legal_turn_options(seat)
		if options.self_win: return {"self_win": true}
		if not options.kong_declares.is_empty(): return {"kong_declares": [options.kong_declares[0]]}
		if not options.add_kong.is_empty(): return {"add_kong": [options.add_kong[0]]}
		if not options.ready_discards.is_empty():
			var drawn = round.players[seat].just_drew
			return {"ready": true, "discard": drawn if drawn in options.ready_discards else options.ready_discards[0]}
		return normal.decide_turn(round, seat)
	func decide_response(round, seat, source, tile, options):
		if options.get("can_win",false): return {"action":"win"}
		if options.get("can_kong",false): return {"action":"kong"}
		return normal.decide_response(round, seat, source, tile, options)

func _ready():
	var cli_exit := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--review-coverage": scenario = "coverage"
		if arg == "--review-exit": cli_exit = true
	var mode_path = "/sdcard/Android/data/com.anshun.mahjong/files/review-mode.txt"
	if OS.has_feature("android") and FileAccess.file_exists(mode_path):
		scenario = FileAccess.get_file_as_string(mode_path).strip_edges()
	if not OS.has_feature("android"):
		output = "res://build/settlement-scenarios/full-round-" + scenario
	DirAccess.make_dir_recursive_absolute(output)
	manifest = FileAccess.open(output.path_join("frames.jsonl"), FileAccess.WRITE)
	if manifest == null:
		push_error("PHONE_REVIEW cannot write " + output)
		return
	get_node("/root/UpdateManager").auto_check = false
	GameConfig.set_tile_animation_seconds(0.30, false)
	GameConfig.set_settlement_speed("slow", false)
	await get_tree().create_timer(2.0).timeout
	table = TABLE.instantiate()
	add_child(table)
	for seat in 4:
		table.round.controllers[seat] = CoverageActor.new() if scenario == "coverage" else AI.new("Review%d" % seat, "medium")
	if scenario == "coverage":
		table.round.set_ai_service(null)
		table.round.dealt.connect(_prepare_coverage_deck)
	table.round.ai_delay_seconds = 1.0
	table.round.ai_response_delay_seconds = 1.0
	table.round.set_rng_seed(7)
	table.round.visual_event.connect(_event)
	started = Time.get_ticks_msec()
	table.round.start_round(table.human_seat, 3, 2)
	await _capture_loop()
	if cli_exit:
		var result: int = 0 if table.round.phase == RoundState.Phase.SETTLED and table._new_areas.native_settlement_complete() else 1
		table.queue_free()
		await get_tree().process_frame
		await preload("res://tests/test_harness.gd").quit_cleanly(get_tree(), result)

func _event(event: Dictionary):
	events.append(event.duplicate(true))
	print("[PHONE_REVIEW_EVENT] ", JSON.stringify(event))

## Arrange a reproducible legal 108-tile deck before visual deal events are
## emitted. Only this excluded test harness changes the shuffle, never rules.
func _prepare_coverage_deck(info: Dictionary):
	var indices = {0:[],1:[],2:[],3:[]}
	for batch in info.batches:
		for deal in batch: indices[int(deal.seat)].append_array(deal.indices)
	var requests = []
	var ready = ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tong1","tong2","tong3","tong5"]
	for i in 13: requests.append([indices[1][i],ready[i]])
	for i in 3: requests.append([indices[0][i],"tong9"])
	for i in 4: requests.append([indices[2][i],"tiao5"])
	requests.append([table.round.wall._head,"tong9"])
	var fixed = {}
	var ring: Array = table.round.wall._ring
	for request in requests:
		var target = int(request[0])
		var card = str(request[1])
		for source in ring.size():
			if fixed.has(source) or str(ring[source]) != card: continue
			var previous = ring[target]
			ring[target] = ring[source]
			ring[source] = previous
			fixed[target] = true
			break
	for player in table.round.players:
		player.concealed = []
		for index in indices[player.seat]: player.concealed.append(ring[int(index)])
	for batch in info.batches:
		for deal in batch:
			for i in deal.indices.size(): deal.cards[i] = ring[int(deal.indices[i])]
	print("[PHONE_REVIEW_SCENARIO] legal-deck ready / exposed-kong / concealed-kong")

func _capture_loop():
	var settled_at = 0
	while is_instance_valid(table) and Time.get_ticks_msec() - started < 240000:
		await RenderingServer.frame_post_draw
		var elapsed = Time.get_ticks_msec() - started
		var view = table._new_areas
		var stage = str(view._settlement_stage_key)
		var data = {"frame": frame_index, "ms": elapsed, "phase": table.round.phase,
			"turn": table.round.current_turn, "events": events.duplicate(true), "stage": stage,
			"settlement_complete": view.native_settlement_complete(), "players": [], "tiles": []}
		data["payments"] = view._settlement_pairs.duplicate(true)
		data["display_scores"] = view._settlement_display_scores.duplicate()
		data["pending"] = view.native_presentation_pending()
		data["settlement_started"] = view.native_settlement_started()
		data["next_controls_visible"] = table._settlement_card._post_controls.visible
		for player in table.round.players:
			data.players.append({"seat": player.seat, "hand": player.concealed.duplicate(),
				"draw": player.just_drew, "melds": player.melds.duplicate(true),
				"discards": player.discards.duplicate(), "ready": player.ready})
		for layer in [view._wall_layer, view._discard_layer, view._red_layer, view._meld_layer] + view.hand_boxes + view.draw_boxes:
			for tile in layer.get_children():
				if not (tile is TileView): continue
				data.tiles.append({"id": tile.get_instance_id(), "layer": layer.name,
					"seat": tile.get_meta("v2_seat", -1), "card": tile.tile, "face": tile.face_up,
					"rect": [tile.position.x, tile.position.y, tile.size.x, tile.size.y],
					"scale": [tile.scale.x, tile.scale.y], "alpha": tile.modulate.a,
					"angle": tile.rotation, "discard_id": tile.get_meta("discard_id",-1),
					"meld_index": tile.get_meta("meld_index",-1), "meld_slot": tile.get_meta("meld_slot",-1),
					"index": tile.get_meta("concealed_index", -1)})
		var name = "%05d_%06d.png" % [frame_index, elapsed]
		var screenshot = get_viewport().get_texture().get_image()
		screenshot.save_png(output.path_join(name))
		data["image"] = name
		manifest.store_line(JSON.stringify(data))
		manifest.flush()
		events.clear()
		frame_index += 1
		if stage != last_stage:
			print("[PHONE_REVIEW_STAGE] ", stage)
			last_stage = stage
		if table.round.phase == RoundState.Phase.SETTLED and view.native_settlement_started() and view.native_settlement_complete():
			if settled_at == 0: settled_at = elapsed
			if elapsed - settled_at > 2000: break
		await get_tree().create_timer(0.16).timeout
	manifest.close()
	finished = true
	print("[PHONE_REVIEW_DONE] frames=", frame_index, " phase=", table.round.phase)
	if table._ai_service != null: table._ai_service.stop()
