"""Gravity sounds: shift down (lighter), shift up (heavier), zero-G hum loop, click."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def shift(up: bool):
    d = 1.4
    n = int(d * s.SR)
    t = s.t_axis(d)
    f = np.geomspace(60, 240, n) if up else np.geomspace(240, 50, n)
    x = s.sine(f, d) * 0.6 + s.saw(f * 0.5, d) * 0.15 + s.sine(f * 1.5, d) * 0.2
    x = s.lowpass_fast(x, 2000)
    shimmer = s.sine(np.geomspace(1800, 600, n) if not up else np.geomspace(600, 1800, n), d) * 0.12
    env = np.sin(np.pi * t / d) ** 0.8
    return s.normalize((x + shimmer) * env, 0.75)


def zerog():
    d = 3.0
    t = s.t_axis(d)
    x = (s.sine(110.0, d) + 0.7 * s.sine(165.0, d) + 0.5 * s.sine(220.0, d) + 0.3 * s.sine(330.0, d))
    x *= 0.7 + 0.3 * np.sin(2 * np.pi * (1 / 3) * t)
    air = s.looped(s.bandpass_fast(s.noise(d + 0.5), 2000, 7000), d, 0.5) * 0.08
    return s.normalize(s.reverb(x, 0.8, 0.4, 0.0)[: int(d * s.SR)] + air, 0.55)


def click():
    d = 0.1
    n = int(d * s.SR)
    return s.normalize((s.sine(1300, d) + 0.4 * s.sine(2600, d)) * s.env_exp(n, 0.02, 0.001), 0.5)


SOUNDS = {"lighter.ogg": (lambda: shift(False), 1.0, 2.0, False), "heavier.ogg": (lambda: shift(True), 1.0, 2.0, False),
          "zerog.ogg": (zerog, 2.5, 3.5, True), "click.ogg": (click, 0.05, 0.2, False)}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        print(f"{name:12s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} {'OK' if not probs else 'PROBLEM: ' + '; '.join(probs)}")
        bad += bool(probs)
    sys.exit(1 if bad else 0)
