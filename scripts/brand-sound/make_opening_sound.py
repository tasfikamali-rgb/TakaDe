#!/usr/bin/env python3
"""Builds TakaDe's opening sound, App/Resources/Sounds/opening.caf.

Original and synthesised here from sine waves and a little filtered noise, so there is
no third-party audio or licence to track. It follows the opening animation
(App/Sources/Root/LaunchSplash.swift): a soft paper "tick" as the taka sign splits, then
two quiet bell notes a fifth apart (E6, B6) as "akaDe" appears. About 0.6 s, peak around
-14 dBFS so it never startles.

    python3 scripts/brand-sound/make_opening_sound.py   # needs numpy and ffmpeg
"""
import pathlib
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44_100
LENGTH = 0.62
OUT = pathlib.Path(__file__).resolve().parents[2] / "App/Resources/Sounds/opening.caf"

t = np.arange(int(RATE * LENGTH)) / RATE
signal = np.zeros_like(t)


def bell(freq, start, gain, decay):
    """A soft bell: the fundamental plus a faint inharmonic partial, quick attack."""
    local = np.clip(t - start, 0, None)
    on = t >= start
    attack = np.clip(local / 0.004, 0, 1)
    env = attack * np.exp(-local / decay) * on
    tone = np.sin(2 * np.pi * freq * local) + 0.18 * np.sin(2 * np.pi * freq * 2.76 * local) * np.exp(-local / (decay * 0.35))
    return gain * env * tone


# The split: 12 ms of noise, smoothed so it sounds like a soft tap, not a click.
rng = np.random.default_rng(7)
noise = rng.standard_normal(len(t))
kernel = np.ones(9) / 9
noise = np.convolve(noise, kernel, mode="same")
tick_env = np.exp(-t / 0.006) * (t < 0.03)
signal += 0.55 * noise * tick_env
signal += bell(659.25, 0.0, 0.25, 0.03)  # a little body under the tap

# The word: E6 then B6.
signal += bell(1318.51, 0.13, 0.55, 0.16)
signal += bell(1975.53, 0.22, 0.42, 0.22)

# Fade the tail to silence and set the peak to about -14 dBFS.
fade = np.clip((LENGTH - t) / 0.08, 0, 1)
signal *= fade
signal *= 10 ** (-14 / 20) / np.max(np.abs(signal))

pcm = (signal * 32767).astype("<i2")
OUT.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    wav_path = pathlib.Path(tmp) / "opening.wav"
    with wave.open(str(wav_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())
    # Little-endian 16-bit PCM in a CAF, the format iOS plays with no decoding cost.
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "pcm_s16le", str(OUT)], check=True)
print(f"wrote {OUT}")
