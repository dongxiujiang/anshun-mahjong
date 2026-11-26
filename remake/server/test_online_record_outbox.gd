extends SceneTree
const Submitter = preload("res://src/runtime/RecordSubmitter.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var folder := OS.get_environment("DONGXIU_TEST_RECORD_DIR")
	var retry := OS.get_environment("DONGXIU_TEST_RECORD_RETRY") == "1"
	var sender := Submitter.new()
	root.add_child(sender)
	sender.configure("4".repeat(64) if retry else "3".repeat(64), "online", OS.get_environment("DONGXIU_RECORD_URL"), folder.path_join("outbox"))
	if not retry:
		sender.enqueue(1)
		sender.complete(JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("real0.json"))))
	var file := folder.path_join("outbox/" + "3".repeat(64) + "-1.json")
	for frame in 10000:
		await process_frame
		OS.delay_msec(1)
		if (retry and not FileAccess.file_exists(file)) or (not retry and sender.state(1).get("status") == "failed"):
			if not retry and not FileAccess.file_exists(file): break
			if retry and not sender.state(1).is_empty(): break
			print("Online outbox tests passed: ", "restored with original identity" if retry else "saved on HTTP failure")
			sender.queue_free()
			await process_frame
			quit()
			return
	printerr("Online outbox did not reach the expected durable state")
	quit(1)
