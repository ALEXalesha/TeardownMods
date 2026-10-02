"""Time-slow sounds: enter / exit whooshes, heartbeat loop, empty buzz, preset click."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def whoosh(down: bool) -> np.ndarray:
    d = 0.9
    n = int(d * s.SR)
    t = s.t_axis(d)
    f = np.geomspace(900, 70, n) if down else np.geomspace(70, 900, n)
    tone = s.saw(f, d)
    tone = s.lowpass_fast(tone, 1800) * 0.5
    air = s.bandpass_fast(s.noise(d), 300, 2500)
    env = np.sin(np.pi * np.clip(t / d, 0, 1)) ** (0.6 if down else 1.4)
    sub = s.sine(np.geomspace(120, 35, n) if down else np.geomspace(35, 120, n), d) * 0.8
    x = (tone + air * 0.6 + sub) * env
    if down:
        x = s.reverb(x, 0.6, 0.35, 0.6)
    return s.normalize(s.fade(x, 0.005, 0.1), 0.78)


def heartbeat() -> np.ndarray:
    d = 1.2   # 50 bpm in slow time
    n = int(d * s.SR)
    out = np.zeros(n)
    for at, a in ((0.0, 1.0), (0.22, 0.7)):
        bd = 0.18
        nb = int(bd * s.SR)
        b = s.sine(np.linspace(70, 40, nb), bd) * s.env_exp(nb, 0.05, 0.004)
        b += s.lowpass_fast(s.noise(bd), 200) * s.env_exp(nb, 0.03) * 0.4
        s.place(out, b, at + 0.01, a)
    return s.normalize(out, 0.8)


def empty() -> np.ndarray:
    d = 0.45
    n = int(d * s.SR)
    x = (s.square(np.linspace(220, 110, n), d) * 0.4 + s.sine(np.linspace(440, 220, n), d) * 0.4)
    x = s.lowpass_fast(x, 2000) * s.env_adsr(n, 0.005, 0.1, 0.7, 0.15)
    return s.normalize(x, 0.6)


def click() -> np.ndarray:
    d = 0.12
    n = int(d * s.SR)
    x = (s.sine(1400, d) + 0.5 * s.sine(2100, d)) * s.env_exp(n, 0.025, 0.001)
    return s.normalize(x, 0.5)


SOUNDS = {
    "enter.ogg": (lambda: whoosh(True), 0.8, 2.0, False),
    "exit.ogg": (lambda: whoosh(False), 0.6, 1.2, False),
    "heartbeat.ogg": (heartbeat, 1.0, 1.4, True),
    "empty.ogg": (empty, 0.3, 0.6, False),
    "click.ogg": (click, 0.05, 0.2, False),
}

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
