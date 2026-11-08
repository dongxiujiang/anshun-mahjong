extends SceneTree

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var r := RoundState.new()
	r.set_rng_seed(7)
	r.opening_delay_seconds = 0.0
	r.controllers = [null, null, null, null]
	r.next_dealer_seat = 0
	r.next_chicken_multiplier = 1
	r.start_round(1, 2, 3)
	print("red=", r.round_meta.die, " white=", r.round_meta.die_white, " break=", r.round_meta.break,
		" double=", r.round_meta.dice_double, " mult=", r.round_meta.chicken_multiplier)
	if r.round_meta.die != 2 or r.round_meta.die_white != 3 or r.round_meta.dice_double or r.round_meta.previous_draw_double:
		push_error("双骰不同点处理错误")
		quit(1); return
	if int(r.round_meta.break) != WallRing.compute_break(2, 0):
		push_error("破墙未使用红骰")
		quit(1); return

	var d := RoundState.new()
	d.set_rng_seed(8)
	d.opening_delay_seconds = 0.0
	d.controllers = [null, null, null, null]
	d.next_dealer_seat = 0
	d.next_chicken_multiplier = 2
	d.start_round(1, 4, 4)
	print("equal red=", d.round_meta.die, " white=", d.round_meta.die_white,
		" double=", d.round_meta.dice_double, " mult=", d.round_meta.chicken_multiplier,
		" break=", d.round_meta.break)
	if not d.round_meta.dice_double or not d.round_meta.previous_draw_double or int(d.round_meta.chicken_multiplier) != 2:
		push_error("同点倍率错误")
		quit(1); return
	if int(d.round_meta.break) != WallRing.compute_break(4, 0):
		push_error("同点破墙应仍看红骰")
		quit(1); return
	var client := RoundState.new()
	client.apply_sync(d.serialize_for_seat(2))
	if not client.round_meta.previous_draw_double or not client.round_meta.dice_double:
		push_error("联机快照没有保留双倍来源")
		quit(1); return
	print("[two_dice_rule] passed")
	quit(0)
