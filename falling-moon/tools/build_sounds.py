"""Falling Moon sounds: rumble loop, wind loop, incoming roar, impact, countdown beep, start chime."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def rumble():
    d = 4.0
    t = s.t_axis(d)
    low = s.looped(s.lowpass_fast(s.noise(d + 0.6), 70, 2), d, 0.6) * 2
    sub = s.sine(25.0, d) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t))
    return s.normalize(s.soft_clip(low + sub, 1.3), 0.8)


def wind():
    d = 4.0
    t = s.t_axis(d)
    x = s.looped(s.bandpass_fast(s.noise(d + 0.6), 200, 1400), d, 0.6)
    howl = s.looped(s.bandpass_fast(s.noise(d + 0.6), 600, 900), d, 0.6)
    g = 0.6 + 0.4 * np.sin(2 * np.pi * 0.25 * t) * np.sin(2 * np.pi * 0.75 * t + 1)
    return s.normalize(x * g + howl * 0.5 * (1 - g + 0.4), 0.7)


def roar():
    d = 6.0
    n = int(d * s.SR)
    t = s.t_axis(d)
    x = s.lowpass_fast(s.noise(d), 900) * (t / d) ** 2.5 * 2
    x += s.bandpass_fast(s.noise(d), 1000, 5000) * (t / d) ** 4 * 0.8
    x += s.sine(np.linspace(30, 80, n), d) * (t / d) ** 2
    return s.normalize(s.soft_clip(s.fade(x, 0.5, 0.05), 1.5), 0.75)


def impact():
    d = 7.0
    n = int(d * s.SR)
    crack = s.highpass_fast(s.noise(0.15), 600) * s.env_exp(int(0.15 * s.SR), 0.04, 0.0005)
    boom = s.lowpass_fast(s.noise(d), 300, 2) * s.env_exp(n, 1.6, 0.01) * 3
    sub = s.sine(np.linspace(40, 18, n), d) * s.env_exp(n, 2.0, 0.02) * 2
    debris = s.bandpass_fast(s.noise(d), 800, 6000) * s.env_exp(n, 1.0, 0.3) * 0.5
    out = boom + sub + debris
    s.place(out, crack, 0.0, 1.5)
    return s.normalize(s.soft_clip(s.fade(out, 0.001, 1.0), 2.0), 0.72)


def beep():
    d = 0.18
    n = int(d * s.SR)
    return s.normalize((s.sine(880, d) + 0.4 * s.sine(1760, d)) * s.env_adsr(n, 0.003, 0.03, 0.6, 0.06), 0.55)


def chime():
    d = 2.0
    n = int(d * s.SR)
    out = np.zeros(n)
    for k, f in enumerate((220, 277, 330, 440)):
        s.place(out, s.sine(f, 1.6) * s.env_exp(int(1.6 * s.SR), 0.6, 0.01), k * 0.12, 0.6)
    return s.normalize(s.reverb(out, 0.7, 0.35, 0.0)[:n], 0.7)


SOUNDS = {"rumble.ogg": (rumble, 3.0, 5.0, True), "wind.ogg": (wind, 3.0, 5.0, True), "roar.ogg": (roar, 5.0, 7.0, False),
          "impact.ogg": (impact, 6.0, 8.0, False), "beep.ogg": (beep, 0.1, 0.3, False), "chime.ogg": (chime, 1.5, 2.5, False)}

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
