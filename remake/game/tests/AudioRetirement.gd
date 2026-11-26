extends RefCounted


static func release_app(app: Node, tree: SceneTree) -> bool:
	var resources: Array[WeakRef] = []
	for player in app.find_children("*", "AudioStreamPlayer", true, false):
		if player.stream != null:
			resources.append(weakref(player.stream))
		if player.has_stream_playback():
			resources.append(weakref(player.get_stream_playback()))
	app.queue_free()
	# AudioServer retires stopped streams on mixer callbacks, not accelerated frames.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 2000:
		await tree.process_frame
		OS.delay_msec(5)
		if Time.get_ticks_msec() - started >= 250 and resources.all(func(item): return item.get_ref() == null):
			return true
	return false
