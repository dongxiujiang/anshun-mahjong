extends RefCounted
## 牌桌统一视觉配置：设计坐标使用 2280×1280，PC 和 Android 共用。
## 改牌面倍率、按钮、颜色或间距优先改这里；不包含计分规则。

const DESIGN_SIZE := Vector2(2280, 1280)
const TABLE_CENTER := Vector2(720, 760)
const LANDSCAPE_SIZE := Vector2(2280, 1280)
const LANDSCAPE_CENTER := Vector2(1140, 650)
const LANDSCAPE_RESULT_SIZE := Vector2(2200, 1232)
const TILE_UNIT := 1.1
const RIVER_TILE_UNIT := 1.25
const PLAYER_TILE_UNIT := 1.35
const OWN_PLAYER_TILE_UNIT := 1.60
const OWN_HAND_TILE_UNIT := OWN_PLAYER_TILE_UNIT * 1.5
const ACTION_BUTTON_SIZE := Vector2(118, 84)
const DISCARD_BUTTON_SIZE := ACTION_BUTTON_SIZE * 1.5
const SETTINGS_BUTTON_SIZE := Vector2(144, 72)
const ACTION_HAND_GAP := 56.0
const RESULT_TILE_UNIT := 1.6
const RESULT_CARD_SIZE := Vector2(1320, 1496)
const RESULT_TOGGLE_SIZE := Vector2(228, 88)
const RESULT_TOGGLE_LOCAL_POSITION := Vector2(1166, 22)
const NEXT_ROUND_BUTTON_SIZE := Vector2(440, 126)
const TILE_GAP := 4.0
const EXPOSED_HAND_GAP := 36.0
const DRAW_GAP := 24.0
const RIVER_POSITION := Vector2(-180, 180)
const RIVER_SIZE := Vector2(360, 228)
const ROTATIONS := [0.0, -PI / 2.0, PI, PI / 2.0]
const WINDS := ["东", "南", "西", "北"]
const INK := Color("#edf3ee")
const MUTED := Color("#aac5b9")
const GOLD := Color("#edcc80")
const SCORE_GAIN := Color("#63d391")
const SCORE_LOSS := Color("#e27878")
const SAFE_MARGIN := 28.0
const TOUCH_MARGIN := 16.0
const VISUAL_ANIMATIONS := true

# 几何与间距（均为设计画布像素）。
const TABLE_BOUNDS := Rect2(24, 80, 2232, 1120)
const LEGACY_TABLE_BOUNDS := Rect2(24, 72, 1392, 1376)
const SIDE_EXPOSED_Y := 1010.0
const OWN_EXPOSED_Y := 430.0
const OPPONENT_EXPOSED_Y := 458.0
const SIDE_EXPOSED_LEFT := -494.0
const EXPOSED_LEFT := -1000.0
const SIDE_OVERFLOW_LEFT := -544.0
const SIDE_OVERFLOW_RIGHT := 530.0
const OVERFLOW_RIGHT := 1000.0
const SIDE_RIVER_POSITION := Vector2(-300, 390)
## 弃牌牌面继续使用 TILE_UNIT；这里只扩大容器的可视宽度，给多行弃牌
## 留出更清晰的间距。东西两家旋转后第二轴就是屏幕横向空间。
const SIDE_RIVER_SIZE := Vector2(720, 190)
const MAIN_RIVER_POSITION := Vector2(-350, 180)
const MAIN_RIVER_SIZE := Vector2(700, 180)
const RIVER_COLUMNS := 10
const RIVER_ROWS := 18
const RIVER_INSET := 4.0
const RIVER_CONTENT_MARGIN := 16.0
const ACTION_SEPARATION := 12
const ACTION_EDGE_GAP := 16.0
const SETTINGS_EDGE_GAP := 24.0
const SETTINGS_TOP_GAP := 4.0
const EXPOSED_ROW_GAP := 16.0
const EXPOSED_ROW_STEP := 24.0
const MELD_GROUP_GAP := 10.0
const EXPOSED_MAX_ROWS := 20
const AVATAR_POSITIONS := [Vector2(622, 854), Vector2(814, 682), Vector2(770, 606), Vector2(578, 794)]
const SCORE_LABEL_POSITIONS := [Vector2(682, 854), Vector2(810, 742), Vector2(602, 606), Vector2(566, 678)]
const HIDDEN_STATUS_POSITIONS := [Vector2(500, 1312), Vector2(1140, 1072), Vector2(500, 1152), Vector2(20, 1072)]
const CENTER_SIZE := Vector2(168, 168)
const CENTER_SCORE_SIZE := Vector2(200, 44)
const CENTER_SCORE_OFFSETS := [Vector2(0, 138), Vector2(224, 0), Vector2(0, -138), Vector2(-224, 0)]
const CENTER_SCORE_FONT_SIZE := 28
const CENTER_NAME_FONT_SIZE := 22
const CENTER_DEALER_SIZE := Vector2(28, 28)
const TURN_LIGHT_COLOR := Color("#fff0aa")
const TURN_LIGHT_SPREAD := 26.0

# 结算卡片：行网格、牌组间距和按钮留白。
const RESULT_GRID_ORIGIN := Vector2(32, 112)
const RESULT_GRID_STRIDE := Vector2(1080, 438)
const RESULT_ROW_SIZE := Vector2(1056, 426)
const RESULT_TOGGLE_EDGE_GAP := Vector2(250, 22)
const RESULT_BOTTOM_GAP := 24.0
const RESULT_DETAILS_TOP := 76.0
const RESULT_GROUP_GAP := Vector2i(20, 14)
const RESULT_TILE_GAP := 8.0
const RESULT_SCORE_WIDTH := 66.0
const RESULT_GROUP_MIN_WIDTH := 152.0

# 字号、圆角和触控。
const DEFAULT_FONT_SIZE := 18
const BUTTON_FONT_SIZE := 21
const ACTION_FONT_SIZE := 42
const SETTINGS_FONT_SIZE := 32
const NEXT_ROUND_FONT_SIZE := 38
const READY_NEXT_ROUND_FONT_SIZE := 34
const BUTTON_RADIUS := 18
const RESULT_RADIUS := 24
const TILE_INPUT_DEBOUNCE_MS := 100

# 统一调色板：背景、牌桌、按钮、结算与禁用牌面。
const TRANSPARENT_FILL := Color(0, 0, 0, 0)
const BACKGROUND := Color("#141d1b")
const TABLE_FRAME := Color("#293430")
const TABLE_FRAME_BORDER := Color("#42524b")
const FELT := Color("#174f3c")
const FELT_BORDER := Color("#688275")
const FELT_TEXTURE_TINT := Color(0.58, 0.8, 0.66, 0.07)
const FELT_INNER_BORDER := Color("#39725a")
const HEADER_LINE := Color("#38453f")
const CENTER_BACKGROUND := Color("#15382e")
const CENTER_BORDER := Color("#618373")
const AVATAR_BACKGROUND := Color("#263f35")
const AVATAR_BORDER := Color("#61786b")
const ACTIVE_WIND := Color("#3b6150")
const DEALER_BACKGROUND := Color("#b84b43")
const DEALER_BORDER := Color("#edb29a")
const DICE_FACE := Color("#f1f3e9")
const DICE_BORDER := Color("#b2bfb3")
const DICE_RED := Color("#bc453e")
const DICE_DOT := Color("#243d32")
const BUTTON_PRIMARY_INK := Color("#203b2d")
const BUTTON_NORMAL := Color("#345344")
const BUTTON_BORDER := Color("#8caa94")
const BUTTON_PRIMARY_HOVER := Color("#f4df9f")
const BUTTON_HOVER := Color("#49735b")
const BUTTON_PRIMARY_PRESSED := Color("#c6aa67")
const BUTTON_PRESSED := Color("#244432")
const BUTTON_DISABLED := Color("#34483b")
const BUTTON_DISABLED_BORDER := Color("#4c6251")
const RESULT_SHADE := Color(0.02, 0.06, 0.04, 0.72)
const RESULT_BACKGROUND := Color("#22392f")
const RESULT_BORDER := Color("#739383")
const RESULT_DETAILS_BACKGROUND := Color("#1b3027")
const DISABLED_TILE_TINT := Color(0.7, 0.76, 0.7)

# 异步视觉动画；速度不影响牌局逻辑。
const DICE_DURATION := preload("res://scripts/autoload/GameConfig.gd").OPENING_DICE_SECONDS
const DEAL_DURATION := preload("res://scripts/autoload/GameConfig.gd").OPENING_DEAL_SECONDS
const DRAW_DURATION := 0.24
const DISCARD_DURATION := 0.28
const MELD_DURATION := 0.28
const REVEAL_DURATION := 0.24
const ANIMATION_TILE_UNIT := 1.15
## Physical-feeling motion constants.  These are visual only; the authoritative
## round never waits for or depends on a tween.
const DEAL_TILE_STAGGER := preload("res://scripts/autoload/GameConfig.gd").OPENING_DEAL_TILE_STAGGER
const DRAW_TILE_STAGGER := 0.018
const DISCARD_TILE_STAGGER := 0.012
const MELD_TILE_STAGGER := 0.026
## After all opening packets land in deal order, players sort the row by hand
## value.  This is a separate visual phase so the deal itself never jumps to a
## sorted slot halfway through the opening.
const SORT_DURATION := preload("res://scripts/autoload/GameConfig.gd").OPENING_SORT_SECONDS
const SORT_TILE_STAGGER := preload("res://scripts/autoload/GameConfig.gd").OPENING_SORT_TILE_STAGGER
const SORT_ARC_HEIGHT := 20.0
const DEAL_ARC_HEIGHT := 34.0
const DRAW_ARC_HEIGHT := 28.0
const DISCARD_ARC_HEIGHT := 22.0
const MELD_ARC_HEIGHT := 18.0
const TILE_SETTLE_LIFT := 3.0
const TILE_SETTLE_SCALE := 1.045
const ANIMATION_TARGETS := [Vector2(1140, 1010), Vector2(1640, 650), Vector2(1140, 430), Vector2(640, 650)]
const ANIMATION_DICE_POSITION := Vector2(1060, 590)
const ANIMATION_DICE_SIZE := Vector2(160, 120)
const ANIMATION_DICE_INK := Color("#f5f3e8")
const ANIMATION_DICE_FONT_SIZE := 46
const DEAL_START_GAP := Vector2(18.0, 22.0)
const DEAL_END_GAP := 6.0
