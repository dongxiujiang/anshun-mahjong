extends RefCounted
## 教打异步工作线程：主线程只生成公开快照，线程内重建 RoundState 后分析。

const TEACHING := preload("res://scripts/core/AiTeaching.gd")
const ROUND := preload("res://scripts/core/RoundState.gd")

var _thread: Thread
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _job: Dictionary = {}
var _result: Dictionary = {}
var _result_token := 0
var _next_token := 0
var _cancel_before := 0
var _stopping := false

func submit(round, seat: int, level: String) -> int:
	if _stopping or round == null: return 0
	if not _start():
		return 0
	var snapshot: Dictionary = round.serialize_for_seat(seat)
	_mutex.lock()
	_next_token += 1
	_job = {"token": _next_token, "snapshot": snapshot, "seat": seat, "level": level}
	_result = {}
	_result_token = 0
	_mutex.unlock()
	_wake.post()
	return _next_token

func take_result(token: int) -> Dictionary:
	if token <= 0: return {}
	_mutex.lock()
	var value: Dictionary = {}
	if _result_token == token and not _result.is_empty():
		value = _result
		_result = {}
		_result_token = 0
	_mutex.unlock()
	return value

func cancel(token: int) -> void:
	if token <= 0: return
	_mutex.lock()
	_cancel_before = maxi(_cancel_before, token)
	if _result_token <= token:
		_result = {}
		_result_token = 0
	_mutex.unlock()

func stop() -> void:
	_mutex.lock()
	_stopping = true
	_job = {}
	_result = {}
	_mutex.unlock()
	_wake.post()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func stop_async(tree: SceneTree) -> void:
	_mutex.lock()
	_stopping = true
	_job = {}
	_result = {}
	_mutex.unlock()
	_wake.post()
	if _thread == null: return
	while _thread != null and _thread.is_alive():
		await tree.process_frame
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func _start() -> bool:
	if _thread != null and _thread.is_alive(): return true
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_thread = Thread.new()
	var error := _thread.start(Callable(self, "_loop"))
	if error != OK:
		_thread = null
		push_error("AI教打线程启动失败：%s" % error)
		return false
	return true

func _loop() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		if _stopping:
			_mutex.unlock()
			return
		var job: Dictionary = _job
		_job = {}
		var token := int(job.get("token", 0))
		_mutex.unlock()
		if token <= 0: continue
		var computed := _compute(job)
		_mutex.lock()
		if not _stopping and token >= _cancel_before:
			_result = computed
			_result_token = token
		_mutex.unlock()

func _compute(job: Dictionary) -> Dictionary:
	var clone = ROUND.new()
	clone.apply_sync(job.get("snapshot", {}))
	var result: Dictionary = TEACHING.recommend(clone, int(job.get("seat", 0)),
		str(job.get("level", "medium")))
	return result
