# V2 牌桌动画流程

本文描述当前正式牌桌 `TableV2` 的实际动画路径。旧
`TableBoardView`、`PlayerTileAreas` 的遮罩动画仅保留兼容接口，正式画面不再使用。

## 1. 开局发牌

`RoundState` 按庄家、下家、对家、上家的顺序生成三个“每家四张”批次，再生成一个
“每家一张”批次。每次批次包含真实牌值以及这些牌在牌墙环上的下标。

```text
RoundState.deal_batch
  -> TableAnimationController 排队
  -> TableV2.animate_deal_group
  -> 从牌墙命中的两张下层、两张上层起飞
  -> 到达每家手牌右侧临时落点
  -> 第二批、第三批让已有手牌向中间展开
  -> 四家都显示13张后停止发牌
```

开局没有预先铺好整副手牌的遮罩。手牌节点只按
`TableAnimationController.dealt_count(seat)` 显示已经落桌的牌，所以不会出现
“最终手牌被盖住后又闪一下”的情况。

## 2. 理牌

三家13张都落地后，`TableV2._begin_hand_sort()` 保留当前牌节点，仅把节点移动到
`Tiles.sort_hand()` 给出的槽位。每张牌用两段位置插值形成拱形轨迹，并逐张错峰。
理牌完成前输入保持锁定，完成后才恢复庄家摸牌。

## 3. 摸牌

```text
RoundState 发出 draw
  -> 记录目标座位并暂时隐藏摸牌位
  -> TableV2 从真实 wall_index 对应的牌墙块创建飞行牌
  -> 飞到该玩家的摸牌位并放大到手牌尺寸
  -> 飞行结束才显示正式摸牌节点
  -> 解锁玩家操作
```

自己的牌显示正面，其他三家显示牌背。飞行期间权威摸牌节点和普通手牌中的同张牌
不会提前显示，因此不会重复、闪烁或提前出现在右侧。

## 4. 有摸牌时的出牌

玩家刚摸牌后选择打出旧牌，依次执行：

1. 被选中的旧牌从手牌飞到弃牌区；鸡牌进入红色区。
2. 原有手牌节点保留，按最终顺序平移，把空位移动到插入点。
3. 右侧摸牌节点移动到新牌的空槽，并由 `draw_box` 转入 `hand_box`。

动画期间不重建整手牌，动画完成后只做一次权威快照校正。位置使用 V2 设计坐标，
不会先跳到左上角再刷新。

如果玩家直接打出刚摸的牌，则摸牌节点直接飞向弃牌区，手牌保持13张。

## 5. 无摸牌时的出牌

碰牌后可以不打新摸牌而直接出牌。这个回合没有摸牌位节点，因此执行：

1. 选中的手牌飞到弃牌区。
2. 其余手牌节点平移补位。
3. 动画结束后刷新权威状态。

它不会伪造摸牌位，也不会关闭空位后整手重建。

## 6. 碰杠与鸡牌

普通碰杠由 `TableV2.animate_meld()` 接管。静态重建和动画落点共用
`_meld_positions()`，所以动画结束后不会改用另一套坐标。

幺鸡、八筒的单张、碰和杠进入红色区。红色区的尺寸、间距、换行和固定锚点由
`TableV2Geometry` 与 `red_layout()` 统一计算；旋转后的实际边界使用
`RedLayer` 本地坐标系计算，避免在 Android 非等比缩放下与手牌或牌墙混算坐标。

## 7. 对象池生命周期

频繁出现的牌统一由 `TileViewPool` 提供：

```text
acquire -> 重置牌面、尺寸、旋转、高亮和输入连接
        -> 加入目标图层
        -> 动画或快照重建结束
        -> release 回池
```

回收时必须同时恢复 `unit`、`custom_minimum_size` 和当前 `size`。否则从手牌或
摸牌位回收的大牌会在下一次作为红牌复用时保持错误尺寸，表现为冲锋鸡尺寸漂移。

`TableV2` 和旧 `TableAnimationLayer` 都在退出场景树时清空池内已经脱离节点的
TileView，防止连续切局积累 CanvasItem。

## 8. 测试入口

```text
tests/run_all.gd
tests/table_v2_hand_discard.gd
tests/table_v2_layout_guards.gd
tests/table_v2_static.gd
tests/accept_all_seats.gd
tests/accept_multi_turn.gd
tests/accept_tap_center.gd
tests/wall_deal_order.gd
tests/wall_draw_ten.gd
```
