extends SceneTree
## Headless warm-up: load autoloads/script cache once so the first room starts
## without paying the full Godot boot cost. It never hosts a room.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var network := root.get_node_or_null("Network")
	if network != null:
		# Touch the same autoload graph used by RoomServer.
		print("[warmup] network=", network.name)
	quit(0)
