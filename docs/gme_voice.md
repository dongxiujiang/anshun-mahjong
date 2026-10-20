# 联机语音（腾讯云 GME）接入手册

## 1. 当前状态

- LiveKit 已从客户端代码、服务器编排和更新清单中移除。
- Android 使用 GME Android SDK 2.9.17（arm64）。
- Windows 先保留原有 PCM 语音，GME Windows GDExtension 随后接入。
- 小米 15 的 1.3.0 启动崩溃不再使用 LiveKit 原生库。

## 2. 必需配置

```dotenv
GME_APP_ID=1400802279
GME_APP_KEY=<腾讯云 GME 控制台的鉴权密钥>
```

`GME_APP_KEY` 只能放在服务器 `.env` 或本地测试环境，**不能提交到仓库，也不能打进客户端**。

服务器需要提供：

```http
GET /gme-auth?room=123456&openid=seat1
```

成功返回短时 AuthBuffer：

```json
{"app_id":"1400802279","room":"123456","openid":"seat1","auth":"base64..."}
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

不需要另写 Java 插件类；但必须使用 Gradle 导出模板，并保留 `RECORD_AUDIO` 权限。

## 4. Windows SDK 文件

```text
GME_Windows_audio_sdk_2.9.17.9e947c95.zip
- include/tmg_sdk.h
- include/auth_buffer.h
- libs/win/x64/release/gmesdk.dll
- libs/win/x64/release/gmesdk.lib
- 其他 GME 运行 DLL
```

Windows 端需要 GDExtension 包装，不能直接由 GDScript 调 DLL。当前版本先用 PCM 回退，完成 GDExtension 后再切到 GME。

## 5. GME 进房流程

```text
客户端进入牌桌
→ 请求服务器 /gme-auth
→ 服务器用 AppID/AppKey 生成 AuthBuffer
→ GME Init(AppID, openId)
→ Poll()
→ EnterRoom(roomNumber, ROOM_TYPE_FLUENCY, authBuffer)
→ EnableMic(true)
→ 每个真人座位通过 OpenID 控制喇叭静音
```

座位映射：

```text
seat0 → openid=seat0
seat1 → openid=seat1
seat2 → openid=seat2
seat3 → openid=seat3
```

## 6. 音量与静音

- 自己麦克风：`SetMicVolume(0..200)`
- 全部他人音量：`SetSpeakerVolume(0..200)`
- 单个座位静音：`AddAudioBlackList("seatN")`
- 恢复单个座位：`RemoveAudioBlackList("seatN")`

现有设置面板的“麦克风音量/他人语音音量”和牌桌喇叭按钮继续复用。

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

## 10. 常见问题

- **/gme-auth 503**：`.env` 没有配置 `GME_APP_KEY`。
- **进入房间失败**：AppID/AppKey 不匹配、GME 应用未开通、AuthBuffer 过期。
- **Android 没有声音**：检查录音权限、GME AAR 是否被打进 APK、`libgmesdk.so` 是否在 `lib/arm64-v8a/`。
- **Windows 没声音**：当前 Windows 还是 PCM 回退；GME Windows GDExtension 尚未发布。
