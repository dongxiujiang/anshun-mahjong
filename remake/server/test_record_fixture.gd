extends "res://tests/test_match_session.gd"
## Builds two actual, independently replayable records and one re-sealed false ledger for the HTTP test.
const Record = preload("res://src/session/RoundRecord.gd")

func _run() -> void:
	var directory := OS.get_environment("DONGXIU_TEST_RECORD_DIR")
	if not directory.is_absolute_path():
		quit(2)
		return
	dice = Dice.new()
	root.add_child(dice)
	for i in 2:
		game = Match.new("records")
		var host: Dictionary = game.join("test-player", "南", "host", now)
		instance = host.ticket.room_instance_id
		game.set_ready("host", true, now)
		if not await _roll(30000 + i):
			quit(1)
			return
		var stock := _deck(1, int(dice.snapshot().result[0]), {1: "w123456789 t123 b5"}, "tong5")
		game.start_round(dice, stock, now, 1)
		game.begin_dealer_turn(instance, 1, _seat_view(1).prompt_id, now)
		check(_act(1, _seat_view(1).prompt_id, "self_win", -1), "real fixture wins")
		var record: Dictionary = game.last_completed_record()
		check(Record.replay(record).ok, "fixture actually replays")
		var file := FileAccess.open(directory.path_join("real%d.json" % i), FileAccess.WRITE)
		file.store_string(JSON.stringify(record))
		file.close()
		if i == 0:
			record.ledger.deltas[0] += 7
			record.erase("checksum")
			record.checksum = Record._canonical(record).sha256_text()
			file = FileAccess.open(directory.path_join("false-ledger.json"), FileAccess.WRITE)
			file.store_string(JSON.stringify(record))
			file.close()
	print("Record upload fixtures: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
