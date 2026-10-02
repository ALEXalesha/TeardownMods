"""Telekinesis sounds: grab, hold hum loop, throw, drop, empty."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def grab():
    d = 0.7
    n = int(d * s.SR)
    t = s.t_axis(d)
    whoosh = s.bandpass_fast(s.noise(d), 300, 2500) * np.sin(np.pi * t / d) ** 2
    tone = (s.sine(np.geomspace(150, 600, n), d) + 0.5 * s.sine(np.geomspace(225, 900, n), d)) * s.env_adsr(n, 0.05, 0.3, 0.6, 0.25)
    return s.normalize(whoosh * 0.5 + tone * 0.5, 0.75)


def hold():
    d = 2.0
    t = s.t_axis(d)
    x = s.sine(130.0, d) * 0.5 + s.sine(195.0, d) * 0.3 + s.sine(261.5, d) * 0.15
    x *= 0.75 + 0.25 * np.sin(2 * np.pi * 3.0 * t)
    x += s.looped(s.bandpass_fast(s.noise(d + 0.3), 1500, 5000), d, 0.3) * 0.08
    return s.normalize(x, 0.6)


def throw():
    d = 0.8
    n = int(d * s.SR)
    burst = s.bandpass_fast(s.noise(d), 200, 4000) * s.env_exp(n, 0.2, 0.003)
    thump = s.sine(np.geomspace(200, 50, n), d) * s.env_exp(n, 0.12, 0.002)
    zap = s.sine(np.geomspace(1500, 300, n), d) * s.env_exp(n, 0.15) * 0.4
    return s.normalize(burst + thump + zap, 0.8)


def drop():
    d = 0.5
    n = int(d * s.SR)
    x = s.sine(np.geomspace(500, 120, n), d) * s.env_exp(n, 0.2) + s.bandpass_fast(s.noise(d), 300, 1500) * np.linspace(1, 0, n) * 0.3
    return s.normalize(s.fade(x, 0.003, 0.05), 0.7)


def empty():
    d = 0.4
    n = int(d * s.SR)
    x = s.square(np.linspace(240, 120, n), d, 0.4) * s.env_adsr(n, 0.005, 0.1, 0.6, 0.12)
    return s.normalize(s.lowpass_fast(x, 1800), 0.6)


SOUNDS = {"grab.ogg": (grab, 0.5, 1.0, False), "hold.ogg": (hold, 1.5, 2.5, True), "throw.ogg": (throw, 0.5, 1.0, False),
          "drop.ogg": (drop, 0.3, 0.7, False), "empty.ogg": (empty, 0.2, 0.6, False)}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        print(f"{name:10s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} {'OK' if not probs else 'PROBLEM: ' + '; '.join(probs)}")
        bad += bool(probs)
    sys.exit(1 if bad else 0)
