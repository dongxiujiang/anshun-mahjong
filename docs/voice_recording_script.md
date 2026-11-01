# 出牌语音录制文本

每套音色 32 句，按顺序录制；每句之间停顿 0.5 秒。

```text
[pause 0.5s]
```

如果 TTS 不支持这个标记，就用实际 0.5 秒静音代替，不要读出方括号内容。

## 每套口头禅

| 音色槽 | 口头禅 |
|---|---|
| 乌沙奇 | 冲呀！ |
| 五五开 | 稳住，能赢！ |
| 星爷 | 有意思！ |
| 发哥 | 慢慢来，稳赢。 |
| 华哥 | 好运继续！ |
| 法国赌神 | 这把梭哈！ |

把下面每句后面的 `{口头禅}` 替换成对应音色的口头禅即可。

## 32 句基础文本

```text
[wan1] 一万，{口头禅} [pause 0.5s]
[wan2] 二万，{口头禅} [pause 0.5s]
[wan3] 三万，{口头禅} [pause 0.5s]
[wan4] 四万，{口头禅} [pause 0.5s]
[wan5] 五万，{口头禅} [pause 0.5s]
[wan6] 六万，{口头禅} [pause 0.5s]
[wan7] 七万，{口头禅} [pause 0.5s]
[wan8] 八万，{口头禅} [pause 0.5s]
[wan9] 九万，{口头禅} [pause 0.5s]
[tiao1] 一条，{口头禅} [pause 0.5s]
[tiao2] 二条，{口头禅} [pause 0.5s]
[tiao3] 三条，{口头禅} [pause 0.5s]
[tiao4] 四条，{口头禅} [pause 0.5s]
[tiao5] 五条，{口头禅} [pause 0.5s]
[tiao6] 六条，{口头禅} [pause 0.5s]
[tiao7] 七条，{口头禅} [pause 0.5s]
[tiao8] 八条，{口头禅} [pause 0.5s]
[tiao9] 九条，{口头禅} [pause 0.5s]
[tong1] 一筒，{口头禅} [pause 0.5s]
[tong2] 二筒，{口头禅} [pause 0.5s]
[tong3] 三筒，{口头禅} [pause 0.5s]
[tong4] 四筒，{口头禅} [pause 0.5s]
[tong5] 五筒，{口头禅} [pause 0.5s]
[tong6] 六筒，{口头禅} [pause 0.5s]
[tong7] 七筒，{口头禅} [pause 0.5s]
[tong8] 八筒，{口头禅} [pause 0.5s]
[tong9] 九筒，{口头禅} [pause 0.5s]
[pong] 碰，{口头禅} [pause 0.5s]
[kong] 杠，{口头禅} [pause 0.5s]
[ready] 报听，{口头禅} [pause 0.5s]
[hu] 胡，{口头禅} [pause 0.5s]
[zimo] 自摸，{口头禅}
```

## 乌沙奇完整示例

```text
一万，冲呀！ [pause 0.5s]
二万，冲呀！ [pause 0.5s]
三万，冲呀！ [pause 0.5s]
四万，冲呀！ [pause 0.5s]
五万，冲呀！ [pause 0.5s]
六万，冲呀！ [pause 0.5s]
七万，冲呀！ [pause 0.5s]
八万，冲呀！ [pause 0.5s]
九万，冲呀！ [pause 0.5s]
一条，冲呀！ [pause 0.5s]
二条，冲呀！ [pause 0.5s]
三条，冲呀！ [pause 0.5s]
四条，冲呀！ [pause 0.5s]
五条，冲呀！ [pause 0.5s]
六条，冲呀！ [pause 0.5s]
七条，冲呀！ [pause 0.5s]
八条，冲呀！ [pause 0.5s]
九条，冲呀！ [pause 0.5s]
一筒，冲呀！ [pause 0.5s]
二筒，冲呀！ [pause 0.5s]
三筒，冲呀！ [pause 0.5s]
四筒，冲呀！ [pause 0.5s]
五筒，冲呀！ [pause 0.5s]
六筒，冲呀！ [pause 0.5s]
七筒，冲呀！ [pause 0.5s]
八筒，冲呀！ [pause 0.5s]
九筒，冲呀！ [pause 0.5s]
碰，冲呀！ [pause 0.5s]
杠，冲呀！ [pause 0.5s]
报听，冲呀！ [pause 0.5s]
胡，冲呀！ [pause 0.5s]
自摸，冲呀！
```

## 录制后文件命名

按顺序切分并命名：

```text
wan1.wav ... wan9.wav
tiao1.wav ... tiao9.wav
tong1.wav ... tong9.wav
pong.wav
kong.wav
ready.wav
hu.wav
zimo.wav
```

## 说明

以上口头禅是原创短句，不包含影视台词或真人标志性台词。不要用未授权的真人声音克隆；TTS 或录音请使用自己拥有权利的声音。
