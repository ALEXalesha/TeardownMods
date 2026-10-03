"""Tsunami sounds: warning siren (loop), wave roar (loop), backwash hiss (loop), the crash
when the wave passes, the conch horn when it is called."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def siren():
    d = 4.0
    t = s.t_axis(d)
    f = 520 + 260 * (0.5 - 0.5 * np.cos(2 * np.pi * t / d))   # one rise and fall per loop
    ph = 2 * np.pi * np.cumsum(f) / s.SR
    x = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    x = s.lowpass_fast(x, 3000)
    return s.normalize(s.soft_clip(x, 1.4), 0.7)


def roar():
    d = 4.0
    t = s.t_axis(d)
    body = s.looped(s.lowpass_fast(s.noise(d + 0.6), 350, 2), d, 0.6) * 2
    hiss = s.looped(s.bandpass_fast(s.noise(d + 0.6), 800, 5000), d, 0.6) * 0.6
    surge = 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t)
    return s.normalize(s.soft_clip((body + hiss) * surge, 1.4), 0.8)


def recede():
    d = 4.0
    t = s.t_axis(d)
    hiss = s.looped(s.bandpass_fast(s.noise(d + 0.6), 1500, 7000), d, 0.6)
    gurgle = s.looped(s.bandpass_fast(s.noise(d + 0.6), 150, 500), d, 0.6) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.5 * t))
    return s.normalize(hiss * 0.5 + gurgle, 0.7)


def crash():
    d = 4.0
    n = int(d * s.SR)
    boom = s.lowpass_fast(s.noise(d), 300, 2) * s.env_exp(n, 0.9, 0.02) * 2.5
    spray = s.bandpass_fast(s.noise(d), 1000, 8000) * s.env_exp(n, 1.5, 0.05) * 0.8
    debris = s.bandpass_fast(s.noise(d), 300, 2000) * s.env_exp(n, 1.0, 0.1) * 0.6
    return s.normalize(s.soft_clip(s.fade(boom + spray + debris, 0.005, 0.5), 1.6), 0.8)


def horn():
    d = 2.2
    n = int(d * s.SR)
    f = np.linspace(170, 182, n)
    ph = 2 * np.pi * np.cumsum(f) / s.SR
    x = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph) + 0.1 * np.sin(4 * ph)
    x += s.bandpass_fast(s.noise(d), 300, 1500) * 0.15
    x *= s.env_adsr(n, 0.25, 0.2, 0.8, 0.6)
    return s.normalize(s.reverb(x, 0.6, 0.3, 0.0)[:n], 0.75)


SOUNDS = {"siren.ogg": (siren, 3.0, 5.0, True), "roar.ogg": (roar, 3.0, 5.0, True), "recede.ogg": (recede, 3.0, 5.0, True),
          "crash.ogg": (crash, 3.0, 5.0, False), "horn.ogg": (horn, 1.5, 3.0, False)}

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
