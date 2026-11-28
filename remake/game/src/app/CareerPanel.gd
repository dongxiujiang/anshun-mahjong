extends VBoxContainer
## 精美新中式本地战绩与安顺大牌成就图鉴面板。

const UI := preload("res://src/app/AppTheme.gd")
const Progress := preload("res://src/app/PlayerProgress.gd")

signal closed

func build(progress: Progress, nickname: String) -> void:
	add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	add_child(head)
	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	title_col.add_child(UI.label("牌友战绩 · %s" % nickname, 28, UI.GOLD_BRIGHT))
	title_col.add_child(UI.label("当前段位：%s　｜　图鉴进度：%d / %d" % [progress.rank_title(), progress.unlocked.size(), Progress.BADGE_ORDER.size()], 16, UI.MUTED))
	head.add_child(title_col)
	head.add_child(UI.button("返回", func(): closed.emit()))

	# 核心数据四宫格
	var metrics := GridContainer.new()
	metrics.columns = 4
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_theme_constant_override("h_separation", 10)
	metrics.add_theme_constant_override("v_separation", 10)
	add_child(metrics)
	var cards := [
		["对局总数", str(int(progress.stats.rounds)) + " 局", UI.INK],
		["胡牌胜率", "%d%% (%d胜)" % [progress.win_rate_percent(), int(progress.stats.wins)], Color("#87e8b7")],
		["最高连胜", str(int(progress.stats.best_streak)) + " 连胜", UI.GOLD_BRIGHT],
		["最高单局", ("+" if int(progress.stats.best_round_gain) > 0 else "") + str(int(progress.stats.best_round_gain)) + " 分", Color("#ffcf77")],
		["自摸次数", str(int(progress.stats.self_draws)) + " 次", UI.INK],
		["累计捉鸡", str(int(progress.stats.chickens_hit)) + " 只", UI.GOLD],
		["冲锋鸡", str(int(progress.stats.charge_chickens)) + " 次", Color("#ff9d78")],
		["金鸡次数", str(int(progress.stats.gold_chickens)) + " 次", UI.GOLD_BRIGHT],
	]
	for item in cards:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UI.card(Color("#18362c"), 10, 10, Color("#3e6454"), 1))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		card.add_child(box)
		box.add_child(UI.label(item[0], 14, UI.MUTED))
		box.add_child(UI.label(item[1], 21, item[2]))
		metrics.add_child(card)

	# 8 枚安顺大牌图鉴成就墙
	add_child(UI.label("安顺大牌与捉鸡图鉴", 20, UI.GOLD))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	for id in Progress.BADGE_ORDER:
		var spec: Dictionary = Progress.BADGES[id]
		var got: bool = progress.unlocked.has(id)
		var badge := PanelContainer.new()
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		badge.add_theme_stylebox_override("panel", UI.card(
			Color("#274736") if got else Color("#12241e"),
			10, 10,
			UI.GOLD_BORDER if got else Color("#2f473e"),
			2 if got else 1))
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 3)
		badge.add_child(vbox)
		vbox.add_child(UI.label(("✦ " if got else "◇ ") + str(spec.name), 16, UI.GOLD_BRIGHT if got else UI.MUTED))
		var desc := UI.label(str(spec.desc), 13, UI.INK if got else Color("#78887f"))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)
		grid.add_child(badge)
	UI.MotionFX.animate_stagger_children(metrics.get_children())
	var panel := UI.MotionFX.MotionConfig.section("panel")
	if panel.card_stagger > 0.0:
		for badge in grid.get_children():
			badge.modulate.a = 0.0
		# Start the gallery as the first metric lands, leaving room for the page entrance.
		var sequence := create_tween()
		sequence.tween_interval(panel.screen_in_duration)
		sequence.tween_callback(UI.MotionFX.animate_stagger_children.bind(grid.get_children()))
	else:
		UI.MotionFX.animate_stagger_children(grid.get_children())
