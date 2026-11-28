extends RefCounted

const SPRING_RESPONSE := 0.24
const SPRING_DAMPING := 0.72
const PARTICLE_CAPACITY := 36
const PARTICLE_BURST_LIMIT := 18
const PARTICLE_SPEED_MIN := 48.0
const PARTICLE_SPEED_MAX := 145.0
const PARTICLE_LIFE_MIN := 0.30
const PARTICLE_LIFE_MAX := 0.56
const PARTICLE_GRAVITY := 140.0
const PARTICLE_RADIUS := Vector2(1.5, 3.0)
const PARTICLE_SPIN := TAU
const PARTICLE_FOIL_WIDTH := 2.0
const CHICKEN_RIPPLE_DELAY := 0.09

# Quality changes rendering, curves and decoration; temporal boundaries are shared.
const PRESETS := {
	"smooth": {
		# 1. 通用按钮与交互控件
		"button": {
			"press_scale": 0.96,
			"press_duration": 0.06,
			"release_duration": 0.09,
			"hover_scale": 1.0,
			"press_y_offset": 0.0,
			"ease_trans": Tween.TRANS_QUAD,
			"release_trans": Tween.TRANS_QUAD,
			"glow_enabled": false,
		},
		# 2. 局内圆形动作按钮（碰/杠/胡/过）
		"action_button": {
			"enter_duration": 0.10,
			"enter_stagger": 0.0,
			"enter_from_scale": 0.90,
			"enter_trans": Tween.TRANS_QUAD,
			"press_scale": 0.94,
			"press_y_offset": 0.0,
			"press_duration": 0.06,
			"release_duration": 0.09,
			"release_trans": Tween.TRANS_QUAD,
			"win_pulse_enabled": false,
			"particles_enabled": false,
		},
		# 3. 倒计时钟（TurnClockView）
		"turn_clock": {
			"show_duration": 0.10,
			"show_from_scale": 0.92,
			"urgent_pulse_hz": 0.0,        # 流畅档仅切换警示色，不逐帧重绘脉冲
			"tick_marks": false,
			"progress_bead": false,
		},
		# 4. 玩家名片（PlayerBadge）
		"player_badge": {
			"turn_pulse_enabled": false,   # 流畅档改用静态高亮金边，关闭每帧 _process
			"turn_scale": 1.0,
			"press_scale": 0.97,
		},
		# 5. 页面 / 面板 / 弹窗 / 抽屉
		"panel": {
			"screen_in_duration": 0.14,
			"ease_trans": Tween.TRANS_QUAD,
			"ui_tween_limit": 6,
			"screen_in_offset_y": 8.0,
			"modal_in_duration": 0.14,
			"modal_out_duration": 0.10,
			"modal_from_scale": 0.96,
			"modal_to_scale": 0.96,
			"backdrop_in_duration": 0.14,
			"modal_in_trans": Tween.TRANS_QUAD,
			"drawer_duration": 0.14,
			"backdrop_alpha": 0.56,
			"card_stagger": 0.0,           # 两档同时显现，不因画质延迟操作入口
			"shadow_enabled": false,
		},
		# 6. 局内轻提示与辅助浮层（TingAssistantOverlay / AI横幅）
		"overlay": {
			"toast_in": 0.10,
			"toast_out": 0.18,
			"toast_offset_y": -6.0,
			"popup_in": 0.09,
			"popup_out": 0.08,
			"popup_offset_y": 6.0,
			"badge_in": 0.12,
			"drag_hint_in": 0.08,
			"drag_ready_scale": 1.0,
		},
		# 7. 牌的 3D 动作（严守 GamePace.ACTION_SECONDS = 0.30s 总节奏）
		"tile": {
			"select_up_duration": 0.08,
			"select_down_duration": 0.075,
			"select_up_trans": Tween.TRANS_QUAD,
			"drag_shift_duration": 0.09,
			"drag_settle_duration": 0.10,
			"drag_settle_trans": Tween.TRANS_QUAD,
			"drag_follow_smoothing": 0.0,  # 0 = 直接跟随，零额外插值
			"discard_duration": 0.30,
			"discard_arc_h": 0.36,
			"chicken_arc_h": 0.52,
			"draw_duration": 0.30,
			"draw_arc_h": 0.42,
			"meld_duration": 0.28,
			"add_kong_duration": 0.30,
			"add_kong_arc_h": 0.72,
			"insert_duration": 0.30,
			"sort_duration": 0.30,
			"sort_trans": Tween.TRANS_QUAD,
			"settle_flip_duration": 0.24,
			"settle_flip_trans": Tween.TRANS_QUAD,
			"opening_trans": Tween.TRANS_QUAD,
		},
		# 8. 场景转场（TableTransition）
		"transition": {
			"enter_duration": 0.24,
			"exit_duration": 0.20,
			"high_y_mult": 1.06,           # 极轻俯视落位，绝无鱼眼
			"fov_mult": 1.0,               # 锁定目标 FOV，零畸变
			"crossfade_duration": 0.16,
			"warmup_frames": 1,            # 渲染就绪 1 帧后起跑
			"dice_audio_wait_visual": true,
		},
		# 9. 特效与 3D 装饰（ActionEffectsStage / WinFeedback / FlipChickenReveal / TableView）
		"fx": {
			"ripple_enabled": false,
			"shake_enabled": false,
			"shake_scale": 0.0,
			"discard_marker_bob": false,   # 流畅档保持静止高可见金标，关 _process
			"callout_duration": 0.78,
			"callout_in_duration": 0.10,
			"callout_scale_overshoot": 1.0,
			"callout_glow": false,
			"callout_particles": 0,
			"win_duration": 0.95,
			"win_ring_count": 1,
			"win_particles": 0,
			"flip_in_duration": 0.20,
			"flip_from_scale": 0.94,
			"flip_trans": Tween.TRANS_QUAD,
			"flip_related_stagger": 0.0,
			"flip_particles": 0,
			"decorative_msaa": Viewport.MSAA_DISABLED,
			"backdrop_detail": false,
		},
	},
	"detail": {
		# 1. 通用按钮与交互控件（iOS 弹簧触感）
		"button": {
			"press_scale": 0.94,
			"press_duration": 0.06,
			"release_duration": 0.09,
			"hover_scale": 1.02,
			"press_y_offset": 1.5,
			"ease_trans": Tween.TRANS_CUBIC,
			"release_trans": Tween.TRANS_BACK,
			"glow_enabled": true,
		},
		# 2. 局内圆形动作按钮（同步弹出 + 弹簧回弹 + 胡牌呼吸光晕）
		"action_button": {
			"enter_duration": 0.10,
			"enter_stagger": 0.0,
			"enter_from_scale": 0.76,
			"enter_trans": Tween.TRANS_BACK,
			"press_scale": 0.91,
			"press_y_offset": 1.8,
			"press_duration": 0.06,
			"release_duration": 0.09,
			"release_trans": Tween.TRANS_BACK,
			"win_pulse_enabled": true,
			"particles_enabled": true,
		},
		# 3. 倒计时钟（鎏金罗盘怀表 + 光珠）
		"turn_clock": {
			"show_duration": 0.10,
			"show_from_scale": 0.84,
			"urgent_pulse_hz": 7.2,
			"tick_marks": true,
			"progress_bead": true,
		},
		# 4. 玩家名片（柔和金边呼吸 + 按压轻弹）
		"player_badge": {
			"turn_pulse_enabled": true,
			"turn_scale": 1.02,
			"press_scale": 0.96,
		},
		# 5. 页面 / 面板 / 弹窗 / 抽屉（iOS 弹性卡片 + 同步出现）
		"panel": {
			"screen_in_duration": 0.14,
			"ease_trans": Tween.TRANS_CUBIC,
			"ui_tween_limit": 16,
			"screen_in_offset_y": 14.0,
			"modal_in_duration": 0.14,
			"modal_out_duration": 0.10,
			"modal_from_scale": 0.91,
			"modal_to_scale": 0.95,
			"backdrop_in_duration": 0.14,
			"modal_in_trans": Tween.TRANS_BACK,
			"drawer_duration": 0.14,
			"backdrop_alpha": 0.62,
			"card_stagger": 0.0,
			"shadow_enabled": true,
		},
		# 6. 局内轻提示与辅助浮层
		"overlay": {
			"toast_in": 0.10,
			"toast_out": 0.18,
			"toast_offset_y": -12.0,
			"popup_in": 0.09,
			"popup_out": 0.08,
			"popup_offset_y": 10.0,
			"badge_in": 0.12,
			"drag_hint_in": 0.08,
			"drag_ready_scale": 1.05,
		},
		# 7. 牌的 3D 动作（自然抛物线 + 微回弹落位，守住 0.30s 总时长）
		"tile": {
			"select_up_duration": 0.08,
			"select_down_duration": 0.075,
			"select_up_trans": Tween.TRANS_BACK,
			"drag_shift_duration": 0.09,
			"drag_settle_duration": 0.10,
			"drag_settle_trans": Tween.TRANS_BACK,
			"drag_follow_smoothing": 28.0, # 指数平滑阻尼跟踪，丝滑跟手不滞后
			"discard_duration": 0.30,
			"discard_arc_h": 0.52,
			"chicken_arc_h": 0.78,
			"draw_duration": 0.30,
			"draw_arc_h": 0.58,
			"meld_duration": 0.28,
			"add_kong_duration": 0.30,
			"add_kong_arc_h": 0.92,
			"insert_duration": 0.30,
			"sort_duration": 0.30,
			"sort_trans": Tween.TRANS_CUBIC,
			"settle_flip_duration": 0.24,
			"settle_flip_trans": Tween.TRANS_BACK,
			"opening_trans": Tween.TRANS_CUBIC,
		},
		# 8. 场景转场（短促克制俯视入座 + 交叉淡入，无鱼眼畸变）
		"transition": {
			"enter_duration": 0.24,
			"exit_duration": 0.20,
			"high_y_mult": 1.18,           # 温和俯视入座（原 1.65 过高）
			"fov_mult": 1.0,               # 取消 1.65× 鱼眼变焦畸变
			"crossfade_duration": 0.16,
			"warmup_frames": 1,
			"dice_audio_wait_visual": true,
		},
		# 9. 特效与 3D 装饰（池化涟漪 + 柔和震屏 + 轻量金箔粒子）
		"fx": {
			"ripple_enabled": true,
			"shake_enabled": true,
			"shake_scale": 1.0,
			"discard_marker_bob": true,
			"callout_duration": 0.78,
			"callout_in_duration": 0.10,
			"callout_scale_overshoot": 1.06,
			"callout_glow": true,
			"callout_particles": 10,
			"win_duration": 0.95,
			"win_ring_count": 2,
			"win_particles": 18,
			"flip_in_duration": 0.20,
			"flip_from_scale": 0.86,
			"flip_trans": Tween.TRANS_BACK,
			"flip_related_stagger": 0.0,
			"flip_particles": 14,
			"decorative_msaa": Viewport.MSAA_2X,
			"backdrop_detail": true,
		},
	},
}

static var current_quality := "detail"
# Pools discard particles from earlier detail sessions, even if they missed a frame.
static var particle_generation := 0

static func normalize_quality(value: String) -> String:
	return "detail" if value == "detail" else "smooth"

static func set_quality(value: String) -> String:
	var quality := normalize_quality(value)
	if current_quality != quality and quality == "smooth":
		particle_generation += 1
	current_quality = quality
	return quality

static func is_detail(value: String = "") -> bool:
	return (current_quality if value.is_empty() else normalize_quality(value)) == "detail"

static func section(category: String, quality_override: String = "") -> Dictionary:
	var quality := current_quality if quality_override.is_empty() else normalize_quality(quality_override)
	return PRESETS[quality].get(category, {})

static func value(category: String, key: String, fallback: Variant = null, quality_override: String = "") -> Variant:
	return section(category, quality_override).get(key, fallback)
