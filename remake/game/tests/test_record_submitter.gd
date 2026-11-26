extends SceneTree
const Submitter = preload("res://src/runtime/RecordSubmitter.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func until(predicate: Callable) -> bool:
	for step in 3000:
		if predicate.call(): return true
		await process_frame
		OS.delay_msec(1)
	return false

func respond(server: TCPServer, body: Dictionary) -> bool:
	if not await until(func(): return server.is_connection_available()): return false
	var peer := server.take_connection()
	if not await until(func(): peer.poll(); return peer.get_available_bytes() > 0): return false
	peer.get_data(peer.get_available_bytes())
	var payload := JSON.stringify(body).to_utf8_buffer()
	var header := ("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % payload.size()).to_utf8_buffer()
	peer.put_data(header + payload)
	for frame in 30:
		await process_frame
		OS.delay_msec(1)
	peer.disconnect_from_host()
	return true

func _run() -> void:
	check(Submitter.safe_url("https://mj.example.org/v1/records"), "HTTPS service accepted")
	for value in ["http://example.org/v1/records", "http://127.0.0.1:80@evil.test/v1/records", "http://localhost.evil.test/x", "https://user:secret@host/x", "http://127.0.0.1:99999/x"]:
		check(not Submitter.safe_url(value), "reject insecure or ambiguous upload destination")
	var tcp := TCPServer.new()
	check(tcp.listen(0, "127.0.0.1") == OK, "local HTTP acknowledgement fixture starts")
	var sender := Submitter.new()
	root.add_child(sender)
	var folder := "user://submitter-test-" + str(Time.get_ticks_usec())
	sender.configure("test-instance", "solo", "http://127.0.0.1:%d/v1/records" % tcp.get_local_port(), folder)
	check(not sender.enqueue(0) and sender.enqueue(1), "only real rounds may request submission")
	check(sender.state(1).status == "queued" and not tcp.is_connection_available(), "pending match never sends a private partial record")
	# Body validation belongs to the authority and the service's real replay verifier.
	sender.complete({"round_number": 1, "checksum": "fixture-checksum", "wall": []})
	check(await respond(tcp, {"status": "stored", "id": "test-instance:1", "checksum": "wrong"}), "HTTP acknowledgement received")
	check(await until(func(): return sender.state(1).status == "failed"), "wrong server digest cannot report success")
	check(FileAccess.file_exists(folder.path_join("test-instance-1.json")), "failed submission remains saved")
	check(sender.enqueue(1), "failed submission can be retried")
	check(await respond(tcp, {"status": "stored", "id": "test-instance:1", "checksum": "fixture-checksum"}), "matching durable acknowledgement received")
	check(await until(func(): return sender.state(1).status == "stored"), "only matching acknowledgement marks success")
	check(not FileAccess.file_exists(folder.path_join("test-instance-1.json")), "successful submission clears its outbox file")
	check(sender.enqueue(1) and sender.state(1).status == "stored", "repeat click does not resubmit a stored record")
	check(sender.enqueue(2), "second round explicitly requests submission")
	sender.complete({"round_number": 2, "checksum": "second-checksum", "wall": []})
	check(await respond(tcp, {"status": "error"}), "failed round receives a non-success acknowledgement")
	check(await until(func(): return sender.state(2).status == "failed"), "failed round remains eligible for retry")
	# Advancing to the next round must not orphan an already requested completed record.
	sender.enqueue(3)
	check(await respond(tcp, {"status": "stored", "id": "test-instance:2", "checksum": "second-checksum"}), "new round retries an earlier failed completed round")
	check(await until(func(): return sender.state(2).status == "stored"), "earlier round retry receives its own acknowledgement")
	sender.complete({"round_number": 3, "checksum": "third-checksum", "wall": []})
	check(await respond(tcp, {"status": "error"}), "third round saved for process-restart recovery")
	check(await until(func(): return sender.state(3).status == "failed"), "third round failure acknowledged")
	sender.queue_free()
	await process_frame
	var other_service := TCPServer.new()
	check(other_service.listen(0, "127.0.0.1") == OK, "different service fixture starts")
	var unrelated := Submitter.new()
	root.add_child(unrelated)
	unrelated.configure("different-instance", "solo", "http://127.0.0.1:%d/v1/records" % other_service.get_local_port(), folder)
	for frame in 6: await process_frame
	check(not other_service.is_connection_available() and unrelated.get("_payloads").is_empty(), "saved private records never redirect to a newly configured service")
	unrelated.queue_free()
	other_service.stop()
	var malformed := FileAccess.open(folder.path_join("broken.json"), FileAccess.WRITE)
	malformed.store_string(JSON.stringify({"format": 1, "endpoint": "http://127.0.0.1:%d/v1/records" % tcp.get_local_port(), "payload": {"mode": "solo", "room_instance_id": "test-instance", "record": {"round_number": "3", "checksum": "bad"}}}))
	malformed.close()
	var restored := Submitter.new()
	root.add_child(restored)
	restored.configure("different-instance", "solo", "http://127.0.0.1:%d/v1/records" % tcp.get_local_port(), folder)
	check(await respond(tcp, {"status": "stored", "id": "test-instance:3", "checksum": "third-checksum"}), "new process recovers requested completed record with original identity")
	check(await until(func(): return not FileAccess.file_exists(folder.path_join("test-instance-3.json"))), "recovered record removed only after exact server acknowledgement")
	check(restored.state(3).is_empty(), "old room upload cannot mark new room round as submitted")
	check(FileAccess.file_exists(folder.path_join("broken.json")), "unrecognised saved data is neither sent nor silently deleted")
	restored.queue_free()
	tcp.stop()
	DirAccess.remove_absolute(folder.path_join("broken.json"))
	DirAccess.remove_absolute(folder)
	await process_frame
	print("Record submitter: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
