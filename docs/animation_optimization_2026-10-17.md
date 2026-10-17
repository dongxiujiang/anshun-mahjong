# 麻将动画优化总结 - 2026-10-17

## 优化目标

使游戏动画更贴近真实麻将场景，解决以下问题：
1. 摸牌位的牌在动画期间提前显示，造成闪烁
2. 出牌后手牌从错误位置刷新
3. 摸牌插入动画时源节点未隐藏，造成重复显示
4. 手牌移动使用全局坐标，父节点旋转导致路径偏移

## 核心优化

### 1. 手牌出牌三段动画序列

真实麻将场景：
- 拿起手牌扔到河牌区
- 其他手牌水平推开，填补空位
- 将摸到的牌插入到手牌中

优化后的实现：
```
第 1 段（0-0.28s）：被打出的牌飞向弃牌区
第 2 段（0.28-0.56s）：其他手牌水平移动，填补空位
第 3 段（0.56-0.84s）：摸牌从摸牌位插入到排序位置
```

### 2. 局部坐标系动画

**问题：** 原代码使用 `global_position` 插值，当父节点有旋转（侧座玩家）时，插值路径会偏移

**解决：** 全部改用局部坐标 `position` 插值
```gdscript
# 优化前
tile.global_position = from_global.lerp(to_global, eased)

# 优化后
tile.position = move_from.lerp(move_to, eased)
```

### 3. 摸牌位源节点隐藏时机

**问题：** 插入动画期间，摸牌位的源节点和临时节点同时显示

**解决：** 在第三段动画开始前立即隐藏源节点
```gdscript
# TableAnimationLayer._hand_motion()
if not event.get("hand_insert", {}).is_empty():
    var source_node = data.get("source_node")
    if is_instance_valid(source_node) and source_node is TileView:
        source_node.visible = false  # 立即隐藏
    # ... 创建临时插入节点
```

### 4. 精准遮罩控制

**问题：** 原代码遮罩了所有手牌，玩家看不到手牌的移动过程

**解决：** 只遮罩被打出的牌
```gdscript
# TableAnimationController.refresh_masks()
if from_hand:
    # 只隐藏被打出的牌节点本身
    _mask(source_node)
    # 其他手牌保持可见，玩家可以看到水平移动
elif discard_from_draw:
    # 从摸牌位打出时，隐藏摸牌位的牌
    for draw_tile in _tiles_in(table.draw_box[seat]):
        _mask(draw_tile)
```

### 5. 摸牌动画可见性管理

**问题：** 摸牌动画未完成时，持久节点提前显示

**解决：** 通过 `_held_draw_seats` 保持隐藏，动画完成后才释放
```gdscript
# TableAnimationController._on_visual_animation_finished()
if finished_type == "draw":
    if remaining_draw_holds <= 0:
        _held_draw_seats.erase(draw_seat)
        # 摸牌动画完成后，立即显示摸牌位的牌
        for draw_tile in _tiles_in(table.draw_box[draw_seat]):
            draw_tile.visible = true
            draw_tile.modulate.a = 1.0
```

## 真实场景对应关系

| 动作 | 真实麻将 | 优化后的实现 |
| --- | --- | --- |
| 摸牌 | 从牌墙抽出，放到手牌右侧单独位置 | 从对应牌墙位置飞到摸牌位，带抛物线和落桌回弹，落地后才显示持久节点 |
| 出牌 | 拿起手牌，扔到河牌区 | 从被点击的手牌位置飞到河牌，带轻微抬升，只隐藏被打出的牌 |
| 手牌整理 | 把牌推开留缝，补回摸牌 | 三段动画：出牌 → 水平移动填补空位 → 摸牌淡入插入目标槽位 |
| 侧座手牌 | 手牌仍沿手牌方向移动 | 使用局部坐标，避免父节点旋转导致的路径偏移 |

## 修改的文件

```
scripts/ui/TableAnimationLayer.gd
  - _hand_motion(): 局部坐标插值 + 源节点提前隐藏

scripts/ui/table/TableAnimationController.gd
  - refresh_masks(): 精准遮罩控制
  - _on_visual_animation_finished(): 摸牌可见性管理

docs/animation_review.md
  - 新增 2026-10-17 优化记录章节
```

## 测试验证

启动游戏，观察以下场景：
1. **摸牌动画**：从牌墙飞到摸牌位，落地瞬间无闪烁
2. **出牌动画**：点击手牌中间一张，观察其他手牌是否水平滑动填补空位
3. **摸牌插入**：打出手牌后，观察摸牌是否从右侧淡入插入到排序位置
4. **侧座手牌**：观察左右玩家的手牌移动是否沿手牌方向（竖直），无偏移
5. **操作锁定**：动画期间不能点击手牌或响应按钮

## 后续优化方向

1. **抛物线参数调优**：调整 `UI.DISCARD_ARC_HEIGHT`、`TILE_SETTLE_LIFT` 等参数，使动画更自然
2. **音效同步**：在出牌、落桌、碰杠时刻播放音效
3. **3D 化**：迁移到 2.5D/3D 场景，增加真实阴影和材质反射
4. **摄像机运动**：在胡牌、杠牌等关键时刻加入摄像机推拉和聚焦

---

优化日期：2026-10-17  
优化工程师：Codex AI
