# 动画速度配置说明

## 概述

本项目支持三档动画速度：

| 速度档位 | 速度键 | 倍率 | 说明 |
|---------|--------|------|------|
| **瞬间** | `instant` | 0.05× | 动画几乎立即完成，用于快速测试和跳过动画 |
| **快** | `fast` | 0.5× | 动画时间减半，快速游戏体验 |
| **正常** | `standard` | 1.0× | 标准动画时间，真实麻将节奏 |

## 实现细节

### 1. 动画速度配置

```gdscript
# scripts/autoload/GameConfig.gd
const ANIMATION_SPEEDS := {"instant": 0.05, "fast": 0.5, "standard": 1.0}
var animation_speed := "standard"

func animation_duration(base: float) -> float:
    return base * float(ANIMATION_SPEEDS.get(animation_speed, 1.0))
```

### 2. UI 速度选项

```gdscript
# scripts/ui/SoundSettings.gd
for item in [["瞬间", "instant"], ["快", "fast"], ["正常", "standard"]]:
    # ...
```

### 3. 动画时长应用

所有动画时长都通过 `GameConfig.animation_duration(base)` 或 `_duration(base)` 计算：

```gdscript
# 发牌动画
var duration := _duration(UI.DEAL_DURATION)
var stagger := _duration(UI.DEAL_TILE_STAGGER)

# 摸牌动画
var duration := _duration(UI.DRAW_DURATION)

# 理牌动画
var duration := _duration(UI.SORT_DURATION)
var delay := _duration(UI.SORT_TILE_STAGGER * float(index))
```

## AI 速度配置（独立配置）

AI 延迟与动画速度独立配置：

| 档位 | 速度键 | 延迟时间 | 说明 |
|------|--------|---------|------|
| **快 1 秒** | `fast` | 1.0 秒 | 最快 AI 决策速度 |
| **中 2 秒** | `medium` | 2.0 秒 | 适中 AI 决策速度 |
| **慢 3 秒** | `slow` | 3.0 秒 | 慢速 AI 决策速度 |

```gdscript
# scripts/autoload/GameConfig.gd
const AI_SPEED_DELAYS := {"fast": 1.0, "medium": 2.0, "slow": 3.0}
var ai_speed := "fast"
```

## 性能优化

### 对象池

`瞬间` 速度下会快速创建和销毁大量 TileView 实例，使用对象池减少 GC 压力：

```gdscript
# scripts/ui/TileViewPool.gd
var _pool: Array[TileView] = []
const MAX_POOL_SIZE := 200

func acquire() -> TileView:
    if _pool.is_empty():
        return TileView.new()
    return _pool.pop_back()

func release(tile: TileView) -> void:
    if _pool.size() >= MAX_POOL_SIZE:
        tile.queue_free()
        return
    tile.reset()
    if tile.get_parent():
        tile.get_parent().remove_child(tile)
    _pool.append(tile)
```

### TileView 重置

```gdscript
# scripts/ui/TileView.gd
func reset() -> void:
    """重置 TileView 为默认状态，用于对象池回收。"""
    set_selected(false)
    set_interactive(false)
    set_winning(false)
    set_highlight(false)
    card = ""
    face_up = false
    table_position = Vector2.ZERO
    modulate = Color.WHITE
    visible = true
```

## 测试覆盖

所有测试文件已更新以使用新的速度键：

- `tests/capture_motion.gd`: 测试 `instant` 和 `standard` 速度
- `tests/capture_table_controls.gd`: 测试 `instant` 和 `standard` 速度
- `tests/smoke_table_layout.gd`: 测试所有三档速度
- `tests/capture_ui.gd`: 使用 `medium` AI 速度
- `tests/OnlineRoom.gd`: 测试在线房间 AI 速度切换

## 注意事项

1. **动画速度**和**AI 速度**是两个独立的配置
2. 动画速度影响所有动画的播放时长
3. AI 速度只影响 AI 玩家的决策延迟
4. `瞬间` 速度主要用于测试和调试，不建议正常游戏使用
5. 对象池会在 `瞬间` 速度下显著提升性能

## 旧速度键迁移

| 旧速度键 | 新速度键 | 说明 |
|---------|---------|------|
| `slow` | `standard` | 慢速改为正常速度 |
| `medium` | `fast` | 中速改为快速 |
| `fast` | `instant` | 快速改为瞬间（仅测试用） |

**注意**: AI 速度键保持不变（`fast`, `medium`, `slow`），不要混淆。
