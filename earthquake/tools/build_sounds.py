"""Earthquake sounds: rumble loop, two cracks, detonator click, distant boom."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def brown(d: float) -> np.ndarray:
    w = s.noise(d)
    b = np.cumsum(w)
    b -= np.convolve(b, np.ones(2000) / 2000, mode="same")
    return b / (np.max(np.abs(b)) + 1e-9)


def rumble() -> np.ndarray:
    d = 4.0
    n = int(d * s.SR)
    t = s.t_axis(d)
    base = s.lowpass_fast(brown(d + 0.6), 90, 2)
    base = s.looped(base, d, 0.6)
    sub = s.sine(28.0, d) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.75 * t))   # 112 and 3 cycles
    grit = s.bandpass_fast(s.noise(d + 0.6), 150, 600)
    grit = s.looped(grit, d, 0.6) * (0.25 + 0.25 * np.sin(2 * np.pi * 1.5 * t + 0.5)) * 0.5
    out = base * 1.0 + sub * 0.7 + grit
    return s.normalize(s.soft_clip(out, 1.3), 0.8)


def crack(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    d = 0.9
    n = int(d * s.SR)
    out = np.zeros(n)
    snap = s.highpass_fast(s.noise(0.03), 1200) * s.env_exp(int(0.03 * s.SR), 0.006, 0.0003)
    s.place(out, snap, 0.0, 1.0)
    thump = s.sine(np.linspace(110, 45, n), d) * s.env_exp(n, 0.09, 0.001)
    out += thump * 0.9
    body = s.bandpass_fast(s.noise(d), 200, 2500) * s.env_exp(n, 0.12, 0.001) * 0.7
    out += body
    # falling bits: tiny clicks over 0.6 s
    for k in range(40):
        at = 0.05 + rng.random() * 0.75
        c = s.bandpass_fast(s.noise(0.012), 1500, 6000) * s.env_exp(int(0.012 * s.SR), 0.003, 0.0002)
        s.place(out, c, at, 0.15 + 0.35 * rng.random() * (1 - at))
    return s.normalize(s.fade(out, 0.0005, 0.08), 0.82)


def click() -> np.ndarray:
    d = 0.22
    n = int(d * s.SR)
    out = np.zeros(n)
    k = s.highpass_fast(s.noise(0.01), 2000) * s.env_exp(int(0.01 * s.SR), 0.002, 0.0002)
    s.place(out, k, 0.0, 1.0)
    s.place(out, k * 0.7, 0.035, 1.0)
    beep = (s.sine(980, 0.12) + 0.3 * s.sine(1960, 0.12)) * s.env_adsr(int(0.12 * s.SR), 0.003, 0.02, 0.7, 0.04)
    s.place(out, beep, 0.07, 0.5)
    return s.normalize(out, 0.7)


def boom() -> np.ndarray:
    d = 3.0
    n = int(d * s.SR)
    t = s.t_axis(d)
    body = s.lowpass_fast(s.noise(d), 220, 2) * s.env_exp(n, 0.8, 0.03) * 2.0
    sub = s.sine(np.linspace(48, 26, n), d) * s.env_exp(n, 1.0, 0.05) * 1.4
    out = body + sub
    return s.normalize(s.soft_clip(s.fade(out, 0.02, 0.5), 1.5), 0.8)


SOUNDS = {
    "rumble.ogg": (rumble, 3.0, 5.0, True),
    "crack1.ogg": (lambda: crack(1), 0.5, 1.2, False),
    "crack2.ogg": (lambda: crack(2), 0.5, 1.2, False),
    "click.ogg": (click, 0.1, 0.4, False),
    "boom.ogg": (boom, 2.0, 4.0, False),
}

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
