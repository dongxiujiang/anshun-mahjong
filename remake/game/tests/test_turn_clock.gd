extends SceneTree

const TurnClock = preload("res://src/session/TurnClock.gd")

var _failures := 0


func _initialize() -> void:
	_test_discard_clock()
	_test_response_clocks()
	_test_custom_durations()
	_test_stale_prompt()
	if _failures == 0:
		print("Turn clock tests passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _test_discard_clock() -> void:
	var clock := TurnClock.new("room-1")
	_check(clock.begin_prompt(1, 2, TurnClock.Kind.DISCARD, [1]), "Open a normal discard prompt")
	_check(clock.timing_for(1, 2, 1, 50000).get("phase") == "waiting_animation", "The animation owns its full time")
	_check(clock.tick(1, 2, 50000).is_empty(), "A waiting animation cannot time out")
	_check(clock.animation_finished(1, 2, 1, 50000), "The authority starts the clock when the seat can act")
	_check(clock.timing_for(1, 2, 1, 50000).get("remaining_ms") == 10000, "Default main discard time is 10 seconds")
	_check(not clock.animation_finished(1, 2, 1, 51000), "Duplicate animation completion does not restart the timer")
	_check(not clock.timing_for(1, 2, 1, 56999).get("reminder"), "No reminder before the last three seconds")
	var warning := clock.timing_for(1, 2, 1, 57000)
	_check(warning.get("reminder") and warning.get("remaining_ms") == 3000, "Reminder starts with exactly three seconds of main time left")
	var grace := clock.timing_for(1, 2, 1, 60000)
	_check(grace.get("phase") == "grace" and grace.get("remaining_ms") == 5000 and grace.get("reminder"), "Main time flows into five seconds of grace with the reminder still on")
	_check(clock.tick(1, 2, 64999).is_empty(), "AI has no timeout intent during the grace period")
	var due := clock.tick(1, 2, 65000)
	_check(due == [{
		"room_instance_id": "room-1", "round_number": 1, "prompt_id": 2,
		"seat": 1, "action": "ai_discard", "deadline_ms": 65000,
	}], "At the deadline the clock emits one identified AI discard intent")
	_check(clock.timing_for(1, 2, 1, 65500).get("reminder"), "An intent is not a successful discard")
	_check(clock.tick(1, 2, 65500).is_empty(), "Repeated ticks do not issue a second AI action")
	_check(clock.action_accepted(1, 2, 1), "The authority reports a successful action")
	_check(clock.timing_for(1, 2, 1, 65500).is_empty(), "The reminder ends with the accepted discard")
	_check(not clock.action_accepted(1, 2, 1), "Repeat acceptance does not affect the prompt")

	_check(clock.begin_prompt(1, 3, TurnClock.Kind.DISCARD, [1]), "The same player opens a later discard prompt normally")
	_check(clock.animation_finished(1, 3, 1, 70000), "The later prompt has its own animation start")
	_check(clock.tick(1, 3, 70001).is_empty(), "The previous timeout grants no continuing AI control")
	_check(clock.action_accepted(1, 3, 1), "A human can complete the later prompt")
	_check(clock.tick(1, 3, 100000).is_empty(), "Accepted human discard leaves no AI intent")


func _test_response_clocks() -> void:
	var clock := TurnClock.new("room-2")
	_check(clock.begin_prompt(1, 5, TurnClock.Kind.RESPONSE, [0, 2, 3]), "Authority opens one response prompt for eligible seats")
	_check(not clock.animation_finished(1, 5, 1, 100), "An ineligible seat has no response clock")
	_check(clock.animation_finished(1, 5, 0, 100), "First response clock starts at its animation end")
	_check(clock.animation_finished(1, 5, 2, 600), "Second response clock has its own animation end")
	_check(clock.animation_finished(1, 5, 3, 600), "Third response clock can start at the same instant")
	_check(not clock.timing_for(1, 5, 0, 2099).get("reminder"), "No premature response reminder")
	_check(clock.timing_for(1, 5, 0, 2100).get("reminder"), "Response reminder starts at three seconds left")
	_check(clock.action_accepted(1, 5, 2), "An accepted choice stops just its own response clock")
	_check(clock.tick(1, 5, 5099).is_empty(), "Response clocks get the full default five seconds")
	var first_due := clock.tick(1, 5, 5100)
	_check(first_due.size() == 1 and first_due[0].get("seat") == 0 and first_due[0].get("action") == "pass", "Only the expired response seat gets a pass intent")
	_check(clock.timing_for(1, 5, 3, 5100).get("remaining_ms") == 500, "The later response still has time")
	_check(clock.action_accepted(1, 5, 0), "An accepted pass retires its clock")
	var second_due := clock.tick(1, 5, 5600)
	_check(second_due.size() == 1 and second_due[0].get("seat") == 3, "The other response expires only at its own deadline")
	_check(clock.tick(1, 5, 5601).is_empty(), "Neither accepted choices nor issued intents fire again")
	_check(clock.begin_prompt(1, 6, TurnClock.Kind.RESPONSE, [0]), "A declared-ready self-draw decision also uses a response clock")
	_check(clock.animation_finished(1, 6, 0, 6000), "Start the self-draw decision after the draw animation")
	var self_draw := clock.tick(1, 6, 11000)
	_check(self_draw.size() == 1 and self_draw[0].get("action") == "pass", "Self-draw expiry requests a pass without a normal-discard grace window")


func _test_custom_durations() -> void:
	var clock := TurnClock.new("room-3")
	_check(clock.begin_prompt(1, 10, TurnClock.Kind.DISCARD, [2], 12000), "Use the configured main discard duration")
	_check(clock.animation_finished(1, 10, 2, 100), "Begin custom discard clock")
	_check(clock.timing_for(1, 10, 2, 12100).get("remaining_ms") == 5000, "Additional discard grace remains fixed at five seconds")
	_check(clock.tick(1, 10, 17099).is_empty(), "The configured discard window is still live")
	_check(clock.tick(1, 10, 17100).size() == 1, "Configured main duration plus fixed grace is the new deadline")
	_check(clock.begin_prompt(1, 11, TurnClock.Kind.RESPONSE, [0], 8000), "Use the independent configured response duration")
	_check(clock.animation_finished(1, 11, 0, 20000), "Begin custom response clock")
	_check(clock.timing_for(1, 11, 0, 25000).get("reminder"), "Custom response still warns at three seconds left")
	_check(clock.tick(1, 11, 27999).is_empty() and clock.tick(1, 11, 28000).size() == 1, "Custom response has no grace period")


func _test_stale_prompt() -> void:
	var clock := TurnClock.new("room-4")
	_check(clock.begin_prompt(3, 20, TurnClock.Kind.DISCARD, [1]), "Register the current turn")
	_check(clock.animation_finished(3, 20, 1, 100), "Open the current turn clock")
	_check(not clock.begin_prompt(3, 20, TurnClock.Kind.DISCARD, [1]), "A duplicate prompt cannot extend its deadline")
	_check(clock.begin_prompt(3, 21, TurnClock.Kind.RESPONSE, [1]), "A newer prompt supersedes the old one")
	_check(not clock.animation_finished(3, 20, 1, 200), "An old animation cannot start a new timer")
	_check(not clock.action_accepted(3, 20, 1), "An old acceptance cannot retire a newer prompt")
	_check(clock.tick(3, 20, 15100).is_empty(), "Superseded timer emits no stale intent")
	_check(clock.clear_prompt(3, 21), "The authority can transition to a phase without any timer")
	_check(not clock.begin_prompt(3, 21, TurnClock.Kind.RESPONSE, [1]), "A cleared prompt cannot reopen")
	_check(not clock.animation_finished(3, 21, 1, 15101), "A cleared prompt ignores late animation completion")
	_check(clock.end_round(3), "Settle the round")
	_check(not clock.begin_prompt(3, 22, TurnClock.Kind.DISCARD, [1]), "An ended round cannot acquire a new clock")
	_check(clock.begin_prompt(4, 1, TurnClock.Kind.DISCARD, [1]), "A new round can reuse prompt numbers")
	_check(not clock.end_round(3), "An old settlement cannot retire the new round")
	_check(clock.animation_finished(4, 1, 1, 15102), "The new round clock still starts")
	_check(clock.end_round(4), "Settle a round with an active clock")
	_check(clock.tick(4, 1, 30102).is_empty() and clock.timing_for(4, 1, 1, 30102).is_empty(), "The settled round has no intent or reminder")
