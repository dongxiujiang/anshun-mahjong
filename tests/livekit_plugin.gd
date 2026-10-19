extends SceneTree
## Verify the native LiveKit GDExtension is loaded before building a release.

const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	t.expect(ClassDB.class_exists("LiveKitRoom"), "LiveKitRoom native class is registered")
	t.expect(ClassDB.class_exists("LiveKitAudioSource"), "LiveKitAudioSource native class is registered")
	t.expect(ClassDB.class_exists("LiveKitAudioStream"), "LiveKitAudioStream native class is registered")
	t.expect(ClassDB.class_exists("LiveKitAudioProcessingModule"), "LiveKit audio processing native class is registered")
	var room = ClassDB.instantiate("LiveKitRoom")
	t.expect(room != null and room.has_method("connect_to_room"), "LiveKit room can be instantiated")
	quit(t.finish("livekit_plugin"))
