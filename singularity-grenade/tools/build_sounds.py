"""Synthesize all Singularity Grenade sounds into mod/snd/*.ogg (mono Vorbis 44.1 kHz)."""
from __future__ import annotations

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import synth as s  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "snd")


def throw() -> np.ndarray:
    d = 0.42
    n = int(d * s.SR)
    t = s.t_axis(d)
    # whoosh: noise through a band that sweeps up then down
    nz = s.noise(d)
    lo = s.bandpass_fast(nz, 300, 1200)
    hi = s.bandpass_fast(nz, 1500, 5000)
    shape = np.sin(np.pi * np.clip(t / d, 0, 1)) ** 1.5
    sweep = np.clip(np.sin(np.pi * t / d * 1.1), 0, 1)
    w = lo * shape * 0.9 + hi * shape * sweep * 0.5
    # short cloth/hand click at the start
    click = s.bandpass_fast(s.noise(0.02), 800, 3000) * s.env_exp(int(0.02 * s.SR), 0.004)
    out = s.place(w, click, 0.0, 0.6)
    return s.normalize(s.fade(out, 0.003, 0.05), 0.8)


def bounce() -> np.ndarray:
    d = 0.32
    n = int(d * s.SR)
    out = np.zeros(n)
    # metallic inharmonic partials of a small brass ring
    for f, a, tau in ((1180, 1.0, 0.09), (1912, 0.7, 0.07), (2795, 0.5, 0.05), (4108, 0.35, 0.03), (5320, 0.2, 0.02)):
        out += s.sine(f, d) * s.env_exp(n, tau, 0.0008) * a
    thud = s.sine(np.linspace(160, 70, n), d) * s.env_exp(n, 0.035, 0.001) * 1.2
    tick = s.highpass_fast(s.noise(d), 2000) * s.env_exp(n, 0.004, 0.0005) * 0.6
    return s.normalize(s.fade(out * 0.6 + thud + tick, 0.0005, 0.03), 0.85)


def beep() -> np.ndarray:
    d = 0.11
    n = int(d * s.SR)
    e = s.env_adsr(n, 0.004, 0.03, 0.6, 0.05)
    out = (s.sine(1620, d) + 0.3 * s.sine(3240, d) + 0.15 * s.square(810, d, 0.5) * 0.3) * e
    return s.normalize(out, 0.6)


def open_() -> np.ndarray:
    d = 1.4
    n = int(d * s.SR)
    t = s.t_axis(d)
    # rising reversed swell (air being sucked in)
    swell_d = 0.45
    sw = s.lowpass_fast(s.noise(swell_d), 2500) * (np.linspace(0, 1, int(swell_d * s.SR)) ** 3)
    # descending "vwoom": saw sweeping 900 -> 55 Hz through a closing filter
    f = 55 + 845 * np.exp(-t / 0.18)
    vw = s.saw(f, d)
    vw = s.lowpass_fast(vw, 1400) * s.env_exp(n, 0.55, 0.01)
    sub = s.sine(np.linspace(70, 38, n), d) * s.env_exp(n, 0.7, 0.02) * 1.3
    shimmer = (s.sine(1320 + 80 * np.sin(2 * np.pi * 7 * t), d) * 0.15) * s.env_exp(n, 0.3, 0.05)
    out = np.zeros(n)
    s.place(out, sw, 0.0, 0.7)
    s.place(out, vw + sub + shimmer, 0.38, 1.0)
    out = s.soft_clip(out * 0.9, 1.4)
    return s.normalize(s.fade(out, 0.01, 0.15), 0.8)


def hum_loop() -> np.ndarray:
    # 4 s loop; every periodic component completes whole cycles in 4 s
    d = 4.0
    n = int(d * s.SR)
    t = s.t_axis(d)
    lfo = np.sin(2 * np.pi * 0.5 * t)            # 2 cycles
    wob = np.sin(2 * np.pi * 3.0 * t)            # 12 cycles
    drone = s.saw(46.0, d) * 0.5 + s.saw(46.5, d) * 0.5   # 46 and 46.5 Hz -> 184 / 186 cycles
    drone = s.lowpass_fast(drone, 260)
    sub = s.sine(23.0, d) * 0.8
    mid = s.sine(184.0 + 0 * t, d) * (0.18 + 0.1 * wob)
    choir = (s.sine(368.0, d) + 0.6 * s.sine(552.0, d)) * 0.07 * (0.6 + 0.4 * lfo)
    # swirling wind: noise through a slowly moving band, crossfaded into a loop
    wind_src = s.noise(d + 0.5)
    wind = s.bandpass_fast(wind_src, 250, 900) * 0.35
    wind = s.make_loop(wind, 0.5)[:n]
    if len(wind) < n:
        wind = np.pad(wind, (0, n - len(wind)))
    wind *= (0.6 + 0.4 * np.sin(2 * np.pi * 1.0 * t + 1.0))
    out = drone + sub + mid + choir + wind
    out = s.soft_clip(out * 0.8, 1.2)
    return s.normalize(out, 0.8)


def collapse() -> np.ndarray:
    d = 2.8
    n = int(d * s.SR)
    out = np.zeros(n)
    # 0.0-0.32 s: implosion, a rising suck with pitch going up
    imp_d = 0.32
    ti = s.t_axis(imp_d)
    imp = s.lowpass_fast(s.noise(imp_d), 3000) * (ti / imp_d) ** 2
    imp += s.sine(200 + 1400 * (ti / imp_d) ** 2, imp_d) * 0.25 * (ti / imp_d)
    s.place(out, imp, 0.0, 0.8)
    # boom at 0.32 s
    bd = d - 0.32
    nb = int(bd * s.SR)
    tb = s.t_axis(bd)
    crack = s.highpass_fast(s.noise(0.05), 1500) * s.env_exp(int(0.05 * s.SR), 0.01, 0.0005)
    body = s.lowpass_fast(s.noise(bd), 900) * s.env_exp(nb, 0.35, 0.002) * 1.4
    rumble = s.lowpass_fast(s.noise(bd), 160) * s.env_exp(nb, 0.9, 0.01) * 2.5
    sub = s.sine(np.linspace(62, 28, nb), bd) * s.env_exp(nb, 0.6, 0.003) * 1.6
    ring = s.sine(np.linspace(880, 440, nb), bd) * s.env_exp(nb, 0.25, 0.002) * 0.18
    boom = body + rumble + sub + ring
    s.place(out, boom, 0.32, 1.0)
    s.place(out, crack, 0.32, 0.9)
    out = s.soft_clip(out, 1.8)
    return s.normalize(s.fade(out, 0.002, 0.4), 0.8)


SOUNDS = {
    "throw.ogg": (throw, 0.3, 0.6, False),
    "bounce.ogg": (bounce, 0.2, 0.5, False),
    "beep.ogg": (beep, 0.05, 0.2, False),
    "open.ogg": (open_, 1.0, 2.0, False),
    "hum.ogg": (hum_loop, 3.0, 5.0, True),
    "collapse.ogg": (collapse, 2.0, 3.5, False),
}


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, (fn, lo, hi, loop) in SOUNDS.items():
        path = os.path.join(OUT, name)
        s.write_ogg(path, fn())
        probs = s.check_sound(path, lo, hi, loop)
        info = s.probe(path)
        status = "OK" if not probs else "PROBLEM: " + "; ".join(probs)
        print(f"{name:14s} {float(info['duration']):5.2f}s peak={info['peak']:.2f} rms={info['rms']:.3f} {status}")
        bad += bool(probs)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
