extends RefCounted
## 测试断言收集器：把失败的断言累积起来，由调用方统一决定退出码。
##
## 为什么不用 assert()：assert 只会在 debug 构建里生效，release 构建直接跳过；
## 而且 assert 不会改变退出码，CI 里测试失败也会返回 0。
## 用法：
##     const H := preload("res://tests/test_harness.gd")
##     var t := H.new()
##     func _initialize() -> void: call_deferred("_run")
##     func _run() -> void:
##         t.expect(cond, "失败信息")
##         await H.quit_cleanly(self, t.finish("smoke_xxx"))

var checks := 0
var failures := 0
var _messages: Array[String] = []

## AudioServer releases Playback on its own thread. Frame-only waits and stop()
## during _exit_tree() can leave WAV resources alive at the engine's exit check.
## Stop while the tree is still running, detach streams, then verify release.
static func drain_audio(tree: SceneTree) -> bool:
	var audio := tree.root.get_node_or_null("AudioManager")
	if audio == null: return true
	var playbacks: Array[WeakRef] = []
	var players: Array = [audio.voice_player, audio.effects_player, audio.settlement_player].filter(func(p): return p != null)
	for player in players:
		if player != null and player.has_stream_playback():
			playbacks.append(weakref(player.get_stream_playback()))
	audio.end_table()
	if audio._duck_tween != null and audio._duck_tween.is_valid(): audio._duck_tween.kill()
	for player in players:
		if player != null:
			player.stop()
			player.stream = null
	audio._streams.clear()
	# Also drain retired playbacks from earlier stream changes. Use real time so
	# a paused tree or a modified Engine.time_scale cannot shorten this interval.
	await tree.create_timer(0.25, true, false, true).timeout
	var deadline := Time.get_ticks_msec() + 2000
	while playbacks.any(func(ref): return ref.get_ref() != null) and Time.get_ticks_msec() < deadline:
		await tree.create_timer(0.05, true, false, true).timeout
	if playbacks.any(func(ref): return ref.get_ref() != null):
		push_error("Audio shutdown timed out: playback resources are still referenced")
		return false
	return true

static func quit_cleanly(tree: SceneTree, code: int) -> void:
	var released := await drain_audio(tree)
	tree.quit(code if released else 1)

func expect(condition: bool, message: String = "") -> bool:
	checks += 1
	if condition:
		return true
	failures += 1
	var text := message if message != "" else "断言失败"
	_messages.append(text)
	push_error("[FAIL] " + text)
	print("  [FAIL] " + text)
	return false

## 打印汇总并返回退出码：0=全部通过，1=有失败。
func finish(name: String) -> int:
	if failures == 0:
		print("[%s] 通过 (%d 项断言)" % [name, checks])
		# Windows 的 OS.execute 可能错解中文编码，汇总器使用 ASCII 完成标记。
		print("[%s] passed (%d checks)" % [name, checks])
		return 0
	print("[%s] 失败: %d/%d 项断言未通过" % [name, failures, checks])
	for text in _messages:
		print("  - " + text)
	return 1
