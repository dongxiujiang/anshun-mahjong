extends RefCounted
## The designer and Main share these safe-area coordinates. Container layout remains intact.
const LABELS := {
	"settings": "设置按钮", "leave": "离开按钮", "auto_play": "AI代打按钮", "teaching": "教打按钮",
	"restore": "恢复按钮", "microphone": "麦克风", "clock": "倒计时钟", "notice": "操作提示",
	"sorting": "排序按钮",
	"advice": "教打提示", "actions": "操作按钮整体", "arrangement": "理牌提示",
	"player/0": "本家 · 姓名与分数", "player/1": "下家 · 姓名与分数",
	"player/2": "对家 · 姓名与分数", "player/3": "上家 · 姓名与分数",
	"win/portrait": "胡牌效果 · 人物", "win/title": "胡牌效果 · 文字", "win/names": "胡牌效果 · 玩家名",
	"settlement": "结算面板", "next_round": "下一局按钮",
}

static func valid(items: Variant, page: bool = false) -> bool:
	if not items is Dictionary or items.size() > (256 if page else 64): return false
	for key in items:
		if page:
			if not key is String or key.length()>240 or key.is_empty():return false
			for character in key:
				if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-/".contains(character):return false
		elif not LABELS.has(key) and not str(key).begins_with("action/"): return false
		var row: Variant = items[key]
		if not row is Dictionary: return false
		for field in ["x", "y", "scale"]:
			var value: Variant = row.get(field)
			if not (value is int or value is float) or not is_finite(float(value)): return false
		if row.x < 0 or row.x > (16 if page else 1) or row.y < 0 or row.y > (16 if page else 1) or row.scale < 0.5 or row.scale > 2: return false
		if row.has("visible") and not row.visible is bool: return false
		if row.has("button_scale") and (not (row.button_scale is float or row.button_scale is int) or not is_finite(float(row.button_scale)) or row.button_scale<0.5 or row.button_scale>2):return false
		for field in ["width","height"]:
			if row.has(field) and (not (row[field] is float or row[field] is int) or not is_finite(float(row[field])) or row[field] <= 0 or row[field] > 1): return false
	return true

static func apply(items: Dictionary, controls: Dictionary, safe: Control) -> void:
	if not is_instance_valid(safe) or safe.size.x <= 0 or safe.size.y <= 0: return
	# Parents (the action strip) precede individually edited buttons.
	for key in controls:
		var control: Control = controls[key]
		if not is_instance_valid(control): continue
		control.offset_transform_enabled = true
		control.offset_transform_visual_only = false
		control.offset_transform_position = Vector2.ZERO
		control.offset_transform_scale = Vector2.ONE
		if str(key).begins_with("action/"): continue
		var row: Dictionary = items.get(key,{})
		if key not in ["actions","settlement"]:
			if row.has("width") or row.has("height"):
				if not control.has_meta("hud_minimum"):control.set_meta("hud_minimum",control.custom_minimum_size)
				if control.get_parent() is Container:
					if not control.has_meta("hud_size_flags"):control.set_meta("hud_size_flags",[control.size_flags_horizontal,control.size_flags_vertical])
					control.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;control.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
				var extent:=Vector2(float(row.get("width",control.size.x/safe.size.x))*safe.size.x,float(row.get("height",control.size.y/safe.size.y))*safe.size.y)
				var minimum:Vector2=extent.max(Vector2(48,48) if key=="clock" else control.get_meta("hud_minimum"))
				if not control.custom_minimum_size.is_equal_approx(minimum):control.custom_minimum_size=minimum
				control.size=extent.max(control.get_combined_minimum_size())
			elif control.has_meta("hud_minimum"):
				control.custom_minimum_size=control.get_meta("hud_minimum");control.size=control.get_combined_minimum_size();control.remove_meta("hud_minimum")
				if control.has_meta("hud_size_flags"):
					var flags:Array=control.get_meta("hud_size_flags");control.size_flags_horizontal=int(flags[0]);control.size_flags_vertical=int(flags[1]);control.remove_meta("hud_size_flags")
		var hidden: bool = not items.get(key,{}).get("visible",true)
		_set_hidden_input(control,hidden)
		control.modulate.a = 0.0 if hidden else 1.0
		if not items.has(key): continue
		var parent_scale: Vector2 = control.get_parent().get_global_transform_with_canvas().get_scale()
		var desired := safe.get_global_transform_with_canvas() * (safe.size * Vector2(row.x, row.y))
		var original := control.get_global_rect().get_center()
		if key == "actions":
			var width: float = row.get("width",600.0/safe.size.x)*safe.size.x
			desired.x += (width-control.size.x)*float(row.scale)*0.5
		if str(key).begins_with("player/") or key=="next_round":
			var half:=control.size*parent_scale*float(row.scale)*0.5
			var bounds:=safe.get_global_rect()
			desired=desired.clamp(bounds.position+half,bounds.end-half)
		control.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
		control.offset_transform_scale = Vector2.ONE * float(row.scale)
		control.offset_transform_position = (desired - original) / parent_scale

static func _set_hidden_input(node: Node, hidden: bool) -> void:
	if node is Control:
		if hidden:
			if not node.has_meta("hud_mouse_filter"):
				node.set_meta("hud_mouse_filter",node.mouse_filter);node.set_meta("hud_focus_mode",node.focus_mode)
			node.mouse_filter=Control.MOUSE_FILTER_IGNORE;node.focus_mode=Control.FOCUS_NONE
		elif node.has_meta("hud_mouse_filter"):
			node.mouse_filter=int(node.get_meta("hud_mouse_filter"));node.focus_mode=int(node.get_meta("hud_focus_mode"))
			node.remove_meta("hud_mouse_filter");node.remove_meta("hud_focus_mode")
	for child in node.get_children():_set_hidden_input(child,hidden)

static func item_rect(key: String, items: Dictionary, controls: Dictionary, safe: Control) -> Rect2:
	var control: Control = controls[key]
	if key != "actions": return control.get_global_rect()
	var row: Dictionary = items.get(key,capture(control,safe))
	var extent := safe.size*Vector2(row.get("width",600.0/safe.size.x),row.get("height",90.0/safe.size.y))*float(row.scale)
	return Rect2(safe.global_position+safe.size*Vector2(row.x,row.y)-extent*0.5,extent)

static func capture(control: Control, safe: Control) -> Dictionary:
	var center: Vector2 = safe.get_global_transform_with_canvas().affine_inverse() * control.get_global_rect().get_center()
	return {"x": clampf(center.x / safe.size.x, 0, 1), "y": clampf(center.y / safe.size.y, 0, 1),
		"scale": control.offset_transform_scale.x if control.offset_transform_enabled else 1.0}
