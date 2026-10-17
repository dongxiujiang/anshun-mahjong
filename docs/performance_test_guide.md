# 性能优化验证步骤

## 在 Godot 编辑器中测试

1. **打开项目**
   - 启动 Godot 编辑器
   - 打开 `C:\Users\xiu\Desktop\Mahjong-Godot\project.godot`

2. **运行游戏**
   - 点击编辑器右上角「运行」按钮（F5）
   - 或打开 `res://scenes/MainMenu.tscn` 并点击「运行当前场景」（F6）

3. **测试发牌动画**
   - 开始新局游戏
   - 观察投骰子后的发牌动画：
     - ✅ 每家每轮发 4 张，共 3 轮 + 最后每家 1 张
     - ✅ 牌从牌墙飞向手牌位置，无闪烁
     - ✅ 动画流畅，无卡顿

4. **测试摸牌动画**
   - 轮到自己时，自动从右侧牌墙摸牌
   - 观察：
     - ✅ 牌从对应牌墙方向飞到右侧摸牌位
     - ✅ 摸牌动画完成前，摸牌位不显示重复的牌
     - ✅ 动画完成后，可以点击操作

5. **测试打牌动画**
   - 点击任意手牌打出
   - 观察：
     - ✅ 第 1 段：旧牌飞向弃牌区（流畅）
     - ✅ 第 2 段：其他手牌平移填补空位（无从左上角刷新）
     - ✅ 第 3 段：刚摸的牌从右侧飞入排序位置（无卡顿）
     - ✅ 摸到的牌不会在移动过程中仍显示在摸牌位

6. **长时间测试**
   - 连续进行 5-10 局游戏
   - 使用编辑器的 **Profiler**（调试 → Profiler）观察：
     - ✅ GC 停顿次数显著减少
     - ✅ 帧率稳定在 58-60 FPS
     - ✅ 内存占用稳定，无持续增长

---

## 如果出现问题

### 卡顿仍然存在
- 检查对象池是否正确初始化：
  - 在 `scripts/ui/GameTable.gd` 的 `_ready()` 开头应有：
    ```gdscript
    var pool := preload("res://scripts/ui/TileViewPool.gd").new()
    ANIMATION_LAYER.tile_pool = pool
    ```
- 检查 `TableAnimationLayer.gd` 中所有 `TileView.new()` 是否替换为 `tile_pool.acquire()`

### 动画逻辑错误
- 如果发牌、摸牌、打牌顺序不对，检查：
  - `scripts/ui/table/TableAnimationController.gd` 没有被意外修改
  - `scripts/ui/TileView.gd` 的 `reset()` 方法是否正确重置所有状态

### 语法错误
- 如果启动时报错，检查：
  - `scripts/ui/TileViewPool.gd` 的 `_init()` 和 `acquire()` 方法语法
  - `scripts/ui/TileView.gd` 的 `reset()` 方法语法

---

## 性能指标参考

| 指标 | 优化前（预期） | 优化后（目标） |
|------|---------------|---------------|
| 发牌动画 GC 次数 | 每轮 4-6 次 | 0-1 次 |
| 摸牌/打牌 GC 停顿 | 5-15ms | < 1ms |
| 平均帧率 | 50-55 FPS | 58-60 FPS |

使用编辑器的 **Profiler** 和 **Visual Profiler** 可以查看实时数据。

---

**优化完成日期：** 2026-10-17  
**下一步：** 如测试通过，可提交代码；如需进一步优化，可考虑 Tween 复用或 AnimationPlayer。
