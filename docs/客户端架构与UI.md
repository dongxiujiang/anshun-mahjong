# 客户端架构与 UI 说明（v2.4.1）

客户端基于 **Godot 4.7.2（GL Compatibility 渲染后端）** 构建，面向 Android 横屏手机/平板与 Windows 桌面，工程位于 `remake/game/`。

---

## 一、界面流程与新中式视觉设计

全局统一采用**深黛墨玉底色 + 古铜描金边框 + 宣纸象牙牌面**的新中式茶馆风格（`AppTheme.gd`、`AppBackdrop.gd`、`TableTheme.gd`）：

1. **首次入局资料页（`ProfileSetup.gd`、`MahjongNames.gd`）**：15 位原创立绘人物两行横向滑动选择；内置 **100 个纯麻将/安顺捉鸡主题昵称库**（无牌名、无重复），支持「挑昵称」5 列滚动面板直选、随机换名与自定义输入；支持手机端返回键失焦与防误退二次确认。
2. **茶馆主大厅（`Main.gd`、`RoomBrowser.gd`）**：双栏布局——左侧聚合单机开局、局域网约局与在线开桌 2×2 工具箱；右侧展示实时 3D 房间台面，顶部提供战绩、资料、设置入口。
3. **等待房间（`Main.gd`）**：东西南北四向罗盘选座，展示玩家头像、准备状态与局域网连接地址，人齐准备后无需多余倒计时直接开局。
4. **2.5D 实感牌桌（`TableView.gd`、`DiceFaces.gdshader`）**：
   - `camera_pitch = 45.4°`，本家手牌放大 `2.06×`（`self_hand_pitch = 68°`，前移 `OWN_HAND_FORWARD_SHIFT = 3.65`，选牌抬高 `0.56`），配合增强防误触容差与水平加权拾取，支持双击/上滑出牌、拖拽理牌与一键智能排序/恢复排序。
   - 开局 3D 骰子视觉放大 `2.25×`（不改物理碰撞边长与协议 4 兼容），配高对比朱砂红/象牙白点数与 1/4 点正红凹点，落定点数一目了然。
   - 仅在轮到本家操作时显示固定位置的圆形倒计时钟（`TurnClockView.gd`），移除牌桌 3D 庄/听立牌摆件。
5. **翻鸡时刻前置与居中结算页（`FlipChickenReveal.gd`、`SettlementView.gd`、`SettlementNames.gd`）**：
   - 胡牌且牌墙翻出鸡牌时，先在无遮挡 3D 亮牌桌面上停留展示「翻鸡时刻」（2.6 秒或随时点「查看结算」跳过），高亮牌墙翻出牌、按序展示 3 张关联鸡牌与 `金鸡×2` 提示，同时 3D 金光标亮翻出牌及各家计分鸡牌。
   - 结算面板首帧精确居中于牌墙内安全区，底部提供 `[离开]`、`[查看牌面]`、`[下一局]` 操作栏；胡牌番型直接在胡牌张旁展示具体牌型与分值（如 `大对子+14`、`清一色+24`、`小七对+24`、`龙七对+44`），冲锋鸡/冲锋金鸡横置金边对齐牌桌朝向，四家名片同步显示 `[庄]`/`[听]` 印章。

---

## 二、局内辅助、双路语音与遥测功能

| 模块 | 源码 | 核心行为 |
| --- | --- | --- |
| **常驻叫牌与抬牌计数** | `src/app/TingAssistantOverlay.gd` | `听牌中 / 报听中` 固定显示在底左本家名片正上方，摸牌/出牌持续不消失、换听实时更新；抬起手牌仅在牌顶显示 `X · 已出 Y 张`（仅计场上弃牌与可见碰杠）并高亮同牌。 |
| **100 昵称库与人机去重** | `src/domain/MahjongNames.gd`、`src/session/RoomSession.gd` | 100 个纯麻将主题汉字昵称，人机建房不重复抽取，人类加入或离开时自动去重防撞名。 |
| **双路语音与名片印章** | `src/audio/VoiceController.gd`、`src/network/GameClient.gd`、`src/app/PlayerBadge.gd` | Android 在线房优先使用腾讯 GME 实时语音（自动读取 `_online_url()` 鉴权），GME 不可用或局域网环境自动无缝回退至 ENet PCM 语音中继；名片旁显示红金 `[庄]`、翠玉 `[听]`，真人分数旁固定展示 `开启中 / 麦开 / 麦关` 与 `发言中 / 收听中 / 已静音`。 |
| **实时 FPS 与网络延迟** | `src/app/StatusTelemetryBar.gd`、`src/network/GameClient.gd` | 常驻安全区右上角空白区（宽屏单行、窄屏双行，零遮挡），2 Hz 平滑刷新 FPS；局域网/在线服务器基于 ENet 传输层 `PEER_LAST_ROUND_TRIP_TIME` 实时显示连接状态点与毫秒延迟（<60ms 绿 / 60–149ms 金 / ≥150ms 红，以及连接中/重连中/已断开）。 |
| **战绩与图鉴** | `src/app/CareerPanel.gd`、`PlayerProgress.gd` | 本地统计胜率、连胜、段位与冲锋鸡/大牌图鉴解锁。 |

---

## 三、全链路性能优化

1. **显存专项优化（-84% ~ -88% GPU VRAM）**：移除 GL Compatibility 下单节点永久占用 257 MB 显存的 `ReflectionProbe`（精致档保留零显存开销的 `REFLECTION_SOURCE_BG` 柔光反射），使单机精致档显存由 `310.48 MB` 降至 **`49.37 MB`**、流畅档降至 **`35.31 MB`**（纹理显存仅 `28.81 MB`）。
2. **阴影与着色器分档**：方向光阴影范围收紧至 `42.0`、移动端阴影图 `1024`，平躺的牌墙与弃牌关闭投射阴影；流畅档切换至零法线采样的 `TileResinSmooth.gdshader`；`mahJong.png` 开启 mipmap、`mahJong_NORM.png` 开启 VRAM 压缩与 mipmap；新增移动端低帧自动降档与「省电帧率 (30 FPS)」开关。
3. **角色立绘显存与体积优化**：15 张立绘由 `1086×1448`（23.69 MB，~94 MB 显存）经 Lanczos 重采样至视网膜级 `384×512`（3.05 MB，~11 MB 显存），QA 安装包 85.86 MB，Android 冷启动实测 **1.88 秒**；另新增纯 `arm64-v8a` 的 `Android Release` 导出预设用于正式包瘦身。
4. **冷启动按需加载与模块解耦**：`TileArt.gd` 按需懒提取单张牌面 UV 并缓存横置牌面；`SoundStage.gd` 优先加载预导入二进制音频并在静默期关闭 `_process`；虚拟键盘轮询改为输入框聚焦触发；`Main.gd` 拆出 `MainLobbyBuilder.gd` 与 `LeaveConfirmOverlay.gd`（瘦身 748 行）。
5. **零无效 3D 渲染与池化**：菜单/大厅关闭牌桌 3D `SubViewport`（`UPDATE_DISABLED`）；`RoomBrowser` 空房停用视口、有房 `UPDATE_ONCE`；复用落牌涟漪、缓存手牌锚点、预缓存 `StyleBoxFlat` 与骰子网格。
