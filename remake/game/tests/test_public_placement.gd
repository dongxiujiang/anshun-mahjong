extends SceneTree
const Round := preload("res://src/domain/Round.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")
const Shared := preload("res://src/presentation/SharedHandDisplay.gd")
const Table := preload("res://src/presentation/TableView.gd")
var round_state := Round.new()
var display := Shared.new(false)
var checks := 0
var failures := 0
var warm: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(label)

# Set only the faces needed by the scenario, then fill all free slots from a legal 108-tile deck.
func deck() -> Array:
	var deal := Round.new()
	deal.start(1, 2, 2, Catalog.ordered_values())
	var owner := ["tong8", "tong8", "tong8", "tong8", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan4", "tiao1", "wan1"]
	var provider := ["wan2", "wan3", "tiao1", "tiao1"]
	var fixed := {}
	for i in owner.size(): fixed[deal.players[1].hand[i]] = owner[i]
	for i in provider.size(): fixed[deal.players[0].hand[i]] = provider[i]
	for value in ["wan5", "wan6", "wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tong5", "wan4", "tong6", "tiao3", "tiao5", "tiao6", "tiao7"]:
		fixed[deal.wall.take_head()] = value
	fixed[deal.wall.take_tail()] = "tong7"
	var remaining := Catalog.values(3741)
	for value in fixed.values(): remaining.erase(value)
	var values := []
	for id in Catalog.COUNT:
		values.append(fixed[id] if fixed.has(id) else remaining.pop_back())
	return values

func view(seat: int) -> Dictionary:
	var projection := round_state.snapshot_for(seat)
	display.project(round_state, projection)
	return projection

func sync() -> void:
	display.sync(round_state)
	warm.apply_view(view(1))

func discard(seat: int, value: String = "") -> void:
	var id: int = round_state.players[seat].draw_id
	if value != "":
		id = -1
		for tile_id in round_state.players[seat].hand:
			if round_state.wall.value(tile_id) == value:
				id = tile_id
				break
	check(round_state.submit(seat, round_state.prompt_id, "discard", id), "legal discard seat %d %s" % [seat, value])
	sync()

func answer(claimant: int = -1) -> void:
	if claimant >= 0:
		check(round_state.submit(claimant, round_state.prompt_id, "pong"), "legal claim by %d" % claimant)
		sync()
	if round_state.phase == "response":
		check(round_state.expire_responses(round_state.prompt_id), "resolve remaining real response windows")
		sync()

func rotations(count: int) -> void:
	for turn in count:
		discard(round_state.turn)
		answer()

func _run() -> void:
	var values := deck()
	check(Catalog.valid_deck(values) and round_state.start(1, 2, 2, values), "legal full deck starts")
	warm = Table.new(false)
	root.add_child(warm)
	sync()
	check(round_state.begin_dealer_turn(), "dealer turn opens")
	sync()
	discard(1, "tong8")
	var first_id: int = round_state.last_discard.tile_id
	answer()
	discard(0, "wan2")
	answer(1)
	discard(1, "tong8")
	answer()
	rotations(3)
	discard(1, "tong8")
	answer()
	rotations(3)
	var eligible: Array = round_state.choices(1).get("concealed_kong_ids", [])
	check(eligible.size() == 1 and round_state.submit(1, round_state.prompt_id, "concealed_kong", eligible[0]), "legal four-wan concealed kong on drawing fourth copy")
	sync()
	var mask: Dictionary = view(3).players[1].melds[1]
	check(not mask.has("tile_ids") and not mask.has("tile"), "authority placement does not reveal newly concealed kong")
	discard(1)
	answer()
	discard(0, "wan3")
	answer(1)
	discard(1, "tong8")
	answer()
	rotations(3)
	var key := "c" + str(first_id)
	var before: Array = view(1).players[1].public_centers[key]
	discard(1, "tiao1")
	var claimed_id: int = round_state.last_discard.tile_id
	var shifted: Dictionary = view(1).players[1].public_centers
	check(float(shifted[key][0]) < float(before[0]) and is_equal_approx(shifted[key][1], before[1]), "temporary charge chicken causes only required horizontal motion")
	answer(0)
	var final_centers: Dictionary = view(1).players[1].public_centers
	check(not final_centers.has("c" + str(claimed_id)) and final_centers[key] == shifted[key], "claim frees only its own tile footprint without undoing other groups' movement")
	var recovered := Shared.new(false)
	recovered.sync(round_state)
	var restored := round_state.snapshot_for(0)
	recovered.project(round_state, restored)
	check(restored.players[1].public_centers == final_centers, "replaying full authority event stream restores the same layout")
	warm._render(false)
	var final_origin: Vector3 = warm.tiles[first_id].position
	for seat in 4:
		var snapshot := view(seat)
		check(snapshot.players[1].public_centers == final_centers, "all observers receive identical public coordinates")
		var late := Table.new(false)
		root.add_child(late)
		late.apply_view(snapshot)
		late._render(false)
		check(late.tiles[first_id].position.is_equal_approx(final_origin), "fresh observer and continuous observer show the same real tile")
		check(not late.tiles.has(claimed_id) or late.tiles[claimed_id].get_meta("zone") == "meld", "claimed chicken is never left in discard zone")
		late.free()
	warm.free()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
