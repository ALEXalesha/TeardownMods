"""Volcano sounds: rock grinding while it grows (loop), deep rumble (loop), eruption roar
(loop), bomb launch, bomb impact (thud and sizzle), final blast, placing chime."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def grind():
    d = 3.0
    t = s.t_axis(d)
    crunch = s.looped(s.bandpass_fast(s.noise(d + 0.6), 120, 900), d, 0.6)
    pops = np.zeros(int(d * s.SR))
    rng = np.random.default_rng(4)
    for at in rng.uniform(0.05, d - 0.2, 40):
        n = int(0.06 * s.SR)
        s.place(pops, s.lowpass_fast(s.noise(0.06), 600) * s.env_exp(n, 0.015), at, rng.uniform(0.4, 1.0))
    pops = s.looped(np.concatenate([pops, pops[: int(0.6 * s.SR)]]), d, 0.6)
    low = s.sine(38.0, d) * (0.7 + 0.3 * np.sin(2 * np.pi * (1 / 3.0) * t))
    return s.normalize(s.soft_clip(crunch * 1.2 + pops + low * 0.6, 1.4), 0.8)


def rumble():
    d = 4.0
    t = s.t_axis(d)
    low = s.looped(s.lowpass_fast(s.noise(d + 0.6), 60, 2), d, 0.6) * 2.5
    sub = s.sine(22.0, d) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t))
    return s.normalize(s.soft_clip(low + sub, 1.3), 0.8)


def roar():
    d = 4.0
    t = s.t_axis(d)
    body = s.looped(s.lowpass_fast(s.noise(d + 0.6), 400), d, 0.6) * 1.6
    hiss = s.looped(s.bandpass_fast(s.noise(d + 0.6), 1500, 6000), d, 0.6) * 0.35
    surge = 0.75 + 0.25 * np.sin(2 * np.pi * 0.75 * t) * np.sin(2 * np.pi * 0.25 * t + 0.5)
    return s.normalize(s.soft_clip((body + hiss) * surge, 1.5), 0.8)


def launch():
    d = 0.9
    n = int(d * s.SR)
    thump = s.lowpass_fast(s.noise(d), 250, 2) * s.env_exp(n, 0.12) * 2
    whoosh = s.bandpass_fast(s.noise(d), 500, 3000) * s.env_adsr(n, 0.05, 0.2, 0.4, 0.5) * 0.5
    return s.normalize(s.fade(thump + whoosh, 0.002, 0.1), 0.8)


def impact():
    d = 1.6
    n = int(d * s.SR)
    thud = s.lowpass_fast(s.noise(d), 300, 2) * s.env_exp(n, 0.1) * 2
    crack = s.highpass_fast(s.noise(d), 1500) * s.env_exp(n, 0.03) * 0.8
    sizzle = s.bandpass_fast(s.noise(d), 3000, 9000) * s.env_adsr(n, 0.05, 0.3, 0.5, 0.8) * 0.35
    return s.normalize(s.fade(thud + crack + sizzle, 0.001, 0.2), 0.8)


def blast():
    d = 6.0
    n = int(d * s.SR)
    boom = s.lowpass_fast(s.noise(d), 250, 2) * s.env_exp(n, 1.4, 0.01) * 3
    sub = s.sine(np.linspace(45, 16, n), d) * s.env_exp(n, 1.8, 0.02) * 2
    rubble = s.bandpass_fast(s.noise(d), 600, 5000) * s.env_exp(n, 1.2, 0.3) * 0.5
    crack = s.highpass_fast(s.noise(0.12), 700) * s.env_exp(int(0.12 * s.SR), 0.03)
    out = boom + sub + rubble
    s.place(out, crack, 0.0, 1.5)
    return s.normalize(s.soft_clip(s.fade(out, 0.001, 1.0), 2.0), 0.75)


def place():
    d = 1.6
    n = int(d * s.SR)
    out = np.zeros(n)
    for k, f in enumerate((110, 147, 165)):
        s.place(out, s.sine(f, 1.3) * s.env_exp(int(1.3 * s.SR), 0.5, 0.01), k * 0.1, 0.6)
    out += s.lowpass_fast(s.noise(d), 200) * s.env_exp(n, 0.4) * 0.6
    return s.normalize(s.reverb(out, 0.6, 0.3, 0.0)[:n], 0.7)


SOUNDS = {"grind.ogg": (grind, 2.5, 3.5, True), "rumble.ogg": (rumble, 3.0, 5.0, True), "roar.ogg": (roar, 3.0, 5.0, True),
          "launch.ogg": (launch, 0.5, 1.2, False), "impact.ogg": (impact, 1.0, 2.0, False), "blast.ogg": (blast, 5.0, 7.0, False),
          "place.ogg": (place, 1.0, 2.0, False)}

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
