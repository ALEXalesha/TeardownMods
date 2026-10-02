"""Trampoline sounds: boing (two sizes), place, remove, mode toggle."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def boing(f0):
    d = 0.9
    n = int(d * s.SR)
    t = s.t_axis(d)
    f = f0 * (1 + 0.6 * np.exp(-t / 0.08)) * (1 + 0.08 * np.sin(2 * np.pi * 11 * t) * np.exp(-t / 0.3))
    x = s.sine(f, d) * 0.7 + s.sine(f * 2.02, d) * 0.2
    x *= s.env_exp(n, 0.28, 0.002)
    thump = s.sine(np.geomspace(120, 50, n), d) * s.env_exp(n, 0.06, 0.001) * 0.8
    twang = s.saw(f * 0.5, d) * s.env_exp(n, 0.05) * 0.15
    return s.normalize(s.fade(x + thump + twang, 0.001, 0.1), 0.8)


def place():
    d = 0.5
    n = int(d * s.SR)
    clunk = s.lowpass_fast(s.noise(d), 600) * s.env_exp(n, 0.05, 0.001) * 1.5
    ring = s.sine(330, d) * s.env_exp(n, 0.15) * 0.3
    return s.normalize(clunk + ring, 0.75)


def remove():
    d = 0.4
    n = int(d * s.SR)
    x = s.sine(np.geomspace(600, 150, n), d) * s.env_exp(n, 0.12) + s.bandpass_fast(s.noise(d), 500, 3000) * s.env_exp(n, 0.06) * 0.4
    return s.normalize(x, 0.7)


def toggle():
    d = 0.25
    out = np.zeros(int(d * s.SR))
    for k, f in enumerate((660, 990)):
        b = s.sine(f, 0.08) * s.env_adsr(int(0.08 * s.SR), 0.003, 0.02, 0.6, 0.03)
        s.place(out, b, k * 0.1, 1.0)
    return s.normalize(out, 0.55)


SOUNDS = {"boing.ogg": (lambda: boing(180), 0.6, 1.2, False), "boing_small.ogg": (lambda: boing(320), 0.6, 1.2, False),
          "place.ogg": (place, 0.3, 0.7, False), "remove.ogg": (remove, 0.2, 0.6, False), "toggle.ogg": (toggle, 0.15, 0.4, False)}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        print(f"{name:16s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} {'OK' if not probs else 'PROBLEM: ' + '; '.join(probs)}")
        bad += bool(probs)
    sys.exit(1 if bad else 0)
