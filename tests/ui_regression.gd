extends SceneTree
## UI/layout and client-storage regression that is cheap to run headlessly.
const H := preload("res://tests/test_harness.gd")
const SESSIONS := preload("res://scripts/core/NetworkSessionStore.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var guide: Control = load("res://scripts/ui/RuleGuide.gd").new()
	root.add_child(guide)
	await process_frame
	t.expect(guide.panel.size.y >= 760.0, "rule panel is tall enough for long pages")
	var body_bottom: float = guide.body_label.position.y + guide.body_label.size.y
	var examples: Control = guide.panel.get_node("Examples")
	t.expect(body_bottom <= examples.position.y, "rule body does not overlap example tiles")
	t.expect(examples.position.y + examples.size.y <= guide.page_label.position.y, "examples do not overlap page controls")
	t.expect(guide.body_label.get_theme_font_size("font_size") <= 28, "long rule pages use a compact font")
	guide.queue_free()
	await process_frame

	var settings: CanvasLayer = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	root.add_child(settings)
	await process_frame
	t.expect(settings.ai_strength_buttons.has("weak"), "AI strength weak button exists")
	t.expect(not settings.ai_strength_buttons["weak"].disabled, "weak AI remains selectable")
	t.expect(settings.ai_strength_buttons["medium"].disabled and settings.ai_strength_buttons["strong"].disabled, "unimplemented AI strengths are disabled")
	settings.queue_free()
	await process_frame

	var overlay: Control = load("res://scripts/ui/ConnectionOverlay.gd").new()
	root.add_child(overlay)
	await process_frame
	t.expect(overlay._panel.size == Vector2(760, 360), "connection card uses the shared dialog dimensions")
	t.expect(overlay._title.get_theme_font_size("font_size") == 32, "connection title uses the shared title size")
	t.expect(overlay._retry_button.get_theme_font_size("font_size") == 28, "connection actions use the shared button size")
	overlay.show_reconnecting(2, 5)
	t.expect(overlay.visible and not overlay._retry_button.visible and overlay._leave_button.text == "取消并返回大厅", "reconnect progress has one clear exit action")
	overlay.show_error("测试断线")
	t.expect(overlay.visible and overlay._retry_button.visible and overlay._leave_button.text == "返回大厅", "connection error offers retry and return")
	overlay.queue_free()
	await process_frame

	var path := "res://build/ui_regression/network.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var session := {"host": "127.0.0.1", "port": 7594, "number": "001234",
		"name": "测试", "player_name": "玩家", "token": "a".repeat(64), "online": true}
	t.expect(SESSIONS.write_session(path, session) == OK, "encrypted session writes")
	t.expect(SESSIONS.read_session(path) == session, "encrypted session round-trips")
	var plain := FileAccess.get_file_as_string(path)
	t.expect(not plain.contains(session.token), "plaintext config never contains the bearer token")
	t.expect(FileAccess.file_exists(path + ".session"), "encrypted session companion exists")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".session"))

	var voice: Node = load("res://scripts/online/OnlineVoiceChat.gd").new()
	voice._rx[2] = {"next": 999, "packets": {}}
	voice.reset_seat(2)
	t.expect(not voice._rx.has(2), "seat voice jitter buffer can be reset")
	voice.free()
	var gme: Node = load("res://scripts/online/GMEVoiceChat.gd").new()
	gme.reset_seat(2)
	gme.free()

	await H.quit_cleanly(self, t.finish("ui_regression"))
