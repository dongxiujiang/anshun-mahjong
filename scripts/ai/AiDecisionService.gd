extends RefCounted
## One long-lived serial worker for AI decisions. The main thread only builds a
## visibility-safe context and consumes a completed decision; the worker never
## touches Node, SceneTree, signals or the live RoundState.

const AI_PLAYER := preload("res://scripts/ai/AiPlayer.gd")

var _thread: Thread
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _jobs: Array = []
var _result: Dictionary = {}
var _result_token := 0
var _next_token := 0
var _cancel_before := 0
var _stopping := false
var _started := false

func start() -> bool:
	_mutex.lock()
	if _stopping:
		_mutex.unlock()
		return false
	if _thread != null and not _thread.is_alive():
		# A GDScript runtime error can terminate the worker between jobs. Drop
		# the dead handle so the next task starts a fresh serial worker.
		_thread = null
		_started = false
	if _thread != null:
		_started = true
		_mutex.unlock()
		return true
	_thread = Thread.new()
	var error := _thread.start(Callable(self, "_worker_loop"))
	if error != OK:
		_thread = null
		_mutex.unlock()
		push_error("AI 工作线程启动失败：%s" % error)
		return false
	_started = true
	_mutex.unlock()
	return true

func submit_turn(context, seat: int) -> int:
	return _submit({"kind": "turn", "context": context, "seat": seat})

func submit_response(context, seat: int, source: int, tile: String, options: Dictionary) -> int:
	return _submit({"kind": "response", "context": context, "seat": seat,
		"source": source, "tile": tile, "options": options.duplicate(true)})

func _submit(job: Dictionary) -> int:
	if _stopping:
		return 0
	if not start():
		return 0
	_mutex.lock()
	_next_token += 1
	job["token"] = _next_token
	# Only the newest pending decision matters. The currently running job is
	# allowed to finish; its token will be ignored by take_result().
	_jobs.clear()
	_jobs.append(job)
	_mutex.unlock()
	_wake.post()
	return _next_token

func take_result(token: int) -> Dictionary:
	_mutex.lock()
	var result: Dictionary = {}
	if _result_token == token and not _result.is_empty():
		result = _result
		_result = {}
		_result_token = 0
	_mutex.unlock()
	return result

func cancel(token: int) -> void:
	_mutex.lock()
	_cancel_before = maxi(_cancel_before, token)
	_jobs = _jobs.filter(func(job): return int(job.get("token", 0)) > token)
	if _result_token <= token:
		_result = {}
		_result_token = 0
	_mutex.unlock()

func stop() -> void:
	_request_stop()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_started = false

## Non-blocking table-leave path: keep the service alive through a coroutine
## until the current compute returns, then join on a frame boundary. The main
## thread is never suspended on wait_to_finish().
func stop_async(tree: SceneTree) -> void:
	_request_stop()
	if _thread == null:
		_started = false
		return
	_finish_stop_later(tree)

func _request_stop() -> void:
	_mutex.lock()
	_stopping = true
	_jobs.clear()
	_result = {}
	_result_token = 0
	_mutex.unlock()
	_wake.post()

func _finish_stop_later(tree: SceneTree) -> void:
	while _thread != null and _thread.is_alive():
		await tree.process_frame
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_started = false

func is_started() -> bool:
	return _started

func _worker_loop() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		if _stopping:
			_mutex.unlock()
			return
		if _jobs.is_empty():
			_mutex.unlock()
			continue
		var job: Dictionary = _jobs.pop_front()
		var token := int(job.get("token", 0))
		_mutex.unlock()
		var computed := _compute(job)
		_mutex.lock()
		if not _stopping and token >= _cancel_before:
			computed["token"] = token
			_result = computed
			_result_token = token
		_mutex.unlock()

func _compute(job: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var context = job.get("context")
	var seat := int(job.get("seat", 0))
	var decision: Dictionary = {}
	if str(job.get("kind", "")) == "turn":
		var ai = AI_PLAYER.new("WorkerAI")
		decision = ai.decide_turn(context, seat)
	else:
		var ai = AI_PLAYER.new("WorkerAI")
		decision = ai.decide_response(context, seat, int(job.get("source", -1)),
			str(job.get("tile", "")), job.get("options", {}))
	return {
		"decision": decision,
		"duration_ms": float(Time.get_ticks_usec() - started) / 1000.0,
	}
