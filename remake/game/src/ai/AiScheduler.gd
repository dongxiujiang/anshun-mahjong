extends RefCounted
## Each owner has its own queue. A worker reads only its detached observation.

const Ai := preload("res://src/ai/AiPlayer.gd")
const Shanten := preload("res://src/anshun/scoring/Shanten.gd")
const Value := preload("res://src/ai/AiValueModel.gd")

class Request extends RefCounted:
	var job: Dictionary
	var difficulty: String
	var decision: Dictionary
	var calculator: Callable
	var task_id := -1
	var cancelled := false

	func _init(source: Dictionary, level: String, calculate: Callable) -> void:
		job = source.duplicate(true)
		difficulty = level
		calculator = calculate

	func compute() -> void:
		decision = calculator.call(job.view, difficulty)
		Value.release_thread_cache()
		Shanten.release_thread_cache()

var _running := {}
var _queued := {}
var _closed := false
var _calculate: Callable

func _init(calculate: Callable = Callable()) -> void:
	_calculate = calculate if calculate.is_valid() else Ai.decide

func enqueue(job: Dictionary, difficulty: String) -> bool:
	var seat: int = job.get("seat", -1)
	if _closed or seat not in range(4) or difficulty not in Ai.DIFFICULTIES:
		return false
	var view: Dictionary = job.get("view", {})
	if view.get("viewer_seat", -1) != seat or view.get("choices", {}).get("prompt_id", -1) != job.get("prompt_id", -2):
		return false
	var running: Request = _running.get(seat)
	var latest: Request = _queued.get(seat, running)
	if latest != null and not latest.cancelled and latest.difficulty == difficulty and latest.job == job:
		return true
	var request := Request.new(job, difficulty, _calculate)
	if running == null:
		_start(seat, request)
	else:
		running.cancelled = true
		_queued[seat] = request
	return true

func _start(seat: int, request: Request) -> void:
	_running[seat] = request
	request.task_id = WorkerThreadPool.add_task(request.compute)

## 结果仍须交给权威端复验房间、回合、提示及当前控制权。
func poll() -> Array:
	var completed := []
	for seat in _running.keys():
		var request: Request = _running[seat]
		if not WorkerThreadPool.is_task_completed(request.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(request.task_id)
		_running.erase(seat)
		if not request.cancelled and not request.decision.is_empty():
			completed.append({"job": request.job, "decision": request.decision})
		if _queued.has(seat):
			var next: Request = _queued[seat]
			_queued.erase(seat)
			_start(seat, next)
	return completed

func cancel_seat(seat: int) -> void:
	_queued.erase(seat)
	if _running.has(seat):
		_running[seat].cancelled = true

func shutdown() -> void:
	_closed = true
	_queued.clear()
	_join_running(_running)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_join_running(_running)

static func _join_running(running: Dictionary) -> void:
	for request in running.values():
		WorkerThreadPool.wait_for_task_completion(request.task_id)
	running.clear()
