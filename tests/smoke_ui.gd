extends SceneTree
## UI 闭环：加载 GameTable，把真人当作自动玩家驱动，验证 异步信号→submit 全流程能打到结算。
## 运行： godot --headless --script res://tests/smoke_ui.gd

const H := preload("res://tests/test_harness.gd")

var table
var _frames := 0
var t := H.new()
var audio_seats := [0, 0, 0, 0]
var audio_wins := 0

func _initialize() -> void:
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	call_deferred("_drive")

func _drive() -> void:
	_frames += 1
	if _frames == 1:
		root.get_node("AudioManager").event_played.connect(_on_audio_event)
	if _frames > 4000:
		print("[smoke_ui] 超时结束失败")
		t.expect(false, "UI 闭环超时（%d 帧未结算）" % _frames)
		table.queue_free()
		# 音频停止与 Playback 回收在音频线程上完成。
		await create_timer(0.2).timeout
		quit(t.finish("smoke_ui")); return
	var r = table.round
	if r.phase == "settled":
		print("[smoke_ui] 结算: winner=%d deltas=%s 牌守恒=%s" % [r.round_meta.winner, str(r.last_result.deltas), _conserved(r)])
		t.expect(_conserved(r), "UI结算后牌应守恒")
		t.expect(is_zero_approx(r.last_result.total_delta), "UI结算后总分变化应为0")
		for seat in 4:
			t.expect(audio_seats[seat] > 0, "真人和每个AI都应该触发出牌语音")
		t.expect(audio_wins == (1 if int(r.round_meta.winner) >= 0 else 0), "结算只触发一次正确的胡牌语音，流局不触发")
		table.queue_free()
		await create_timer(0.2).timeout
		quit(t.finish("smoke_ui")); return
	if r.awaiting:
		if not r._awaiting_response.is_empty():
			# 别家弃牌回应
			var seat: int = r._awaiting_response.seat
			var tile: String = r._awaiting_response.tile
			var ps = r.players[seat]
			var can_win: bool = RuleEngine.can_win_on(ps.concealed, ps.melds, tile)
			r.submit_response(seat, tile, {"action": "win" if can_win else "pass"})
		else:
			# 轮到真人（seat0）出牌
			var seat: int = r.current_turn
			var ps = r.players[seat]
			var dict := _decide(seat, ps, r)
			r.submit_turn(seat, dict)
		await process_frame
	else:
		await process_frame
	_drive()

func _on_audio_event(event: Dictionary) -> void:
	if event.action == "discard":
		audio_seats[int(event.seat)] += 1
	elif event.action in ["hu", "zimo"]:
		audio_wins += 1

func _decide(seat: int, ps, r) -> Dictionary:
	if RuleEngine.analyze(ps.concealed, ps.melds).win:
		return {"self_win": true}
	# 弃最低向听
	var best: String = ps.concealed[0]
	var bs := 99
	for tile in ps.concealed.duplicate():
		var trial: Array = ps.concealed.duplicate()
		trial.erase(tile)
		var sh := Shanten.shanten(trial, ps.melds)
		if sh < bs:
			bs = sh
			best = tile
	return {"discard": best, "kong_declares": [], "add_kong": [], "ready": false, "self_win": false}

func _conserved(r) -> bool:
	var n := 0
	for ps in r.players:
		n += ps.concealed.size() + ps.discards.size()
		for m in ps.melds:
			n += 3 if m.kind == "pung" else 4
	n += r.wall.remaining
	return n == 108
