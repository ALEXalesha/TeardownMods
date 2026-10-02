"""Tornado sounds: roar loop, spawn (thunder + rising wind), dissipate, radio click."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def roar():
    d = 4.0
    t = s.t_axis(d)
    low = s.looped(s.lowpass_fast(s.noise(d + 0.6), 160, 2), d, 0.6) * 1.6
    mid = s.looped(s.bandpass_fast(s.noise(d + 0.6), 250, 1200), d, 0.6)
    howl = s.looped(s.bandpass_fast(s.noise(d + 0.6), 500, 900), d, 0.6)
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t) * np.sin(2 * np.pi * 1.25 * t + 1)   # 2 and 5 cycles
    x = low + mid * (0.5 + 0.5 * gust) + howl * 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.75 * t))
    return s.normalize(s.soft_clip(x, 1.3), 0.8)


def spawn():
    d = 3.0
    n = int(d * s.SR)
    out = np.zeros(n)
    crack = s.highpass_fast(s.noise(0.08), 800) * s.env_exp(int(0.08 * s.SR), 0.02, 0.001)
    rumble = s.lowpass_fast(s.noise(2.5), 200, 2) * s.env_exp(int(2.5 * s.SR), 0.8, 0.02) * 2
    s.place(out, crack, 0.0, 1.0)
    s.place(out, rumble, 0.03, 1.0)
    wind = s.bandpass_fast(s.noise(d), 200, 1500) * np.linspace(0, 1, n) ** 2
    out += wind * 0.6
    return s.normalize(s.soft_clip(s.fade(out, 0.002, 0.3), 1.4), 0.76)


def dissipate():
    d = 2.5
    n = int(d * s.SR)
    x = s.bandpass_fast(s.noise(d), 200, 1500) * np.linspace(1, 0, n) ** 1.5
    x += s.lowpass_fast(s.noise(d), 150) * np.linspace(1, 0, n) ** 2
    return s.normalize(s.fade(x, 0.02, 0.2), 0.75)


def click():
    d = 0.2
    n = int(d * s.SR)
    x = s.highpass_fast(s.noise(d), 1500) * s.env_exp(n, 0.05) * 0.4 + s.sine(1200, d) * s.env_adsr(n, 0.005, 0.05, 0.5, 0.08) * 0.5
    return s.normalize(x, 0.55)


SOUNDS = {"roar.ogg": (roar, 3.0, 5.0, True), "spawn.ogg": (spawn, 2.0, 4.0, False),
          "dissipate.ogg": (dissipate, 1.5, 3.5, False), "click.ogg": (click, 0.1, 0.4, False)}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        print(f"{name:14s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} {'OK' if not probs else 'PROBLEM: ' + '; '.join(probs)}")
        bad += bool(probs)
    sys.exit(1 if bad else 0)
