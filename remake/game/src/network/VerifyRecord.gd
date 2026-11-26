extends SceneTree
## Isolated, bounded verifier for user-authorized diagnostic uploads. Never prints the private tape.
const Record = preload("res://src/session/RoundRecord.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var source := FileAccess.open(args[0], FileAccess.READ)
	if source == null or source.get_length() > 2 * 1024 * 1024:
		quit(2)
		return
	var result := Record.replay_json(source.get_as_text())
	if result.ok:
		print("DONGXIU_REPLAY_OK")
	quit(0 if result.ok else 1)
