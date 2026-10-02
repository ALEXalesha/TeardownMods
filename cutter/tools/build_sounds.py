"""Cutter sounds: spin-up, spin-down, idle whine loop, grinding loop, mark click."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def motor(f, d):
    x = s.saw(f, d) * 0.35 + s.sine(np.asarray(f) * 2, d) * 0.3 + s.sine(np.asarray(f) * 8.5, d) * 0.12
    return s.lowpass_fast(x, 6000)


def spinup():
    d = 0.8
    n = int(d * s.SR)
    f = 60 + 240 * (1 - np.exp(-np.arange(n) / s.SR / 0.25))
    x = motor(f, d) * np.linspace(0.3, 1, n)
    return s.normalize(s.fade(x, 0.01, 0.05), 0.7)


def spindown():
    d = 1.2
    n = int(d * s.SR)
    f = 300 * np.exp(-np.arange(n) / s.SR / 0.5) + 20
    x = motor(f, d) * np.exp(-np.arange(n) / s.SR / 0.5)
    return s.normalize(s.fade(x, 0.005, 0.1), 0.65)


def idle():
    d = 2.0
    t = s.t_axis(d)
    x = motor(300.0, d) * (0.9 + 0.1 * np.sin(2 * np.pi * 4 * t))   # 600 / 8 cycles
    air = s.looped(s.bandpass_fast(s.noise(d + 0.3), 2000, 7000), d, 0.3) * 0.1
    return s.normalize(x + air, 0.6)


def grind():
    d = 2.0
    t = s.t_axis(d)
    nz = s.looped(s.bandpass_fast(s.noise(d + 0.4), 1200, 9000), d, 0.4)
    am = 0.7 + 0.3 * np.sin(2 * np.pi * 23 * t)   # 46 cycles
    tone = s.sine(2400.0, d) * 0.25 + s.sine(3600.5, d) * 0.12
    low = motor(280.0, d) * 0.4
    crackle = s.looped(s.highpass_fast(s.noise(d + 0.4), 5000), d, 0.4) * (s.looped(s.noise(d + 0.4), d, 0.4) > 0.9)
    x = nz * am * 0.8 + tone + low + crackle * 0.4
    return s.normalize(s.soft_clip(x, 1.4), 0.75)


def click():
    d = 0.08
    n = int(d * s.SR)
    return s.normalize((s.sine(2000, d) + s.highpass_fast(s.noise(d), 3000) * 0.5) * s.env_exp(n, 0.012, 0.0005), 0.5)


SOUNDS = {
    "spinup.ogg": (spinup, 0.5, 1.0, False), "spindown.ogg": (spindown, 0.8, 1.5, False),
    "idle.ogg": (idle, 1.5, 2.5, True), "grind.ogg": (grind, 1.5, 2.5, True), "click.ogg": (click, 0.04, 0.2, False),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        print(f"{name:13s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} {'OK' if not probs else 'PROBLEM: ' + '; '.join(probs)}")
        bad += bool(probs)
    sys.exit(1 if bad else 0)
