# 联机座位音色包

当前已导入 19 套真实录音。韩立、乌沙奇已移除。

## 音色 ID

```text
luoxiaohei 罗小黑
wuyuanzhao 武元照
wenrounv   温柔女
jiejie     姐姐
gaoxiaonv  搞笑女
weilong    威龙
leishen    雷神
shuaige    帅哥
mingliangnv 明亮女
diantainan 电台男
huaqiang   华强
taiwannan  台湾男
wangye     王也
leijun     雷军
lubenwei   卢本伟
xiaohei    小黑
french     法国赌神
wenrou     温柔帅哥
nvyou      女友
```

默认座位音色：

```text
东 / 自己：罗小黑
南 / 下家：武元照
西 / 对家：温柔女
北 / 上家：姐姐
```

四个座位必须使用不同音色；已使用的音色在下拉框中会置灰。旧配置里的 default、韩立、乌沙奇会回退到罗小黑。

19 套音频均已切分为 32 句。旧的“语音下拉框/试听语音”已移除，试听改到每个座位的“试听”按钮；另有“测试全部语音”按钮。

## 音频目录

每套音色放入：

```text
res/audio/voice_packs/<pack_id>/
  wan1.wav ... wan9.wav
  tiao1.wav ... tiao9.wav
  tong1.wav ... tong9.wav
  pong.wav
  kong.wav
  ready.wav
  hu.wav
  zimo.wav
```

旧语音目录已移除；缺少文件时不会播放该条语音。

口头禅后续可以放在同目录的 `catchphrases/`，接入出牌事件时再扩展。

## UI 与联机规则

- 牌桌设置 → 座位音色。
- 每个座位独立选择，四个座位不能重复。
- 每个选择后面有独立“试听”按钮。
- “测试全部语音”按 11 套 × 32 句顺序播放，并显示进度。
- 非房主只能修改自己的座位。
- 房主可以独立修改任意座位，没有“全部一键设置”。
- 房主权威保存；客户端修改通过 `lobby_action("voice_pack")` 提交，重复音色会被拒绝。
- 房主修改后立即 `lobby_sync` 广播，客户端立即更新 `AudioManager`。
- 缺音频时仍能开局，只是该句不播放。

## 默认速度

```text
人机出牌：快
摸牌动画：快
出牌动画：快
结算：快速
AI 强度：中
开局发牌：快
```

座位音色弹窗加大，四个座位各带独立试听按钮；打开时读取当前 AudioManager/联机配置，选择后本地立即生效并保存，再同步给房主。

## 测试

```text
71/71 通过
Android 牌桌设置 UI 已实测：座位音色弹窗、四个座位、全部选项
```

## 后续音频

不能用网上抓取的真人/影视角色音频；需要：

- 有授权的录音；或
- 非模仿的 TTS 原创音色。

音频放入上述目录即可，不需要再改联机逻辑。
