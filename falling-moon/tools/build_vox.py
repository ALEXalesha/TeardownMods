"""Falling Moon models: brass telescope (hand tool) and the lunar boulder left in the crater."""
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


if __name__ == "__main__":
    for name, fn, names in (("telescope.vox", telescope, ["tube"]), ("boulder.vox", boulder, ["boulder"])):
        path = os.path.join(MOD, "vox", name)
        write_vox(path, fn())
        vf = read_vox(path)
        assert [m.name for m in vf.models] == names
        print("verified", name, [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/telescope.vox", 0.3,
                rh=("0.0 -0.05 0.1", "0.0 90.0 0.0"), lh=("0.0 -0.05 -0.3", "90.0 40.0 0.0"),
                poses={"fp_action": ("0.25 -0.3 -0.45", "8.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
