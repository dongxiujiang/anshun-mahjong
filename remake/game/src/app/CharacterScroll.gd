extends ScrollContainer
## Native touch scrolling plus the same drag gesture with a desktop mouse.
var _pressed:=false
var _dragging:=false
var _origin:=Vector2.ZERO
var _scroll_start:=0
var _finger:=-1
var _touch_card:Button
func _ready()->void:
	scroll_deadzone=12
	visibility_changed.connect(func():
		if not is_visible_in_tree():_pressed=false;_dragging=false;_finger=-1;_touch_card=null)
func _input(event:InputEvent)->void:
	if not is_visible_in_tree():return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _finger>=0 or not get_global_rect().has_point(event.position):return
			_finger=event.index;_origin=event.position;_scroll_start=scroll_horizontal;_dragging=false
			_touch_card=_card_at(event.position)
		elif event.index==_finger:
			_finger=-1
			if not _dragging and is_instance_valid(_touch_card) and _card_at(event.position)==_touch_card:
				_touch_card.grab_focus();_touch_card.pressed.emit()
			_dragging=false;_touch_card=null
		else:return
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index==_finger:
		_move(event.position);get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.device==-1:return
		if event.pressed:
			_pressed=get_global_rect().has_point(event.position);_dragging=false
			_origin=event.position;_scroll_start=scroll_horizontal
		else:
			_pressed=false
			if _dragging:
				_dragging=false;get_viewport().set_input_as_handled()
				var picker=get_child(0)
				if picker.has_method("_select"):picker._select(picker.selected_id)
	elif event is InputEventMouseMotion and _pressed:
		_move(event.position)
		if _dragging:
			get_viewport().set_input_as_handled()

func _move(point:Vector2)->void:
	var distance:=point-_origin
	if absf(distance.x)>12 and absf(distance.x)>absf(distance.y):_dragging=true
	if _dragging:scroll_horizontal=_scroll_start-roundi(distance.x)

func _card_at(point:Vector2)->Button:
	if not get_global_rect().has_point(point):return null
	for card in get_child(0)._cards:
		if card.get_global_rect().has_point(point):return card
	return null
