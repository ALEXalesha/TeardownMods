"""Falling Moon models: brass telescope (hand tool) and the voxel moon.

The moon is a hollow shell (3 voxels thick, radius 80 voxels, 161^3 model) so it stays
around 240k voxels: it is spawned for the last part of the fall and moved every tick,
so it must be light. Spawned at scale R/8 it becomes a sphere of radius R metres.
Grey rock shades (palette range 41-56) with darker maria and real crater dents.
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
BRASS, BRASS_DK, LEATHER, LENS = 153, 154, 155, 193
ROCK, ROCK_DK, ROCK_LT, GLOW = 41, 42, 43, 50
MOON = list(range(44, 52))   # 8 greys, dark to light
MOON_R = 80
MOON_SHELL = 3.0


def palette(vf):
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    cols = {BRASS: (200, 150, 70), BRASS_DK: (140, 100, 44), LEATHER: (90, 50, 30), LENS: (150, 220, 255),
            ROCK: (150, 150, 146), ROCK_DK: (100, 100, 98), ROCK_LT: (190, 190, 184), GLOW: (255, 120, 40)}
    for k, c in cols.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.6", "_metal": "0.2"}
    vf.materials[LENS] = {"_type": "_emit", "_emit": "0.6", "_flux": "2"}
    vf.materials[GLOW] = {"_type": "_emit", "_emit": "1", "_flux": "4"}
    for k, idx in enumerate(MOON):
        g = int(78 + k * 19)
        vf.set_color(idx, (g, g, int(g * 0.97)))
        vf.materials[idx] = {"_type": "_metal", "_rough": "0.9", "_metal": "0.0"}


def telescope() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    m = Model("tube", (5, 16, 5))
    for y in range(16):
        r = 2.4 if y > 9 else (1.9 if y > 4 else 1.5)
        for x in range(5):
            for z in range(5):
                d = math.hypot(x - 2, z - 2)
                if d <= r:
                    idx = BRASS if y % 5 else BRASS_DK
                    if 5 <= y <= 8:
                        idx = LEATHER
                    m.set(x, y, z, idx)
    for x in range(1, 4):
        for z in range(1, 4):
            m.set(x, 15, z, LENS)
    vf.models = [m]
    return vf


def boulder() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(3)
    n = 36
    m = Model("boulder", (n, n, 26))
    c = (n - 1) / 2
    bumps = [(rnd.uniform(0, n), rnd.uniform(0, n), rnd.uniform(0, 26), rnd.uniform(3, 7)) for _ in range(14)]
    for x in range(n):
        for y in range(n):
            for z in range(26):
                dx, dy, dz = (x - c) / 17, (y - c) / 17, (z - 4) / 20
                r = math.sqrt(dx * dx + dy * dy + dz * dz)
                for bx, by, bz, br in bumps:
                    if math.sqrt((x - bx) ** 2 + (y - by) ** 2 + (z - bz) ** 2) < br and r < 1.0:
                        r -= 0.04
                if r <= 1.0:
                    idx = rnd.choice((ROCK, ROCK, ROCK_DK, ROCK_LT))
                    # glowing cracks from the heat of the impact
                    if (abs(x - c - 3 * math.sin(z * 0.4)) < 0.6 or abs(y - c + 2 * math.sin(x * 0.3)) < 0.6) and r > 0.8:
                        idx = GLOW
                    m.set(x, y, z, idx)
    vf.models = [m]
    return vf


def moon() -> VoxFile:
    import numpy as np
    vf = VoxFile()
    palette(vf)
    n = 2 * MOON_R + 1
    rng = np.random.default_rng(11)
    ax = np.arange(n, dtype=np.float32) - MOON_R
    x, y, z = np.meshgrid(ax, ax, ax, indexing="ij")
    d = np.sqrt(x * x + y * y + z * z)
    dirs = np.stack([x, y, z], -1) / np.maximum(d, 1e-6)[..., None]
    # surface height: craters (bowl with a raised rim) as dents in the shell
    h = np.zeros_like(d)
    alb = np.zeros_like(d)
    centres = rng.normal(size=(70, 3))
    centres /= np.linalg.norm(centres, axis=1, keepdims=True)
    sizes = rng.uniform(0.04, 0.28, 70) ** 1.3
    for c, sz in zip(centres, sizes):
        ang = np.arccos(np.clip((dirs * c).sum(-1), -1, 1)) / sz
        h += np.where(ang < 1, -(1 - ang ** 2) * 2.6 * min(1.0, sz * 6), 0)
        h += np.where((ang >= 0.85) & (ang < 1.25), 0.9 * np.cos((ang - 1.05) / 0.2 * 1.57) * min(1.0, sz * 6), 0)
        alb += np.where(ang < 0.9, 0.12, 0)
    # maria: big smooth dark regions
    for c in rng.normal(size=(6, 3)):
        c /= np.linalg.norm(c)
        alb -= 0.55 * np.clip(1 - np.arccos(np.clip((dirs * c).sum(-1), -1, 1)) / rng.uniform(0.35, 0.6), 0, 1) ** 0.7
    outer = MOON_R + np.clip(h, -2.6, 0.9) * 0.9
    shell = (d <= outer) & (d > outer - MOON_SHELL)
    tone = np.clip(0.6 + alb + rng.normal(0, 0.06, d.shape), 0, 0.999)
    idx = np.asarray(MOON, dtype=np.int32)[(tone * len(MOON)).astype(np.int32)]
    m = Model("moon", (n, n, n))
    xs, ys, zs = np.nonzero(shell)
    vals = idx[xs, ys, zs]
    m.voxels = {(int(a), int(b), int(c)): int(v) for a, b, c, v in zip(xs, ys, zs, vals)}
    vf.models = [m]
    return vf


if __name__ == "__main__":
    for name, fn, names in (("telescope.vox", telescope, ["tube"]), ("moon.vox", moon, ["moon"])):
        path = os.path.join(MOD, "vox", name)
        write_vox(path, fn())
        vf = read_vox(path)
        assert [m.name for m in vf.models] == names
        print("verified", name, [(m.name, m.size, len(m.voxels)) for m in vf.models])
        if name == "moon.vox":
            count = len(vf.models[0].voxels)
            assert count < 260000, f"moon shell too heavy: {count} voxels"
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/telescope.vox", 0.3,
                rh=("0.0 -0.05 0.1", "0.0 90.0 0.0"), lh=("0.0 -0.05 -0.3", "90.0 40.0 0.0"),
                poses={"fp_action": ("0.25 -0.3 -0.45", "8.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
