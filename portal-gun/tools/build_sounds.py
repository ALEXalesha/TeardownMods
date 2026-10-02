"""Portal gun sounds: two fire shots, portal open, close, pass-through, fizzle, portal hum loop."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def fire(base):
    d = 0.45
    n = int(d * s.SR)
    f = base * np.geomspace(2.2, 0.6, n)
    x = s.sine(f, d) * 0.6 + s.saw(f * 0.5, d) * 0.2
    x += s.bandpass_fast(s.noise(d), 1500, 6000) * s.env_exp(n, 0.05) * 0.4
    x *= s.env_exp(n, 0.15, 0.002)
    return s.normalize(s.fade(x, 0.001, 0.05), 0.75)


def open_():
    d = 0.8
    n = int(d * s.SR)
    t = s.t_axis(d)
    whoosh = s.bandpass_fast(s.noise(d), 400, 3000) * np.sin(np.pi * t / d) ** 2
    ring = (s.sine(523, d) + 0.5 * s.sine(784, d) + 0.3 * s.sine(1046, d)) * s.env_exp(n, 0.35, 0.05) * 0.4
    return s.normalize(whoosh * 0.6 + ring, 0.75)


def close():
    d = 0.6
    n = int(d * s.SR)
    x = s.sine(np.geomspace(900, 80, n), d) * s.env_exp(n, 0.2) + s.bandpass_fast(s.noise(d), 300, 2000) * np.linspace(1, 0, n) * 0.4
    return s.normalize(s.fade(x, 0.002, 0.05), 0.7)


def pass_():
    d = 0.7
    n = int(d * s.SR)
    t = s.t_axis(d)
    f = 200 + 1200 * np.sin(np.pi * t / d)
    x = s.sine(f, d) * 0.4 + s.bandpass_fast(s.noise(d), 600, 5000) * 0.5
    x *= np.sin(np.pi * t / d) ** 1.5
    return s.normalize(x, 0.75)


def fail():
    d = 0.4
    n = int(d * s.SR)
    x = s.bandpass_fast(s.noise(d), 2000, 8000) * s.env_exp(n, 0.08) + s.square(np.linspace(300, 120, n), d, 0.3) * s.env_exp(n, 0.1) * 0.3
    return s.normalize(s.lowpass_fast(x, 7000), 0.6)


def hum():
    d = 2.0
    t = s.t_axis(d)
    x = s.sine(110.0, d) * 0.4 + s.sine(220.5, d) * 0.2 + s.sine(330.0, d) * 0.15
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 2.0 * t)
    x += s.looped(s.bandpass_fast(s.noise(d + 0.3), 2000, 6000), d, 0.3) * 0.1
    return s.normalize(x, 0.6)


SOUNDS = {"fire_blue.ogg": (lambda: fire(700), 0.3, 0.6, False), "fire_orange.ogg": (lambda: fire(520), 0.3, 0.6, False),
          "open.ogg": (open_, 0.5, 1.0, False), "close.ogg": (close, 0.4, 0.8, False), "pass.ogg": (pass_, 0.5, 1.0, False),
          "fail.ogg": (fail, 0.2, 0.6, False), "hum.ogg": (hum, 1.5, 2.5, True)}

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
