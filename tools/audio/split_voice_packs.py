"""把每套长录音切分为 32 句游戏语音。

录音顺序：
  wan1..9, tiao1..9, tong1..9, pong, kong, ready, hu, zimo

用法：
  python tools/audio/split_voice_packs.py --source wav --out res/audio/voice_packs

要求每套能切出且只能切出 32 段；否则不落盘并返回非零。
输出统一为 22050 Hz、单声道、16-bit PCM。
"""
from __future__ import annotations

import argparse
import shutil
import wave
from pathlib import Path

import numpy as np

KEYS = ([f"wan{i}" for i in range(1, 10)]
        + [f"tiao{i}" for i in range(1, 10)]
        + [f"tong{i}" for i in range(1, 10)]
        + ["pong", "kong", "ready", "hu", "zimo"])

PACKS = {
    "罗小黑": "luoxiaohei",
    "武元照": "wuyuanzhao",
    "温柔女": "wenrounv",
    "搞笑女": "gaoxiaonv",
    "威龙": "weilong",
    "雷神": "leishen",
    "帅哥": "shuaige",
    "女友": "nvyou",
    "电台男": "diantainan",
    "华强": "huaqiang",
    "台湾男": "taiwannan",
    "王也": "wangye",
    "雷军": "leijun",
}

TARGET_RATE = 22050


def read_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise ValueError(f"{path.name}: 需要单声道 16-bit WAV")
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768.0
    return data, rate


def split_speech(data: np.ndarray, rate: int) -> list[tuple[int, int]]:
    win = int(0.02 * rate)
    frames = len(data) // win
    rms = np.sqrt((data[: frames * win].reshape(frames, win) ** 2).mean(axis=1))
    threshold = max(0.008, float(np.percentile(rms, 20)) * 2.0)
    active = rms > threshold
    merge_gap = int(0.25 / 0.02)
    runs: list[tuple[int, int]] = []
    start = None
    for index, is_active in enumerate(active):
        if is_active and start is None:
            start = index
        elif not is_active and start is not None:
            if index - start >= 2:
                runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, frames))
    merged: list[tuple[int, int]] = []
    for begin, end in runs:
        if merged and begin - merged[-1][1] < merge_gap:
            merged[-1] = (merged[-1][0], end)
        else:
            merged.append((begin, end))
    # 0.18 秒以下的碎片视为噪声，不保留。
    return [(begin, end) for begin, end in merged if end - begin >= 9]


def trim_and_resample(data: np.ndarray, rate: int, begin: int, end: int) -> np.ndarray:
    start = max(0, begin * int(0.02 * rate) - int(0.03 * rate))
    stop = min(len(data), end * int(0.02 * rate) + int(0.03 * rate))
    clip = data[start:stop].copy()
    if rate != TARGET_RATE:
        out_len = int(round(len(clip) * TARGET_RATE / rate))
        old_pos = np.arange(len(clip), dtype=np.float64)
        new_pos = np.linspace(0, len(clip) - 1, out_len, dtype=np.float64)
        clip = np.interp(new_pos, old_pos, clip).astype(np.float32)
    peak = float(np.max(np.abs(clip))) if len(clip) else 0.0
    if peak > 0.98:
        clip = clip * (0.98 / peak)
    return clip


def write_wav(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TARGET_RATE)
        w.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="wav")
    parser.add_argument("--out", default="res/audio/voice_packs")
    args = parser.parse_args()
    source = Path(args.source)
    out = Path(args.out)
    failures = []
    for display, pack_id in PACKS.items():
        path = source / f"{display}.wav"
        if not path.exists():
            failures.append(f"缺少 {display}.wav")
            continue
        data, rate = read_wav(path)
        segments = split_speech(data, rate)
        if len(segments) != 32:
            failures.append(f"{display}: 切出 {len(segments)} 段，应为 32")
            continue
        target = out / pack_id
        if target.exists():
            shutil.rmtree(target)
        for key, (begin, end) in zip(KEYS, segments):
            write_wav(target / f"{key}.wav", trim_and_resample(data, rate, begin, end))
        print(f"{display:8s} -> {pack_id:12s} 32 clips")
    if failures:
        print("FAILED:")
        for failure in failures:
            print(" -", failure)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
