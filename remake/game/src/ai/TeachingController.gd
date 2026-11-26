extends Node

const Scheduler = preload("res://src/ai/AiScheduler.gd")
const Teaching = preload("res://src/ai/AiTeaching.gd")
signal recommendation_changed(result: Dictionary)

var _worker := Scheduler.new(Teaching.recommend_one)
var _current := {}
var _level := ""

func recommend(full_view: Dictionary, difficulty: String) -> bool:
	var next := Teaching.job_for(full_view, difficulty)
	if next.is_empty():
		cancel()
		return false
	if _current == next and difficulty == _level:
		return true
	cancel()
	if not _worker.enqueue(next, difficulty):
		return false
	_current = next
	_level = difficulty
	return true

func cancel() -> void:
	if not _current.is_empty():
		_worker.cancel_seat(_current.seat)
		_current = {}
		_level = ""
		recommendation_changed.emit({})

func _process(_delta: float) -> void:
	for completed in _worker.poll():
		if completed.job == _current:
			var result: Dictionary = completed.decision.duplicate()
			for key in ["room_instance_id", "round_number", "seat"]:
				result[key] = _current[key]
			recommendation_changed.emit(result)

func _exit_tree() -> void:
	cancel()
	_worker.shutdown()
