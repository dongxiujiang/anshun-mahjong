# 东秀麻将 · 安顺捉鸡（v2.4.1）

基于 **Godot 4.7.2** 打造的 **新中式 2.5D 安顺捉鸡麻将**，包含跨平台客户端（Android / Windows）、协议 4 权威无头联机服务端（Python 目录接口 + Godot 无头牌桌进程），以及内置官方门户网站前后端。

---

## 核心特性

- **原汁原味安顺捉鸡规则**：完整保留捉鸡、冲锋鸡/冲锋金鸡、翻鸡、干扣/大干扣、报听与杀报、杠开/抢杠胡/热炮、海底捞月以及真实的碰杠/冲锋鸡牌桌物理摆放区域。
- **沉浸式 2.5D 牌桌与人性化交互**：
  - **2.06× 大号手牌与防误触**：手牌倾角 `68°`、选牌抬高 `0.56`，配合优化后的点击/长按容差与水平加权拾取，顺滑防误点；开局骰子 `2.25×` 放大配红白高对比大点数，点位清晰易辨。
  - **100 个麻将专属昵称库**：玩家建档与资料页支持「挑昵称」5 列滚动选单与随机换名；人机座位从 100 昵称库中不重复抽取，彻底告别牌名昵称。
  - **常驻听牌提示 & 抬牌计数**：`听牌中 / 报听中` 常驻在底左玩家名片正上方，摸牌/出牌不消失、换听实时更新；抬起手牌仅在牌顶轻提示场上已出张数并高亮同牌；名片旁清晰展示 `[庄]`、`[听]` 印章。
  - **翻鸡时刻前置 & 牌型明细结算**：胡牌后先在无遮挡亮牌牌桌上展示「翻鸡时刻」（高亮牌墙翻出牌、3 张关联鸡牌与 `金鸡×2` 提示，停留 2.6 秒或随时点「查看结算」）；结算页直接展示具体番型与分值（如 `大对子+14`、`清一色+24`、`小七对+24`、`龙七对+44`），冲锋鸡横置金边摆放。
  - **双路语音对讲与实时遥测**：Android 联机房优先使用腾讯 GME 实时语音（线上服务内置签权）并支持 ENet PCM 自动回退，名片明确区分 `开启中 / 麦开 / 麦关` 与 `发言中 / 收听中 / 已静音`；右上角实时展示 `FPS` 与局域网/服务器毫秒延迟。
- **全链路端到端优化**：15 位角色立绘重采样至视网膜级 `384×512`（体积与显存降低 87.1%），APK 体积 **85.86 MB**，Android 冷启动实测 **1.88 秒**；大厅自动停用后台 3D 视口、按需懒提取牌面 UV 与预导入音频。
- **官方门户网站 + 后端接口**：访问 `https://mj.dongxiu.fun/` 即可浏览实时在线房间、网页一键创建联机房、下载带 SHA-256 校验与计数统计的最新 APK，并可在页面内联调后端 REST 接口。

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
│   │   │   ├── domain/        # 麻将牌墙、回合状态机、座位、100 昵称库与协议定义
│   │   │   ├── ai/            # 智能出牌 AI 与教打参谋
│   │   │   ├── app/           # 新中式 UI、听牌辅助、翻鸡时刻、遥测条、结算与生涯战绩
│   │   │   ├── audio/         # 音效舞台与局域网/在线双路语音控制器
│   │   │   ├── network/       # ENet 客户端、局域网自动发现与无头房间服务
│   │   │   └── presentation/  # 2.5D 牌桌渲染、高清骰子着色器、手牌排序、镜头与动画
│   │   └── tests/             # 66 套自动化规则/UI/网络/性能验证脚本
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

### 1. 运行客户端全量自动化测试（66 套）

```powershell
# 单项示例（Godot 4.7.2）
Godot_v4.7.2-stable_win64.exe --headless --path remake/game -s res://tests/test_round.gd
Godot_v4.7.2-stable_win64.exe --headless --path remake/game -s res://tests/test_v241_polish.gd
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
- [客户端架构与 UI](docs/客户端架构与UI.md)：v2.4.1 界面设计、翻鸡时刻、语音与延迟遥测、全链路性能优化
- [服务端与官网前后端](docs/服务端与官网前后端.md)：协议 4 接口规范、门户 REST API 与部署架构
- [发布与测试记录](docs/发布与测试记录.md)：v2.4.1 实机测试数据、APK 校验信息与上线记录
