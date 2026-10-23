# UI 风格与新增界面规范

目标是让所有新界面自动继承游戏现有视觉语言，而不是每次临时拼一套控件。

## 基准组件

新增界面必须优先复用：

```text
scripts/ui/UiStyle.gd       panel / button / field / 颜色
scripts/ui/UiMotion.gd      appear / slide_in / 按钮按压
scripts/ui/TileView.gd      _font() 统一字体
```

参考实现：

```text
scripts/ui/ResumeRoomDialog.gd   确认类弹窗
scripts/ui/ConnectionOverlay.gd  连接/重连类弹窗
scripts/ui/SoundSettings.gd      设置类面板
```

## 弹窗尺寸

标准确认/连接弹窗：

```text
面板：760 × 360
外边距：38
标题：32 号，金色 GOLD，左上角 (38, 28)
正文：22 号，MUTED，区域 (38, 88) 到 684 × 96，自动换行
操作区：y=246，两个 330 × 76 按钮
```

需要更多内容时优先增加正文高度，不要把按钮堆到屏幕边缘。

## 颜色与字体

```text
标题/重点     UiStyle.GOLD
正文          UiStyle.MUTED
输入框文字    UiStyle.INK
面板背景      UiStyle.panel()
主按钮        UiStyle.button(button, true)
次按钮        UiStyle.button(button, false)
```

不要直接使用 Godot 默认 `AcceptDialog`、`ConfirmationDialog` 的系统主题作为最终界面；它们只适合临时调试。

## 动效

统一使用：

```gdscript
MOTION.appear(self)
MOTION.slide_in(panel)
STYLE.button(button, primary)
```

重复调用状态更新时先判断 `visible`，避免每次重连计数都重新播放整段动画。

## 安全区与缩放

所有全屏弹窗用 `STYLE.usable_rect(self)` 计算可用区域，再按比例缩放并居中。不要直接用 `get_viewport_rect()` 定位到刘海/手势区。

## 文案与操作

- 错误弹窗必须有一个明确主操作：`重试`、`返回大厅` 或 `保存`；
- 连接类弹窗必须说明当前状态和是否保留原座位；
- 不要只显示一个裸错误字符串；
- 主动离开与自动断线必须区分：自动断线保留 token，主动离开才清除。

## 新增界面检查清单

```text
[ ] 使用 UiStyle.panel()
[ ] 使用 TileView._font()
[ ] 标题 32 / 正文 22 / 按钮 28
[ ] 使用 STYLE.button() 的主次按钮
[ ] 使用 STYLE.usable_rect() 居中
[ ] 使用 MOTION.appear/slide_in
[ ] 有明确主操作和取消操作
[ ] 在 ui_regression.gd 增加最小布局断言
```
