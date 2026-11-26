extends Node
const Sort = preload("res://src/presentation/HandSort.gd")
const Scheduler = preload("res://src/ai/AiScheduler.gd")
signal completed(result: Dictionary)
var _worker := Scheduler.new(Sort.calculate)
var _current := {}

func request(scope: Dictionary, view: Dictionary, suits: Array, priority: String) -> bool:
	cancel()
	var safe := Sort.safe_view(view,suits,priority)
	_current = scope.duplicate(true)
	_current.view = safe
	return _worker.enqueue(_current,"low")
func cancel() -> void:
	if not _current.is_empty(): _worker.cancel_seat(int(_current.seat))
	_current = {}
func _process(_delta: float) -> void:
	for item in _worker.poll():
		if item.job == _current:
			var result: Dictionary = item.decision.duplicate(true)
			result.scope = _current.duplicate(true); result.scope.erase("view")
			_current = {}; completed.emit(result)
func _exit_tree() -> void: cancel(); _worker.shutdown()
