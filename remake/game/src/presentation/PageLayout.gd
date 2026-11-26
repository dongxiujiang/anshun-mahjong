extends RefCounted
## The actual menu controls are shared by the game and the designer.
const Hud = preload("res://src/presentation/HudLayout.gd")
const PAGES := {"home":"大厅", "profile_edit":"个人资料", "online":"在线入口", "lan":"局域网入口", "room":"房间座位", "settings":"设置", "update":"软件更新", "leave":"离开确认", "reconnect":"连接恢复"}

static func canonical(page:String)->String:
	return "profile_edit" if page=="profile_setup" else page

static func valid(pages: Variant) -> bool:
	if not pages is Dictionary or pages.size()>PAGES.size()+1:return false
	for page in pages:
		if not PAGES.has(canonical(page)) or not Hud.valid(pages[page],true):return false
	return true

static func collect(root: Control, controls: Dictionary, path: String = "") -> void:
	if root.has_meta("page_label"):controls[path]=root
	if root is BaseButton or root is LineEdit or root is Range or (root is Label and not root.text.is_empty()):
		controls[path]=root
		return
	var children:=root.get_children()
	var counts:={}
	for child in children:
		if not child is Control or child is ScrollBar:continue
		var kind:String=child.get_class()
		var index:int=counts.get(kind,0);counts[kind]=index+1
		collect(child,controls,path+"/"+str(child.get_meta("page_id",kind+str(index))))

static func label(control: Control) -> String:
	if control.has_meta("page_label"):return str(control.get_meta("page_label"))
	if not control.accessibility_name.is_empty():return control.accessibility_name
	if control.get_parent() is GridContainer and control.get_index()>0:
		var previous=control.get_parent().get_child(control.get_index()-1)
		if previous is Label and not control is Label:return previous.text
	if control is Label or control is Button:return control.text.replace("\n"," · ").left(36)
	return "输入框" if control is LineEdit else ("数值" if control is Range else "内容")

static func scroll_offset(control: Control) -> Vector2:
	var result:=Vector2.ZERO
	var parent:=control.get_parent()
	while parent is Control:
		if parent is ScrollContainer:result+=Vector2(parent.scroll_horizontal,parent.scroll_vertical)
		parent=parent.get_parent()
	return result

static func capture(control: Control, safe: Control) -> Dictionary:
	var center:=safe.get_global_transform_with_canvas().affine_inverse()*control.get_global_rect().get_center()+scroll_offset(control)
	return {"x":clampf(center.x/safe.size.x,0,16),"y":clampf(center.y/safe.size.y,0,16),"scale":1.0,
		"width":control.size.x/safe.size.x,"height":control.size.y/safe.size.y}

static func apply(items: Dictionary, controls: Dictionary, safe: Control) -> void:
	var display:=items.duplicate(true)
	for key in display:
		if controls.has(key):
			var offset:=scroll_offset(controls[key])/safe.size
			display[key].x-=offset.x;display[key].y-=offset.y
	Hud.apply(display,controls,safe)

static func visible(control: Control, safe: Control) -> bool:
	var bounds:=control.get_global_rect().intersection(safe.get_global_rect())
	var parent:=control.get_parent()
	while parent is Control:
		if parent.clip_contents:bounds=bounds.intersection(parent.get_global_rect())
		parent=parent.get_parent()
	return bounds.has_area()

static func scrolls(node: Node) -> Array:
	var result:=[]
	if node is ScrollContainer:result.append(node)
	for child in node.get_children():result.append_array(scrolls(child))
	return result
