"""Original, deterministic settlement chimes; no downloads or runtime synthesis.

Run this file to rebuild only the six settlement WAVs. Other audio is untouched.
Soft attacks/edge fades avoid clicks; a short metallic cascade accompanies the
digit particles reaching the total. All samples are mono, 16-bit PCM at 44.1kHz.
"""
from array import array
from pathlib import Path
import math
import random
import sys
import wave

RATE = 44100
OUTPUT = Path(__file__).resolve().parents[2] / "res/audio/effects"
# (length, [(start, frequency, gain)], metallic). Sparse pentatonic notes keep
# the cues compatible with the table music and distinct from spoken tile names.
CUES = {
    "flip": (0.30, [(0, 880, 0.7), (0.08, 1320, 0.5)], True),
    "chicken": (0.28, [(0, 660, 0.7), (0.075, 880, 0.5)], False),
    "kong": (0.25, [(0, 330, 0.8), (0.045, 495, 0.5)], False),
    "win": (0.38, [(0, 660, 0.6), (0.075, 880, 0.6), (0.15, 1100, 0.5)], True),
    "other": (0.22, [(0, 550, 0.7), (0.055, 660, 0.4)], False),
    "coins": (0.44, [(0, 1046.5, 0.6), (0.06, 1318.5, 0.7),
                     (0.13, 1568, 0.6), (0.21, 2093, 0.35), (0.21, 1046.5, 0.4)], True),
}


def generate():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for index, (cue, (duration, notes, metallic)) in enumerate(CUES.items()):
        rng = random.Random(20261018 + index)
        samples = []
        for frame in range(round(duration * RATE)):
            time = frame / RATE
            value = 0.0
            for start, frequency, gain in notes:
                elapsed = time - start
                if elapsed < 0:
                    continue
                attack = 1 - math.exp(-elapsed / 0.0025)
                decay = math.exp(-elapsed / (0.075 if metallic else 0.05))
                tone = math.sin(math.tau * frequency * elapsed)
                tone += 0.22 * math.sin(math.tau * frequency * (2.73 if metallic else 2) * elapsed) * math.exp(-elapsed / 0.04)
                tone += 0.055 * rng.uniform(-1, 1) * math.exp(-elapsed / 0.008)
                value += gain * attack * decay * tone
            edge = min(1.0, max(0.0, (duration - time) / 0.035))
            samples.append(value * edge)
        gain = 0.42 / max(abs(value) for value in samples)
        pcm = array("h", (round(value * gain * 32767) for value in samples))
        if sys.byteorder != "little":
            pcm.byteswap()
        path = OUTPUT / f"settlement_{cue}.wav"
        with wave.open(str(path), "wb") as target:
            target.setnchannels(1)
            target.setsampwidth(2)
            target.setframerate(RATE)
            target.writeframes(pcm.tobytes())
        print(f"{path.name}: {duration:.2f}s")


if __name__ == "__main__":
    generate()
