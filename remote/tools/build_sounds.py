"""Remote control sounds: connect, disconnect, hop chirp, radio static loop, out-of-range beeps."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def chirp(f0, f1, d=0.25):
    n = int(d * s.SR)
    x = s.sine(np.geomspace(f0, f1, n), d) * s.env_adsr(n, 0.005, 0.05, 0.7, 0.08)
    return x


def connect():
    out = np.zeros(int(0.5 * s.SR))
    s.place(out, chirp(600, 900, 0.12), 0.0, 0.8)
    s.place(out, chirp(900, 1400, 0.16), 0.14, 0.8)
    s.place(out, s.bandpass_fast(s.noise(0.2), 1500, 6000) * np.linspace(1, 0, int(0.2 * s.SR)) * 0.3, 0.0, 1.0)
    return s.normalize(out, 0.7)


def disconnect():
    out = np.zeros(int(0.5 * s.SR))
    s.place(out, chirp(1200, 700, 0.14), 0.0, 0.8)
    s.place(out, chirp(700, 350, 0.2), 0.16, 0.8)
    return s.normalize(out, 0.7)


def hop():
    out = np.zeros(int(0.35 * s.SR))
    for k in range(3):
        s.place(out, chirp(800 + 300 * k, 1000 + 300 * k, 0.07), k * 0.09, 0.7)
    return s.normalize(out, 0.65)


def static():
    d = 1.5
    x = s.bandpass_fast(s.looped(s.noise(d + 0.3), d, 0.3), 700, 6500)
    crackle = s.looped((s.noise(d + 0.3) > 0.96).astype(float) * s.noise(d + 0.3), d, 0.3)
    return s.normalize(x * 0.6 + crackle, 0.6)


def lost():
    out = np.zeros(int(0.6 * s.SR))
    for k in range(3):
        b = s.sine(440, 0.1) * s.env_adsr(int(0.1 * s.SR), 0.003, 0.02, 0.7, 0.03)
        s.place(out, b, k * 0.17, 1.0)
    return s.normalize(out, 0.55)


SOUNDS = {"connect.ogg": (connect, 0.3, 0.7, False), "disconnect.ogg": (disconnect, 0.3, 0.7, False),
          "hop.ogg": (hop, 0.2, 0.5, False), "static.ogg": (static, 1.0, 2.0, True), "lost.ogg": (lost, 0.4, 0.8, False)}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        print(f"{name:15s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} {'OK' if not probs else 'PROBLEM: ' + '; '.join(probs)}")
        bad += bool(probs)
    sys.exit(1 if bad else 0)
