"""Mover sounds: grab, release, hold hum loop, freeze, unfreeze, clone, tick, undo, error, scale."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def sweep_tone(f0, f1, d, tau=None, harm=0.3):
    n = int(d * s.SR)
    f = np.geomspace(f0, f1, n)
    x = s.sine(f, d) + harm * s.sine(f * 2, d) + 0.15 * s.saw(f * 0.5, d)
    e = s.env_adsr(n, 0.01, d * 0.4, 0.6, d * 0.4) if tau is None else s.env_exp(n, tau, 0.005)
    return x * e


def grab():
    d = 0.35
    x = sweep_tone(220, 880, d) + s.bandpass_fast(s.noise(d), 800, 4000) * s.env_exp(int(d * s.SR), 0.08) * 0.3
    return s.normalize(s.fade(x, 0.002, 0.05), 0.75)


def release():
    d = 0.3
    x = sweep_tone(700, 160, d)
    return s.normalize(s.fade(x, 0.002, 0.05), 0.7)


def hold_loop():
    d = 2.0
    t = s.t_axis(d)
    x = s.sine(110.0, d) * 0.5 + s.sine(220.0, d) * 0.25 + s.sine(330.5, d) * 0.12  # 220/440/661 cycles
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 3.0 * t)                                        # 6 cycles
    air = s.looped(s.bandpass_fast(s.noise(d + 0.4), 1500, 5000), d, 0.4) * 0.08
    return s.normalize(x + air, 0.6)


def freeze():
    d = 0.9
    n = int(d * s.SR)
    out = np.zeros(n)
    for f, a in ((2093, 1.0), (2637, 0.7), (3136, 0.6), (4186, 0.4)):
        out += s.sine(f, d) * s.env_exp(n, 0.25, 0.002) * a
    low = s.sine(np.linspace(300, 80, n), d) * s.env_exp(n, 0.15, 0.003) * 0.8
    crack = s.highpass_fast(s.noise(d), 3000) * s.env_exp(n, 0.03, 0.001) * 0.5
    return s.normalize(s.fade(out * 0.5 + low + crack, 0.001, 0.1), 0.75)


def unfreeze():
    d = 0.6
    n = int(d * s.SR)
    x = s.sine(np.linspace(150, 500, n), d) * s.env_exp(n, 0.2, 0.01) + s.bandpass_fast(s.noise(d), 500, 3000) * s.env_exp(n, 0.1) * 0.4
    return s.normalize(s.fade(x, 0.002, 0.1), 0.7)


def clone():
    d = 0.5
    n = int(d * s.SR)
    out = np.zeros(n)
    for k, at in enumerate((0.0, 0.16)):
        b = sweep_tone(300 + 200 * k, 1200 + 300 * k, 0.18, tau=0.06)
        s.place(out, b, at, 1.0)
    return s.normalize(s.fade(out, 0.001, 0.05), 0.75)


def tick():
    d = 0.06
    n = int(d * s.SR)
    x = s.sine(1800, d) * s.env_exp(n, 0.01, 0.0005) + s.highpass_fast(s.noise(d), 4000) * s.env_exp(n, 0.004) * 0.4
    return s.normalize(x, 0.5)


def undo():
    d = 0.45
    n = int(d * s.SR)
    x = sweep_tone(1200, 300, d) * 0.6 + s.bandpass_fast(s.noise(d), 600, 3000)[::-1] * np.linspace(0, 1, n) ** 2 * 0.5
    return s.normalize(s.fade(x, 0.002, 0.05), 0.7)


def error():
    d = 0.3
    n = int(d * s.SR)
    x = s.square(140, d, 0.5) * 0.5 + s.square(147, d, 0.5) * 0.5
    x = s.lowpass_fast(x, 1500) * s.env_adsr(n, 0.005, 0.05, 0.8, 0.08)
    return s.normalize(x, 0.6)


def scale():
    d = 1.2
    n = int(d * s.SR)
    t = s.t_axis(d)
    x = s.sine(400 + 300 * np.sin(2 * np.pi * 6 * t), d) * 0.4 + s.sine(np.geomspace(200, 1600, n), d) * 0.4
    x *= s.env_adsr(n, 0.05, 0.3, 0.7, 0.3)
    return s.normalize(x, 0.7)


SOUNDS = {
    "grab.ogg": (grab, 0.2, 0.6, False), "release.ogg": (release, 0.2, 0.5, False),
    "hold.ogg": (hold_loop, 1.5, 2.5, True), "freeze.ogg": (freeze, 0.5, 1.2, False),
    "unfreeze.ogg": (unfreeze, 0.3, 0.9, False), "clone.ogg": (clone, 0.3, 0.8, False),
    "tick.ogg": (tick, 0.03, 0.2, False), "undo.ogg": (undo, 0.3, 0.7, False),
    "error.ogg": (error, 0.2, 0.5, False), "scale.ogg": (scale, 0.8, 1.6, False),
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
