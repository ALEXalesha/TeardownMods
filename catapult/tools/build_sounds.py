"""Catapult sounds: wooden creak when placing/aiming, the swing (whoosh + thump of the arm),
the release twang, an incoming whistle loop for flying projectiles, and the impact crash."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def creak():
    d = 1.2
    n = int(d * s.SR)
    t = s.t_axis(d)
    f = 180 + 60 * np.sin(2 * np.pi * 1.3 * t) + 40 * np.sin(2 * np.pi * 7 * t)
    ph = 2 * np.pi * np.cumsum(f) / s.SR
    x = (np.sin(ph) + 0.6 * np.sin(2.01 * ph) + 0.3 * np.sin(3.03 * ph)) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 9 * t)))
    x = s.bandpass_fast(x + s.noise(d) * 0.2, 150, 2500) * s.env_adsr(n, 0.05, 0.2, 0.7, 0.4)
    return s.normalize(x, 0.7)


def swing():
    d = 1.6
    n = int(d * s.SR)
    t = s.t_axis(d)
    whoosh = s.bandpass_fast(s.noise(d), 200, 1800) * np.exp(-((t - 0.35) / 0.18) ** 2) * 1.4
    thump = np.zeros(n)
    s.place(thump, s.lowpass_fast(s.noise(0.5), 160, 2) * s.env_exp(int(0.5 * s.SR), 0.12), 0.55, 2.5)
    rattle = s.bandpass_fast(s.noise(d), 600, 3000) * s.env_exp(n, 0.3, 0.55) * 0.3
    return s.normalize(s.fade(whoosh + thump + rattle, 0.01, 0.3), 0.8)


def twang():
    d = 0.9
    n = int(d * s.SR)
    f = np.linspace(140, 95, n)
    ph = 2 * np.pi * np.cumsum(f) / s.SR
    x = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)) * s.env_exp(n, 0.25, 0.002)
    return s.normalize(x + s.highpass_fast(s.noise(d), 2000) * s.env_exp(n, 0.02) * 0.5, 0.75)


def whistle():
    d = 3.0
    t = s.t_axis(d)
    air = s.looped(s.bandpass_fast(s.noise(d + 0.6), 700, 2600), d, 0.6)
    tone = s.sine(900.0, d) * 0.15 * (0.7 + 0.3 * np.sin(2 * np.pi * (1 / 1.5) * t))
    return s.normalize(air + tone, 0.6)


def impact():
    d = 2.2
    n = int(d * s.SR)
    boom = s.lowpass_fast(s.noise(d), 260, 2) * s.env_exp(n, 0.35, 0.003) * 2.5
    crack = s.highpass_fast(s.noise(d), 1500) * s.env_exp(n, 0.05) * 1.0
    debris = s.bandpass_fast(s.noise(d), 500, 5000) * s.env_exp(n, 0.7, 0.05) * 0.6
    return s.normalize(s.soft_clip(s.fade(boom + crack + debris, 0.001, 0.4), 1.6), 0.7)


SOUNDS = {"creak.ogg": (creak, 1.0, 1.5, False), "swing.ogg": (swing, 1.2, 2.0, False), "twang.ogg": (twang, 0.6, 1.2, False),
          "whistle.ogg": (whistle, 2.5, 3.5, True), "impact.ogg": (impact, 1.8, 2.6, False)}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        print(f"{name:11s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} {'OK' if not probs else 'PROBLEM: ' + '; '.join(probs)}")
        bad += bool(probs)
    sys.exit(1 if bad else 0)
