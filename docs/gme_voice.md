# 联机语音（腾讯云 GME）接入手册

## 1. 当前状态

- LiveKit 已从客户端代码、服务器编排和更新清单中移除。
- Android 在线房间使用 GME Android SDK 2.9.17（arm64）；局域网房间使用现有 PCM 语音采集和房主转发，不请求在线房间鉴权。
- Windows 客户端已移除；仅保留 Android GME。
- 小米 15 的 1.3.0 启动崩溃不再使用 LiveKit 原生库。

## 2. 必需配置

```dotenv
GME_APP_ID=1400802279
GME_APP_KEY=<腾讯云 GME 控制台的鉴权密钥>
```

`GME_APP_KEY` 只能放在服务器 `.env` 或本地测试环境，**不能提交到仓库，也不能打进客户端**。

服务器需要提供：

```http
GET /gme-auth?room=123456&openid=1234561
X-Room-Token: <该座位当前 resume_token>
```

`openid` 必须是 `房间号+座位号`；`X-Room-Token` 必须是该座位当前房间成员凭证，否则返回 403。成功返回短时 AuthBuffer：

```json
{"app_id":"1400802279","room":"123456","openid":"1234561","auth":"base64..."}
```

## 3. Android SDK 文件

提供的 SDK：

```text
GME_android_audio_sdk_2.9.17.9e947c95.zip
- gmesdk.jar
- libs/arm64-v8a/libgmesdk.so
- libs/arm64-v8a/libgmefaad2.so
- libs/arm64-v8a/libgmefdkaac.so
- libs/arm64-v8a/libgmelamemp3.so
- libs/arm64-v8a/libgmeogg.so
- libs/arm64-v8a/libgmesoundtouch.so
```

仓库使用 `addons/gme/gmesdk.aar` 封装 JAR + arm64 原生库。Gradle 导出会自动带上该 AAR。

Android 客户端通过 Godot 4.7 的 `JavaClassWrapper` 直接调用：

```text
com.gme.TMG.ITMGContext
com.gme.TMG.ITMGAudioCtrl
```

使用 `VoiceDelegate.java` 提供 GME 所需的具体回调类；必须使用 Gradle 导出模板，并保留 `RECORD_AUDIO` 权限。新增或修改此 Java 类需要发布完整 APK，不能仅靠 PCK 更新。

## 4. Windows SDK 文件

```text
GME_Windows_audio_sdk_2.9.17.9e947c95.zip
- include/tmg_sdk.h
- include/auth_buffer.h
- libs/win/x64/release/gmesdk.dll
- libs/win/x64/release/gmesdk.lib
- 其他 GME 运行 DLL
```

Windows 客户端已移除，不再提供 PCM 回退或 Windows GME 桥接。

## 5. GME 进房流程

```text
客户端进入牌桌
→ 请求服务器 /gme-auth
→ 服务器用 AppID/AppKey 生成 AuthBuffer
→ GME Init(AppID, openId)
→ Poll()
→ EnterRoom(roomNumber, ROOM_TYPE_FLUENCY, authBuffer)
→ 确认 IsRoomEntered，应用本机静音和音量，再开启接收
→ 玩家点击自己的姓名后才 EnableMic(true)，默认关闭
→ 每个真人座位通过 OpenID 控制本机收听
```

座位映射：

```text
房间 123456：
seat0 → openid=1234560
seat1 → openid=1234561
seat2 → openid=1234562
seat3 → openid=1234563
```

## 6. 音量与静音

- 自己麦克风：`SetMicVolume(0..200)`
- 全局播放音量保持 `SetSpeakerVolume(100)`，通过各座位 `SetSpeakerVolumeByOpenID(openid, 0..200)` 应用本机他人音量。
- 单个座位静音：`AddAudioBlackList(openid)`。
- 恢复单个座位：`RemoveAudioBlackList(openid)`，再应用本机音量。
- 连接前选择的静音在进房时生效；SDK 重新进房后重新应用，不能只改变名字颜色。

现有设置面板的“麦克风音量/他人语音音量”继续复用。牌桌点击玩家名字和分数区域控制语音，不显示喇叭图标：自己的麦克风开启时名字为黄色；其他玩家只有麦克风开启且未被本地静音时名字为黄色，关闭时为白色。轮到出牌仅显示名字旁的黄色圆点，不改变名字颜色。

等待权限或连接时可再次点击自己的姓名取消开麦。Android 后台通知暂停采集和播放；回到前台且牌局同步完成后恢复原选择。SDK 断线时立即上报麦克风关闭，恢复后重新应用开关；系统停止录音时允许玩家重新开启，不能每帧重复调用失败的采集操作。换座先退出旧 OpenID，再鉴权加入新座位。

鉴权请求超时为 8 秒，进房或 SDK 恢复等待上限为 10 秒。失败后按 1、3、8 秒间隔最多自动重试三次；牌局状态帧不会触发反复鉴权。旧请求的返回不能覆盖新座位，手动重试不必等待其他玩家出牌。

局域网采用 24 kHz、20 ms PCM 帧。转发允许短时成批到达，持续限制每个玩家每秒 50 帧；不能按相邻包必须间隔 10 ms 限流，否则低帧率会丢正常语音。接收缺包最多等待 80 ms，不因后续包持续到达而无限等待；接收队列过长时保留近期声音，静音和后台时清空，停止说话后释放播放流。

## 7. 服务器 AuthBuffer

`server/gme_auth.py` 实现 GME 的 TEA/CBC AuthBuffer，接口由 `server/room_directory.py` 提供。

测试：

```bash
python tests/test_gme_auth.py
```

不要把 AppKey 发给客户端；客户端只拿 `auth` 的 base64。

## 8. 构建

Android：

```bash
godot --headless --path . --install-android-build-template
mkdir -p android/build/libs android/build/src/main/java/com/anshun/mahjong
cp addons/gme/gmesdk.aar android/build/libs/gmesdk.aar
cp addons/gme/VoiceDelegate.java android/build/src/main/java/com/anshun/mahjong/VoiceDelegate.java
# 在 android/build/build.gradle 中加入：
# dependencies { implementation files("libs/gmesdk.aar") }
godot --headless --path . --export-release "Android" build/android/anshun-mahjong.apk
```

`export_presets.cfg` 必须：

```text
gradle_build/use_gradle_build=true
architectures/armeabi-v7a=false
architectures/arm64-v8a=true
permissions/record_audio=true
```

## 9. 验证顺序

1. 服务器 `/gme-auth` 返回 200；
2. 小米 15 安装 APK 后能进入主菜单和牌桌；
3. 点麦克风，GME 返回进房成功；
4. 第二台设备用同一房间号进入；
5. 验证双方语音、单座位静音、音量设置；
6. 再验证弱网、切后台、重新进房。

自动回归：`tests/voice_chat.gd`、`tests/gme_voice_chat.gd` 覆盖缓存、静音、权限取消、原生状态恢复和鉴权重试；`tests/run_network.py` 中的 `voice_network.gd` 使用真实双进程 ENet，在 15 FPS 下双向发送各 100 个测试音频帧。原生 SDK 的回归替身与测试音频不能代替两台 Android 设备上的真人通话、回声和蓝牙耳机验收。

## 10. 常见问题

- **/gme-auth 503**：`.env` 没有配置 `GME_APP_KEY`。
- **进入房间失败**：AppID/AppKey 不匹配、GME 应用未开通、AuthBuffer 过期。
- **Android 没有声音**：检查录音权限、GME AAR 是否被打进 APK、`libgmesdk.so` 是否在 `lib/arm64-v8a/`。
- **Windows 版本**：已移除，不再提供安装包。

