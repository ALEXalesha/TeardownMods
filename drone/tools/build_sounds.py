"""Drone sounds: rotor hum loop, radio static loop, crash, drop click, deploy, pack, low-battery and signal beeps."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def hum():
    d = 2.0
    t = s.t_axis(d)
    # four rotors with slightly different blade-pass frequencies (all whole cycles in 2 s)
    out = np.zeros(int(d * s.SR))
    for f in (180.0, 183.5, 186.0, 189.5):
        x = s.saw(f, d) * 0.5 + s.sine(f * 2, d) * 0.3
        out += x
    out = s.lowpass_fast(out, 2500)
    air = s.looped(s.bandpass_fast(s.noise(d + 0.4), 400, 3000), d, 0.4) * 0.5
    out = out * (0.85 + 0.15 * np.sin(2 * np.pi * 7 * t)) + air
    return s.normalize(out, 0.7)


def static():
    d = 1.5
    x = s.looped(s.noise(d + 0.3), d, 0.3)
    x = s.bandpass_fast(x, 800, 7000)
    crackle = s.looped((s.noise(d + 0.3) > 0.97).astype(float) * s.noise(d + 0.3), d, 0.3)
    return s.normalize(x * 0.6 + crackle, 0.6)


def crash():
    d = 1.0
    n = int(d * s.SR)
    out = s.bandpass_fast(s.noise(d), 300, 5000) * s.env_exp(n, 0.12, 0.001)
    rng = np.random.default_rng(4)
    for k in range(20):
        c = s.bandpass_fast(s.noise(0.02), 1500, 8000) * s.env_exp(int(0.02 * s.SR), 0.004)
        s.place(out, c, 0.05 + rng.random() * 0.7, 0.4 * rng.random())
    out += s.sine(np.linspace(140, 50, n), d) * s.env_exp(n, 0.08) * 0.8
    return s.normalize(s.fade(out, 0.0005, 0.1), 0.85)


def drop():
    d = 0.25
    n = int(d * s.SR)
    clk = s.highpass_fast(s.noise(d), 2500) * s.env_exp(n, 0.006, 0.0003)
    tone = s.sine(np.linspace(1200, 700, n), d) * s.env_exp(n, 0.06) * 0.4
    return s.normalize(clk + tone, 0.7)


def whir(up: bool):
    d = 1.0
    n = int(d * s.SR)
    f = np.linspace(40, 186, n) if up else np.linspace(186, 30, n)
    x = s.saw(f, d) * 0.5 + s.sine(f * 2, d) * 0.3
    x = s.lowpass_fast(x, 2500) * (np.linspace(0.2, 1, n) if up else np.linspace(1, 0, n) ** 1.5)
    return s.normalize(s.fade(x, 0.01, 0.05), 0.7)


def beep(f, reps):
    d = 0.5
    out = np.zeros(int(d * s.SR))
    for k in range(reps):
        b = s.sine(f, 0.08) * s.env_adsr(int(0.08 * s.SR), 0.003, 0.02, 0.7, 0.02)
        s.place(out, b, k * 0.14, 1.0)
    return s.normalize(out, 0.55)


SOUNDS = {
    "hum.ogg": (hum, 1.5, 2.5, True), "static.ogg": (static, 1.0, 2.0, True), "crash.ogg": (crash, 0.6, 1.5, False),
    "drop.ogg": (drop, 0.1, 0.4, False), "deploy.ogg": (lambda: whir(True), 0.6, 1.5, False),
    "pack.ogg": (lambda: whir(False), 0.6, 1.5, False), "battery.ogg": (lambda: beep(880, 3), 0.3, 0.7, False),
    "signal.ogg": (lambda: beep(440, 2), 0.3, 0.7, False),
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
