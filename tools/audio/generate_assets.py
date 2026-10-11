"""生成慢速古琴音色/落桌音效，柔化语音；运行时不依赖 Python。"""
from pathlib import Path
import argparse
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / 'res' / 'audio'
RATE = 22050
MUSIC_BPM = 54
MUSIC_BEATS = 64


def write_pcm(path, samples, rate=RATE):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(samples, -1, 1) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(pcm.tobytes())


def trim_voice(path):
    with wave.open(str(path), 'rb') as source:
        assert source.getsampwidth() == 2 and source.getnchannels() == 1
        rate = source.getframerate()
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(float) / 32768
    peak = np.max(np.abs(samples))
    audible = np.flatnonzero(np.abs(samples) > max(.002, peak * .008))
    assert audible.size, f'空语音：{path.name}'
    first = max(0, audible[0] - int(rate * .035))
    last = min(samples.size, audible[-1] + int(rate * .075))
    samples = samples[first:last]
    # 温和收掉尖锐高频，不改变音高，也不通过加速牺牲自然停顿。
    frequencies = np.fft.rfftfreq(samples.size, 1 / rate)
    spectrum = np.fft.rfft(samples)
    warmth = .62 + .38 / np.sqrt(1 + (frequencies / 3400) ** 4)
    samples = np.fft.irfft(spectrum * warmth, n=samples.size)
    samples *= .65 / max(1e-9, np.max(np.abs(samples)))
    fade = min(round(rate * .008), len(samples) // 2)
    samples[:fade] *= np.linspace(0, 1, fade)
    samples[-fade:] *= np.linspace(1, 0, fade)
    write_pcm(path, samples, rate)
    return len(samples) / rate


def music():
    # 原创 D 调五声音阶，54 BPM / 16 小节。疏朗的古琴拨弦、泛音和滑音。
    beat = 60 / MUSIC_BPM
    count = round(MUSIC_BEATS * beat * RATE)
    output = np.zeros(count)
    phrases = [
        [(0, 62), (2, 66), (4, 69), (6, 66), (7.5, 64)],
        [(0, 62), (3, 59), (5, 57)],
        [(0, 64), (2, 66), (4.5, 71), (6.5, 69)],
        [(0, 66), (3, 64), (5.5, 62)],
        [(0, 69), (2.5, 74), (4.5, 71), (6.5, 69)],
        [(0, 66), (2.5, 64), (5, 62)],
        [(0, 64), (2, 66), (4, 69), (6, 66)],
        [(0, 64), (3, 59), (5, 62)],
    ]

    def place(note, start, length, amplitude, slide=False, harmonic=False):
        time = np.arange(round(length * RATE)) / RATE
        frequency = 440 * 2 ** ((note - 69) / 12)
        # 按音轻微滑音和很浅的吟猱，让余韵有自然起伏。
        cents = -16 * np.exp(-time / .2) if slide else np.zeros_like(time)
        cents += (3 if slide else .7) * np.sin(2 * np.pi * 4.1 * time) * (1 - np.exp(-time / .7))
        phase = 2 * np.pi * np.cumsum(frequency * 2 ** (cents / 1200)) / RATE
        tone = np.zeros_like(time)
        for partial in range(1, 11):
            pluck = abs(np.sin(np.pi * partial * .21)) / partial ** 1.35
            if harmonic and partial % 2:
                pluck *= .17
            decay = np.exp(-time / (2.1 / partial ** .58))
            tone += pluck * np.sin(phase * partial * (1 + .000012 * partial ** 2)) * decay
        tone += .045 * np.sin(2 * np.pi * 142 * time) * np.exp(-time / .13)
        envelope = (1 - np.exp(-time / .009)) * np.minimum(1, (length - time) / .3)
        signal = tone * envelope * amplitude
        indexes = (round(start * RATE) + np.arange(len(signal))) % count
        np.add.at(output, indexes, signal)

    for phrase_index, phrase in enumerate(phrases):
        start = phrase_index * 8 * beat
        place([50, 45, 47, 50][phrase_index % 4], start, 7, .11)
        for index, (position, note) in enumerate(phrase):
            place(note, start + position * beat, 6, .25 if index == 0 else .19,
                  slide=index in (1, 3), harmonic=phrase_index == 4 and index == 1)
    # 环形早期反射，跨接缝保留尾韵；没有鼓点或刺耳的高音铺底。
    dry = output.copy()
    for delay, gain in [(.083, .09), (.137, .08), (.223, .06), (.347, .045), (.521, .03)]:
        output += np.roll(dry, round(delay * RATE)) * gain
    output *= .42 / max(1e-9, np.max(np.abs(output)))
    assert abs(output[0] - output[-1]) < .025, '循环接缝不能出现明显点击'
    write_pcm(AUDIO / 'music' / 'table.wav', output)


def discard_effect():
    rng = np.random.default_rng(44)
    time = np.arange(round(.24 * RATE)) / RATE
    output = np.zeros_like(time)
    for start, gain in [(0, 1), (.035, .5)]:
        local = np.maximum(0, time - start)
        active = time >= start
        click = (rng.normal(0, .34, time.size) + .45 * np.sin(2 * np.pi * 1250 * local))
        click *= np.exp(-local / .012) * (1 - np.exp(-local / .0008)) * active
        body = .28 * np.sin(2 * np.pi * 260 * local) * np.exp(-local / .03) * active
        output += gain * (click + body)
    output *= .7 / np.max(np.abs(output))
    write_pcm(AUDIO / 'effects' / 'discard.wav', output)


def build_assets(voice_source, voices_processed=False, speakers=None):
    if voices_processed:
        durations = {}
        for path in sorted((AUDIO / 'voice').rglob('*.wav')):
            with wave.open(str(path), 'rb') as source:
                durations[path.relative_to(AUDIO / 'voice').with_suffix('').as_posix()] = round(source.getnframes() / source.getframerate(), 3)
    else:
        durations = {path.relative_to(AUDIO / 'voice').with_suffix('').as_posix(): round(trim_voice(path), 3) for path in sorted((AUDIO / 'voice').rglob('*.wav'))}
    assert len(durations) in (32, 128), '每位玩家需要27个牌名及5个动作语音'
    assert max(durations.values()) < 1.0, '语音不能超过快档出牌间隔'
    # 音频生成只更新语音与音效，保留已经选择的背景音乐。
    if not (AUDIO / 'music' / 'table.wav').exists():
        music()
    discard_effect()
    manifest_path = AUDIO / 'manifest.json'
    previous = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    with wave.open(str(AUDIO / 'music' / 'table.wav'), 'rb') as source:
        music_seconds = source.getnframes() / source.getframerate()
    (AUDIO / 'manifest.json').write_text(json.dumps({'voice_seconds': durations, 'music_seconds': music_seconds, 'speakers': speakers or previous.get('speakers', []),
                                                   'voice_source': voice_source,
                                                   'voice_processing': 'gentle treble shelf, 8ms edge fades, peak 0.65',
                                                   'music_source': previous.get('music_source', 'Original slow pentatonic composition, modal guqin timbre, 54 BPM'),
                                                   'music_license': previous.get('music_license', ''),
                                                   'music_url': previous.get('music_url', ''),
                                                   'music_processing': previous.get('music_processing', ''),
                                                   'effect_source': 'Original procedural tile impact'}, indent=2), encoding='utf-8')
    print(f'Voice: {len(durations)} clips; longest: {max(durations.values()):.3f}s; music: {music_seconds:.2f}s')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--voice-source', default='Windows Microsoft Huihui; offline speech synthesis, slower rate')
    args = parser.parse_args()
    build_assets(args.voice_source)
