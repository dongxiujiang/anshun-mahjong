extends "res://tests/test_play_controls.gd"

func _run() -> void:
	var path:="user://settings-overlay-%s.cfg"%Time.get_ticks_usec()
	app=Main.instantiate();app.table_play_only=false;app._settings=Settings.new(path)
	app._settings.save_profile("设置检查",1);root.add_child(app)
	app._choose_mode("solo")
	check(await until(func():return app._choices().get("actions",[]).has("discard") and app._table._opening==null and app._table._motions.is_empty()),"start real solo turn before settings")
	var host=app._client._host
	var prompt:int=app._round_projection.prompt_id
	app._open_settings()
	var panel=app._room_settings_panel
	check(panel.has_method("show_operation_reminder"),"settings exposes a dedicated return-to-table reminder")
	if not panel.has_method("show_operation_reminder"):
		await AudioRetirement.release_app(app,self);DirAccess.remove_absolute(path)
		print("Settings overlay: %d checks, %d failures"%[checks,failures]);quit(1);return
	check(panel.tabs.get_tab_count()==2 and panel.tabs.get_tab_title(0)=="对局" and panel.tabs.get_tab_title(1)=="声音","settings has exactly the approved two pages")
	check(app._board.visible and app._table.visible,"settings retains the actual table behind its panel")
	check(not app._table.is_processing_input() and not app._table.is_processing_unhandled_input(),"settings blocks table input")
	check(host._paused_at>=0,"solo settings pause the authority")
	panel.tabs.current_tab=1;await process_frame
	check(panel._fields.voice_pack.is_visible_in_tree() and not panel._fields.difficulty.is_visible_in_tree(),"sound page exposes audio controls only")
	var before:Dictionary=panel.values()
	panel.tabs.current_tab=0;await process_frame
	check(panel.values()==before,"switching pages retains both pages' unsaved values")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app._close_settings()
	check(host._paused_at>=0,"closing settings in background must not resume solo")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(host._paused_at<0 and app._round_projection.prompt_id==prompt,"foreground resumes the same solo operation")
	panel=app._room_settings_panel
	app._open_settings();panel=app._room_settings_panel
	panel.show_operation_reminder(true)
	check(panel._operation_notice.visible and button("返回牌桌")!=null,"dedicated reminder is visible outside scrolling fields")
	button("返回牌桌").pressed.emit()
	check(app._screen=="play" and host._paused_at<0,"return-to-table button closes settings and resumes the same game")
	await AudioRetirement.release_app(app,self);DirAccess.remove_absolute(path)
	print("Settings overlay: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
