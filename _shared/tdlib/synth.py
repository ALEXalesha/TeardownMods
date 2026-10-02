"""Tiny procedural sound synthesis toolkit (numpy) + OGG export via ffmpeg.

Everything works on float32 mono arrays at 44100 Hz in range [-1, 1].
Teardown's own mods ship mono Vorbis .ogg at 44.1 kHz, so export matches that.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(12345)


def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def silence(dur: float) -> np.ndarray:
    return np.zeros(int(dur * SR), dtype=np.float64)


def sine(freq, dur: float, phase: float = 0.0) -> np.ndarray:
    """freq may be a scalar or an array (per-sample frequency, for sweeps)."""
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    return np.sin(ph)


def saw(freq, dur: float) -> np.ndarray:
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = np.cumsum(f) / SR
    return 2 * (ph - np.floor(ph + 0.5))


def square(freq, dur: float, duty: float = 0.5) -> np.ndarray:
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = np.cumsum(f) / SR
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def noise(dur: float) -> np.ndarray:
    return rng.uniform(-1, 1, int(dur * SR))


def lowpass(x: np.ndarray, cutoff) -> np.ndarray:
    """One-pole low-pass; cutoff may be scalar or per-sample array (Hz)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1.0 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):  # small sounds only; fine in python
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def lowpass_fast(x: np.ndarray, cutoff: float, passes: int = 1) -> np.ndarray:
    """Static cutoff low-pass via FFT brick-ish filter with smooth roll-off."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    resp = 1.0 / np.sqrt(1.0 + (f / max(cutoff, 1.0)) ** (2 * 2 * passes))
    return np.fft.irfft(X * resp, n=len(x))


def highpass_fast(x: np.ndarray, cutoff: float) -> np.ndarray:
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    resp = 1.0 / np.sqrt(1.0 + (max(cutoff, 1.0) / np.maximum(f, 1e-3)) ** 4)
    return np.fft.irfft(X * resp, n=len(x))


def bandpass_fast(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return highpass_fast(lowpass_fast(x, hi), lo)


def env_adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    """Attack/decay/release in seconds, sustain level 0..1 over n samples."""
    e = np.full(n, s, dtype=np.float64)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na, endpoint=False) if na else e[:na]
    nd2 = min(nd, n - na)
    if nd2 > 0:
        e[na:na + nd2] = np.linspace(1, s, nd2, endpoint=False)
    nr = min(nr, n)
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr)
    return e


def env_exp(n: int, tau: float, attack: float = 0.002) -> np.ndarray:
    t = np.arange(n) / SR
    e = np.exp(-t / tau)
    na = int(attack * SR)
    if na > 0:
        e[:na] *= np.linspace(0, 1, na)
    return e


def fade(x: np.ndarray, fin: float = 0.005, fout: float = 0.02) -> np.ndarray:
    y = x.copy()
    ni, no = int(fin * SR), int(fout * SR)
    if ni:
        y[:ni] *= np.linspace(0, 1, ni)
    if no:
        y[-no:] *= np.linspace(1, 0, no)
    return y


def mix(*parts, length: int | None = None) -> np.ndarray:
    n = length or max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:min(n, len(p))] += p[:n]
    return out


def place(base: np.ndarray, part: np.ndarray, at: float, gain: float = 1.0) -> np.ndarray:
    i = int(at * SR)
    end = min(len(base), i + len(part))
    if end > i:
        base[i:end] += part[:end - i] * gain
    return base


def normalize(x: np.ndarray, peak: float = 0.89) -> np.ndarray:
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (peak / m)


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def make_loop(x: np.ndarray, xfade: float = 0.25) -> np.ndarray:
    """Crossfade tail into head so the sound loops seamlessly."""
    n = int(xfade * SR)
    body = x[:-n].copy()
    tail = x[-n:]
    w = np.linspace(0, 1, n)
    body[:n] = body[:n] * np.sqrt(w) + tail * np.sqrt(1 - w)
    return body


def reverb(x: np.ndarray, room: float = 0.4, wet: float = 0.25, tail: float = 1.0) -> np.ndarray:
    """Cheap feedback comb reverb."""
    out = np.concatenate([x, np.zeros(int(tail * SR))])
    wet_sig = np.zeros_like(out)
    for d, g in ((0.0297, 0.77), (0.0371, 0.74), (0.0411, 0.72), (0.0437, 0.70)):
        dl = int(d * SR * (0.6 + room))
        buf = out.copy()
        y = np.zeros_like(out)
        # feedback comb approximated by a few decaying echoes
        for k in range(1, 8):
            sh = dl * k
            if sh >= len(out):
                break
            y[sh:] += buf[:-sh] * (g ** k)
        wet_sig += y
    return out * (1 - wet) + normalize(wet_sig, np.max(np.abs(out)) + 1e-9) * wet


# ------------------------------------------------------------------ export

def write_wav(path: str, x: np.ndarray) -> None:
    y = np.clip(x, -1, 1)
    pcm = (y * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)


def write_ogg(path: str, x: np.ndarray, quality: int = 5) -> None:
    ff = shutil.which("ffmpeg")
    if not ff:
        raise RuntimeError("ffmpeg not found in PATH")
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "s.wav")
        write_wav(wav, x)
        subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis",
                        "-q:a", str(quality), "-ac", "1", "-ar", str(SR), path], check=True)


def probe(path: str) -> dict:
    """Return codec, sample rate, channels, duration and decoded peak (via ffmpeg)."""
    fp = shutil.which("ffprobe")
    out = subprocess.run([fp, "-v", "error", "-show_entries", "stream=codec_name,sample_rate,channels:format=duration",
                          "-of", "default=nw=1", path], capture_output=True, text=True, check=True).stdout
    info = {}
    for line in out.splitlines():
        k, _, v = line.partition("=")
        info[k] = v
    raw = subprocess.run([shutil.which("ffmpeg"), "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-"],
                         capture_output=True, check=True).stdout
    pcm = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    info["peak"] = float(np.max(np.abs(pcm))) if len(pcm) else 0.0
    info["rms"] = float(np.sqrt(np.mean(pcm ** 2))) if len(pcm) else 0.0
    info["clipped_samples"] = int(np.sum(np.abs(pcm) >= 0.999))
    # loop seam: difference between last and first samples relative to typical step
    if len(pcm) > 100:
        step = np.mean(np.abs(np.diff(pcm[:2000]))) + 1e-6
        info["seam_jump"] = float(abs(pcm[-1] - pcm[0]) / step)
    return info


def check_sound(path: str, min_dur: float, max_dur: float, loop: bool = False) -> list[str]:
    """Return a list of problems (empty if fine)."""
    p = probe(path)
    probs = []
    if p.get("codec_name") != "vorbis":
        probs.append(f"codec {p.get('codec_name')} is not vorbis")
    if p.get("sample_rate") != "44100":
        probs.append(f"sample rate {p.get('sample_rate')}")
    if p.get("channels") != "1":
        probs.append(f"channels {p.get('channels')}")
    d = float(p.get("duration", 0))
    if not (min_dur <= d <= max_dur):
        probs.append(f"duration {d:.2f}s outside [{min_dur}, {max_dur}]")
    if p["peak"] > 0.995 or p["clipped_samples"] > 0:
        probs.append(f"clipping: peak {p['peak']:.3f}, {p['clipped_samples']} clipped samples")
    if p["peak"] < 0.05:
        probs.append(f"too quiet: peak {p['peak']:.3f}")
    if loop and p.get("seam_jump", 0) > 40:
        probs.append(f"loop seam jump {p['seam_jump']:.1f}x typical step")
    return probs


def fit(x: np.ndarray, n: int) -> np.ndarray:
    """Pad with zeros or truncate to exactly n samples."""
    if len(x) >= n:
        return x[:n]
    return np.pad(x, (0, n - len(x)))


def looped(x_longer: np.ndarray, dur: float, xfade: float = 0.5) -> np.ndarray:
    """Turn a signal longer than dur into a seamless loop of exactly dur seconds.

    The part after `dur` (up to xfade seconds) is crossfaded into the start.
    """
    n = int(round(dur * SR))
    m = min(int(round(xfade * SR)), len(x_longer) - n)
    if m <= 0:
        raise ValueError("looped: source must be longer than the loop")
    body = x_longer[:n].copy()
    tail = x_longer[n:n + m]
    w = np.linspace(0, 1, m)
    body[:m] = body[:m] * np.sqrt(w) + tail * np.sqrt(1 - w)
    return body
