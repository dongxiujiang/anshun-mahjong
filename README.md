# 东秀麻将 · 安顺捉鸡（v2.4.0）

基于 **Godot 4.7.2** 打造的 **新中式 2.5D 安顺捉鸡麻将**，包含跨平台客户端（Android / Windows）、协议 4 权威无头联机服务端（Python 目录接口 + Godot 无头牌桌进程），以及内置官方门户网站前后端。

---

## 核心特性

- **原汁原味安顺捉鸡规则**：完整保留捉鸡、冲锋鸡/冲锋金鸡、翻鸡、干扣/大干扣、报听与杀报、杠开/抢杠胡/热炮、海底捞月以及真实的碰杠/冲锋鸡牌桌物理摆放区域。
- **沉浸式 2.5D 牌桌与人性化交互**：
  - 1.82× 放大手牌与顺滑上滑/双击出牌，移除多余出牌按钮与牌桌 3D 庄听摆件，名片旁清晰展示 `[庄]`、`[听]` 印章。
  - **常驻听牌提示 & 抬牌计数**：`听牌中 / 报听中` 常驻在底左玩家名片正上方，摸牌/出牌不消失、换听实时更新；抬起手牌仅在牌顶轻提示场上已出张数并高亮同牌。
  - **结算一致化**：结算页中的冲锋鸡/冲锋金鸡横置金边摆放，鸟头朝向与 3D 牌桌实体冲锋鸡完全一致。
  - **语音与性能遥测**：联机房真人明确区分 `麦开 / 麦关`、`发言中 / 收听中 / 已静音`；对局与房间右上角实时显示 `FPS` 与局域网/在线服务器 ENet 毫秒延迟。
- **全链路端到端优化**：15 位角色立绘重采样至视网膜级 `384×512`（体积与显存降低 87.1%），APK 瘦身至 **85.84 MB**，Android 冷启动实测 **1.96 秒**；大厅自动停用后台 3D 视口、按需懒提取牌面 UV 与预导入音频。
- **官方门户网站 + 后端接口**：访问在线服务端根路径即可浏览实时在线房间、网页一键创建联机房、下载带 SHA-256 校验与计数统计的最新 APK，并可在页面内联调后端 REST 接口。

---

## 目录结构

```text
Mahjong-Godot/
├── remake/
│   ├── game/                  # Godot 4.7.2 游戏客户端与权威无头牌桌工程
│   │   ├── assets/            # 牌面纹理、15套角色立绘/语音包、音频与牌桌布局配置
│   │   ├── scenes/            # 主场景 Main.tscn
│   │   ├── src/
│   │   │   ├── anshun/        # 权威安顺捉鸡规则与计分引擎（严禁偏离规则）
│   │   │   ├── domain/        # 麻将牌墙、回合状态机、座位与协议定义
│   │   │   ├── ai/            # 智能出牌 AI 与教打参谋
│   │   │   ├── app/           # 新中式 UI、听牌辅助、遥测条、结算与生涯战绩
│   │   │   ├── audio/         # 音效舞台与局域网/在线语音控制器
│   │   │   ├── network/       # ENet 客户端、局域网自动发现与无头房间服务
│   │   │   └── presentation/  # 2.5D 牌桌渲染、手牌排序、镜头与动画
│   │   └── tests/             # 65 套自动化规则/UI/网络/性能验证脚本
│   ├── server/                # Python 3 目录、牌谱校验与官网门户后端
│   │   ├── room_directory.py  # HTTP 主服务（协议 4 房间目录 + 门户接口 + 静态前端）
│   │   ├── portal_api.py      # 版本清单、APK 下载计数与静态资源安全分发
│   │   ├── round_records.py   # SQLite 权威牌谱归档与无头规则重演校验
│   │   └── gme_auth.py        # 在线语音鉴权签名
│   ├── web/                   # 新中式官方门户前端（零外部 CDN 依赖）
│   └── tools/
│       └── build_android_apk.ps1  # Windows 一键导出并校验 Android APK 脚本
├── docker/                    # 容器启动脚本与 Caddy 反向代理配置
├── docs/                      # 精简核心技术与发布文档
├── Dockerfile                 # 一体化在线服务镜像（Python + Godot Headless + Web）
├── compose.yaml               # 本地源码构建编排
├── compose.prod.yaml          # 生产预构建镜像编排
└── deploy.sh                  # 一键部署脚本
```

---

## 快速上手

### 1. 运行客户端全量自动化测试（65 套）

```powershell
# 单项示例（Godot 4.7.2）
Godot_v4.7.2-stable_win64.exe --headless --path remake/game -s res://tests/test_round.gd
Godot_v4.7.2-stable_win64.exe --headless --path remake/game -s res://tests/test_telemetry_bar.gd
```

### 2. 导出 Android APK

```powershell
powershell -ExecutionPolicy Bypass -File "remake\tools\build_android_apk.ps1"
```

产物输出至 `build/dongxiu-remake-25d.apk`，自动完成 `apksigner` 验签与资源完整性核验。

### 3. 运行服务端 + 官方门户（本地或 Docker）

```bash
# 本地启动（同时提供协议 4 联机目录、牌谱校验与官网前端）
python3 remake/server/room_directory.py \
  --godot /path/to/godot \
  --project remake/game \
  --runtime build/room-server \
  --web-dir remake/web \
  --downloads-dir build/downloads \
  --public-host 127.0.0.1 \
  --bind 127.0.0.1 \
  --port 8080

# 服务端测试（门户接口 + 在线房间目录 + 权威牌谱重演）
python3 remake/server/test_portal_api.py --godot /path/to/godot
python3 remake/server/test_room_directory.py --godot /path/to/godot
python3 remake/server/test_record_store.py --godot /path/to/godot

# Docker 一键部署
sh deploy.sh mj.dongxiu.fun
```

---

## 文档导航

- [规则玩法与计分](docs/规则玩法与计分.md)：安顺捉鸡、冲锋鸡、报听、番型与碰杠摆放权威说明
- [客户端架构与 UI](docs/客户端架构与UI.md)：2.4.0 界面设计、语音与延迟遥测、全链路性能优化
- [服务端与官网前后端](docs/服务端与官网前后端.md)：协议 4 接口规范、门户 REST API 与部署架构
- [发布与测试记录](docs/发布与测试记录.md)：v2.4.0 实机测试数据、APK 校验信息与上线记录
