extends SceneTree
## Game-styled previous-room prompt: resume and explicit leave actions.

const H := preload("res://tests/test_harness.gd")
const DIALOG := preload("res://scripts/ui/ResumeRoomDialog.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dialog := DIALOG.new()
	root.add_child(dialog)
	await process_frame
	dialog.open("123456")
	t.expect(dialog.visible, "saved-room prompt is visible")
	t.expect(dialog.find_child("LeaveRoomButton", true, false) != null, "prompt has an explicit leave button")
	t.expect(dialog.find_child("LeaveRoomButton", true, false).text == "离开", "leave button is labelled 离开")
	var resume_seen := [false]
	var leave_seen := [false]
	dialog.confirmed.connect(func(): resume_seen[0] = true)
	dialog.leave_requested.connect(func(): leave_seen[0] = true)
	dialog.find_child("LeaveRoomButton", true, false).pressed.emit()
	t.expect(leave_seen[0], "leave emits leave_requested")
	t.expect(not dialog.visible, "leave closes the prompt")
	dialog.open("123456")
	dialog.confirmed.emit()
	t.expect(resume_seen[0], "resume signal remains compatible with the restart test")
	dialog.queue_free()
	await process_frame
	quit(t.finish("resume_dialog"))
