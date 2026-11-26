extends GridContainer

const UI := preload("res://src/app/AppTheme.gd")
const Art := preload("res://src/app/CharacterArt.gd")
const GOLD := Color("#ffce72")

var selected_id := 1
var _cards: Array[Button] = []
var _markers: Array[PanelContainer] = []

func build(chosen: int) -> void:
	columns = 8
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 10)
	var group := ButtonGroup.new()
	var normal := UI.elevated_card(Color("#142f26"), 14, 0, Color("#3f6755"), 1, 3)
	var hover := UI.elevated_card(Color("#1d4235"), 14, 0, Color("#7ea892"), 2, 4)
	var selected := UI.elevated_card(Color("#224839"), 14, 0, GOLD, 2, 6)
	var focus := UI.card(Color.TRANSPARENT, 14, 0, UI.INK, 2)
	for id in range(1, Art.Packs.ORDER.size()+1):
		var card := Button.new()
		card.name = "Character%02d" % id
		card.accessibility_name = Art.title(id)
		card.tooltip_text=Art.title(id)
		card.custom_minimum_size = Vector2(184, 140)
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		card.size_flags_vertical = SIZE_EXPAND_FILL
		card.toggle_mode = true
		card.button_group = group
		card.add_theme_stylebox_override("normal", normal)
		card.add_theme_stylebox_override("hover", hover)
		card.add_theme_stylebox_override("pressed", selected)
		card.add_theme_stylebox_override("hover_pressed", selected)
		card.add_theme_stylebox_override("focus", focus)
		card.pressed.connect(_select.bind(id))
		add_child(card)
		_cards.append(card)
		_add_portrait(card, id)
		var marker := PanelContainer.new()
		marker.mouse_filter = MOUSE_FILTER_IGNORE
		marker.add_theme_stylebox_override("panel", UI.card(GOLD, 14, 0, GOLD))
		var label := UI.label("✓", 18, Color("#1a3228"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.add_child(label)
		card.add_child(marker)
		marker.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
		marker.offset_left = -35
		marker.offset_right = -7
		marker.offset_top = 7
		marker.offset_bottom = 35
		_markers.append(marker)
	_select(clampi(chosen, 1, Art.Packs.ORDER.size()))
	for index in _cards.size():
		var card := _cards[index]
		if index % columns > 0:
			card.focus_neighbor_left = card.get_path_to(_cards[index - 1])
		if index % columns < columns - 1 and index+1<_cards.size():
			card.focus_neighbor_right = card.get_path_to(_cards[index + 1])
		if index >= columns:
			card.focus_neighbor_top = card.get_path_to(_cards[index - columns])
		elif index+columns<_cards.size():
			card.focus_neighbor_bottom = card.get_path_to(_cards[index + columns])

func focus_selected() -> void:
	UI.focus_later(_cards[selected_id - 1])

func _add_portrait(card: Button, id: int) -> void:
	var frame := Control.new()
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	card.add_child(frame)
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	frame.offset_left = 6
	frame.offset_top = 6
	frame.offset_right = -6
	frame.offset_bottom = -6
	var caption:=UI.label(Art.title(id),17)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	frame.add_child(caption)
	caption.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE);caption.offset_top=-24
	var portrait := TextureRect.new()
	portrait.texture = Art.avatar(id)
	if portrait.texture==null:
		portrait.free()
		var pending:=UI.label("图片待生成",17,UI.MUTED)
		pending.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;pending.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		frame.add_child(pending);pending.set_anchors_and_offsets_preset(PRESET_FULL_RECT);pending.offset_bottom=-24
		return
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	var crop:=Control.new();crop.mouse_filter=MOUSE_FILTER_IGNORE;crop.clip_contents=true
	frame.add_child(crop);frame.move_child(crop,0);crop.set_anchors_and_offsets_preset(PRESET_FULL_RECT);crop.offset_bottom=-24
	crop.add_child(portrait)
	portrait.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

func _select(id: int) -> void:
	selected_id = id
	for index in _markers.size():
		var active := index == id - 1
		_cards[index].set_pressed_no_signal(active)
		_markers[index].visible = active
