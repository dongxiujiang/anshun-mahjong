extends PanelContainer

const UI := preload("res://src/app/AppTheme.gd")
const Seats := preload("res://src/domain/Seats.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")
const TileArt := preload("res://src/presentation/TileArt.gd")
const DicePair=preload("res://src/app/DicePairView.gd")
const POSITIONS := ["我", "下", "对", "上"]
const WINDS := ["东", "南", "西", "北"]

var _body: VBoxContainer
var _table_overlay:=false
var next_button: Button
var peek_button: Button
var ready_hint: Label
var _footer: HBoxContainer
var _rows_info:=[]
var _headings:=[]


func show_result(settlement: Dictionary, mode: String, return_to_seats: Callable, next_round: Callable, record: Control = null, table_overlay:bool=false, peek_toggle: Callable = Callable()) -> void:
	_table_overlay=table_overlay
	if table_overlay:add_theme_stylebox_override("panel",UI.elevated_card(Color("#0d2922f2"),14,10,Color("#cfa95a"),2,10))
	if is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	_body = VBoxContainer.new()
	_rows_info.clear();_headings.clear()
	if table_overlay:_body.add_theme_constant_override("separation",4)
	add_child(_body)
	var ledger: Dictionary = settlement.ledger
	var draw: bool = ledger.winners.is_empty()
	var title := "流局" if draw else "本局结算"
	if table_overlay:
		var heading:=HBoxContainer.new();_body.add_child(heading)
		_headings.append(heading)
		var reason:=HBoxContainer.new();reason.custom_minimum_size.x=100;heading.add_child(reason)
		var red:int=settlement.round_meta.get("die",0);var white:int=settlement.round_meta.get("die_white",0)
		if red in range(1,7) and red==white:
			var pair:=DicePair.new();pair.values=[red,white];reason.add_child(pair)
		elif int(ledger.multiplier)==2:reason.add_child(UI.label("上局流局",16,Color("#e6cf8d")))
		var names:=PackedStringArray()
		for winner in ledger.winners:names.append("你" if int(winner)==int(settlement.get("viewer_seat",-1)) else str(settlement.seats[int(winner)].nickname))
		var winner_title:=UI.label("流局" if draw else ("、".join(names)+("自摸" if settlement.round_meta.get("self_draw",false) else "胡牌")),21,Color("#f3d98e"))
		winner_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;winner_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;heading.add_child(winner_title)
		var balance:=Control.new();balance.custom_minimum_size.x=100;heading.add_child(balance)
		var header:=HBoxContainer.new();_body.add_child(header)
		_headings.append(header)
		var player:=UI.label("玩家",14,UI.MUTED);player.custom_minimum_size.x=92;header.add_child(player)
		var items:=UI.label("得分项",14,UI.MUTED);items.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(items)
		var total:=UI.label("单家 / 增减",14,UI.MUTED);total.custom_minimum_size.x=108;header.add_child(total)
	else:_body.add_child(UI.label("%s　×%s" % [title, ledger.multiplier], 26))
	var rows := VBoxContainer.new()
	if table_overlay:rows.add_theme_constant_override("separation",3)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if table_overlay:_body.add_child(rows)
	else:
		var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;_body.add_child(scroll);scroll.add_child(rows)
	var viewer := int(settlement.get("viewer_seat", -1))
	var order := [viewer, Seats.previous(viewer), Seats.opposite(viewer), Seats.next(viewer)] if viewer >= 0 else [0, 1, 2, 3]
	for seat in order:
		_add_row(rows, settlement, int(seat), viewer)
	if record != null:
		_body.add_child(record)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.add_theme_constant_override("separation", 8)
	_footer = controls
	_body.add_child(controls)
	ready_hint = UI.label("", 13, UI.MUTED)
	ready_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls.add_child(ready_hint)
	peek_button = null
	if table_overlay:
		var leave_btn := UI.button("离开", return_to_seats)
		leave_btn.custom_minimum_size = Vector2(74, 38)
		controls.add_child(leave_btn)
		if peek_toggle.is_valid():
			peek_button = UI.button("查看牌面", peek_toggle)
			peek_button.custom_minimum_size = Vector2(92, 38)
			controls.add_child(peek_button)
	else:
		controls.add_child(UI.button("离开房间", return_to_seats))
	if mode == "solo":
		next_button = UI.button("下一局", next_round, true)
	else:
		next_button = UI.button("准备下一局", next_round, true)
		next_button.tooltip_text = "所有在线玩家准备后立即开始下一局"
	next_button.custom_minimum_size = Vector2(108, 38) if table_overlay else Vector2(128, 46)
	controls.add_child(next_button)
	if table_overlay:
		_headings.append(controls)


func update_ready_state(room: Dictionary, viewer_seat: int, mode: String) -> void:
	if not is_instance_valid(next_button) or not is_instance_valid(ready_hint):
		return
	if mode == "solo" or room.is_empty():
		ready_hint.text = ""
		next_button.text = "下一局"
		return
	var seats: Array = room.get("seats", [])
	if seats.size() != 4 or viewer_seat not in range(4):
		return
	var total_humans := 0
	var ready_humans := 0
	var waiting_names := PackedStringArray()
	for seat in 4:
		var m: Dictionary = seats[seat]
		if bool(m.get("connected", false)):
			total_humans += 1
			if bool(m.get("ready", false)):
				ready_humans += 1
			else:
				waiting_names.append("你" if seat == viewer_seat else str(m.get("nickname", "牌友")))
	var mine_ready := bool(seats[viewer_seat].get("ready", false))
	next_button.text = "取消准备" if mine_ready else "准备下一局"
	next_button.theme_type_variation = "" if mine_ready else "PrimaryButton"
	if total_humans <= 1:
		ready_hint.text = "点击准备立即开始下一局"
	elif ready_humans >= total_humans:
		ready_hint.text = "全员已准备，即将开局…"
	else:
		ready_hint.text = "已准备 %d/%d · 等待 %s" % [ready_humans, total_humans, "、".join(waiting_names)]


func _add_row(rows: VBoxContainer, settlement: Dictionary, seat: int, viewer: int) -> void:
	var ledger: Dictionary = settlement.ledger
	var occupant: Dictionary = settlement.seats[seat]
	var card := PanelContainer.new()
	var is_winner: bool = ledger.winners.has(seat)
	var row_fill := (Color("#234334") if is_winner else Color("#123028")) if _table_overlay else (Color("#2f493b") if is_winner else Color("#24392f"))
	var row_border := Color("#dfba68") if is_winner else (Color("#587564") if _table_overlay else UI.BORDER)
	card.add_theme_stylebox_override("panel", UI.card(row_fill, 6 if _table_overlay else 9, 4 if _table_overlay else 8, row_border, 2 if is_winner else 1))
	rows.add_child(card)
	var columns := HBoxContainer.new()
	card.add_child(columns)
	var who := VBoxContainer.new()
	if _table_overlay:who.add_theme_constant_override("separation",1)
	who.custom_minimum_size.x = 92 if _table_overlay else 108
	var position: String = POSITIONS[Seats.relative(viewer, seat)] if viewer >= 0 else WINDS[seat]
	var nickname: String = occupant.get("nickname", "")
	if nickname.is_empty():
		nickname = "%s家人机" % WINDS[seat]
	who.add_child(UI.label(("你" if seat==viewer else nickname) if _table_overlay else "%s · %s" % [position, nickname], 14 if _table_overlay else 16,Color("#e6cf8d") if _table_overlay else UI.INK))
	var status: String = "胡牌" if ledger.winners.has(seat) else ledger.status[seat]
	who.add_child(UI.label((position+"　" if _table_overlay and seat!=viewer else "")+status, 12 if _table_overlay else 15, UI.MUTED))
	columns.add_child(who)
	var items := HFlowContainer.new()
	if _table_overlay:items.add_theme_constant_override("h_separation",3);items.add_theme_constant_override("v_separation",2)
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(items)
	var item_rows: Array = ledger.items[seat].duplicate()
	item_rows.sort_custom(func(a, b): return a.opponents.size() > b.opponents.size())
	if _table_overlay:item_rows=display_items(item_rows)
	for entry in item_rows:
		_add_item(items, entry, seat)
	if item_rows.is_empty():
		items.add_child(UI.label("无计分项", 14 if _table_overlay else 16, UI.MUTED))
	var score := VBoxContainer.new()
	if _table_overlay:score.add_theme_constant_override("separation",1)
	score.custom_minimum_size.x = 108 if _table_overlay else 128
	var delta := int(ledger.deltas[seat])
	if _table_overlay:
		var unit:=0
		for item in ledger.items[seat]:unit+=int(item.amount)
		score.add_child(UI.label("%s　%s"%[delta_text(unit),delta_text(delta)],16,Color("#7bdda5") if delta>=0 else Color("#e1908c")))
	else:score.add_child(UI.label("%s　累计 %d" % [delta_text(delta), int(settlement.scores[seat])], 17))
	var relative_totals := PackedStringArray()
	for other in ([viewer, Seats.previous(viewer), Seats.opposite(viewer), Seats.next(viewer)] if viewer >= 0 else [0, 1, 2, 3]):
		if other == seat:
			continue
		var label: String = POSITIONS[Seats.relative(viewer, other)] if viewer >= 0 else WINDS[other]
		var amount := int(ledger.pairwise[seat][other])
		relative_totals.append("%s%+d" % [label, amount])
	if not _table_overlay:score.add_child(UI.label(" ".join(relative_totals),13,UI.MUTED))
	else:score.tooltip_text=" ".join(relative_totals)
	columns.add_child(score)
	_rows_info.append({"card":card,"who":who,"score":score,"items":items,"columns":columns})


static func display_items(items: Array) -> Array:
	var groups:=[];var lookup:={}
	for item in items:
		var opponents:Array=item.opponents.duplicate();opponents.sort()
		var key:=JSON.stringify([item.kind,item.label,opponents,signf(float(item.amount))])
		if not lookup.has(key):
			lookup[key]=groups.size();groups.append(item.duplicate(true))
		else:
			var group:Dictionary=groups[lookup[key]];group.amount+=item.amount
			group.tiles.append_array(item.get("tiles",[]));group.tile_ids.append_array(item.get("tile_ids",[]))
	return groups

func _add_item(flow: HFlowContainer, item: Dictionary, owner: int) -> void:
	var group: BoxContainer = HBoxContainer.new()
	group.add_theme_constant_override("separation", 3)
	var faces: BoxContainer=group
	if _table_overlay:
		faces=HBoxContainer.new();faces.alignment=BoxContainer.ALIGNMENT_CENTER;faces.add_theme_constant_override("separation",0);group.add_child(faces)
	var is_charge: bool = str(item.get("kind", "")) == "charge"
	for tile_value in item.get("tiles", []):
		var face := PanelContainer.new()
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if is_charge:
			# 冲锋鸡 / 冲锋金鸡横着摆放，与牌桌上的实体冲锋鸡朝向保持完全一致
			face.custom_minimum_size = Vector2(32, 24) if _table_overlay else Vector2(33, 24)
			face.add_theme_stylebox_override("panel", UI.card(Color("#f3ead3"), 3, 2, Color("#e2b250"), 1))
		else:
			face.custom_minimum_size = Vector2(24, 32) if _table_overlay else Vector2(24, 33)
			face.add_theme_stylebox_override("panel", UI.card(Color("#ede6d3"), 3, 2, Color("#cfbd99")))
		faces.add_child(face)
		var texture := TileArt.face_sideways(str(tile_value)) if is_charge else TileArt.face(str(tile_value))
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			face.add_child(icon)
		else:
			face.add_child(UI.label(tile_name(str(tile_value)), 12, Color("#22332a")))
	var opponents := PackedStringArray()
	if item.opponents.size() < 3:
		for offset in [3, 2, 1]:
			if item.opponents.has(posmod(owner - offset, 4)):
				opponents.append(POSITIONS[offset])
	var suffix := "（%s）" % "／".join(opponents) if not opponents.is_empty() else ""
	var label:String=item.label.replace("自摸基础分","自摸")
	var caption:=UI.label((delta_text(int(item.amount)) if not item.get("tiles",[]).is_empty() else label+delta_text(int(item.amount))) if _table_overlay else "%s%+d%s" % [item.label,int(item.amount),suffix],15 if _table_overlay else 15)
	group.tooltip_text="%s%+d%s"%[item.label,int(item.amount),suffix]
	if _table_overlay:caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	group.add_child(caption)
	flow.add_child(group)

func height_for_width(width: float) -> float:
	var style:=get_theme_stylebox("panel")
	var result:float=style.get_minimum_size().y
	for heading in _headings:result+=heading.get_combined_minimum_size().y
	result+=float(_body.get_theme_constant("separation"))*_headings.size()
	for row in _rows_info:
		var available:float=width-style.get_minimum_size().x-row.card.get_theme_stylebox("panel").get_minimum_size().x-row.who.get_combined_minimum_size().x-row.score.get_combined_minimum_size().x-2*row.columns.get_theme_constant("separation")
		var x:=0.0;var line:=0.0;var height:=0.0
		for group in row.items.get_children():
			var extent:Vector2=group.get_combined_minimum_size()
			if x>0 and x+extent.x>available:height+=line+2;x=0;line=0
			x+=extent.x+3;line=maxf(line,extent.y)
		height+=line
		result+=maxf(height,maxf(row.who.get_combined_minimum_size().y,row.score.get_combined_minimum_size().y))+row.card.get_theme_stylebox("panel").get_minimum_size().y
	result+=3*maxi(0,_rows_info.size()-1)
	return result


static func tile_name(value: String) -> String:
	if not Catalog.valid_value(value):
		return ""
	var suit: String = {"wan": "万", "tiao": "条", "tong": "筒"}[value.left(-1)]
	return value.right(1) + suit


static func delta_text(delta: int) -> String:
	return "+%d" % delta if delta > 0 else str(delta)
