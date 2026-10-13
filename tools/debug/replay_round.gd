extends SceneTree
## godot --headless --path 工程目录 --script res://tools/debug/replay_round.gd -- --record=记录路径
const REPLAY := preload("res://scripts/core/RoundReplay.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--record="): path = argument.trim_prefix("--record=")
	if path == "":
		print("[replay_round] 请提供 --record=对局JSON文件路径")
		quit(1)
		return
	var result := REPLAY.replay(REPLAY.load_record(path))
	if not result.ok:
		print("[replay_round] 第 %d 次操作失败：%s" % [result.event_index + 1, result.error])
		quit(1)
		return
	var round: RoundState = result.round
	print("[replay_round] 已重放 %d 次操作，阶段=%s" % [result.event_index, RoundState._phase_name(round.phase)])
	if round.phase == RoundState.Phase.SETTLED:
		print("[replay_round] 胜者=%s 积分变化=%s 下局庄家=%s" % [round.round_meta.winner, round.last_result.deltas, round.next_dealer_seat])
	print("[replay_round] passed")
	quit(0)
