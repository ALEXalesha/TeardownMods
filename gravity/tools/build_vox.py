"""Gravity core voxel model (HUD icon and preview; the mod is key-driven, no hand tool)."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
FRAME, FRAME_DK, CORE, CORE_IN, ARROW = 137, 138, 194, 195, 193


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    for k, c in {FRAME: (90, 96, 108), FRAME_DK: (54, 58, 66), CORE: (60, 200, 255), CORE_IN: (200, 245, 255), ARROW: (255, 200, 60)}.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.3", "_metal": "0.6"}
    for k in (CORE, CORE_IN, ARROW):
        vf.materials[k] = {"_type": "_emit", "_emit": "0.9", "_flux": "3"}
    n = 13
    m = Model("core", (n, n, n))
    c = (n - 1) / 2
    for x in range(n):
        for y in range(n):
            for z in range(n):
                edges = sum(v in (0, n - 1) for v in (x, y, z))
                if edges >= 2:
                    m.set(x, y, z, FRAME if (x + y + z) % 2 else FRAME_DK)
                r = math.sqrt((x - c) ** 2 + (y - c) ** 2 + (z - c) ** 2)
                if r <= 3.4:
                    m.set(x, y, z, CORE_IN if r < 2 else CORE)
    # downward arrow under the core
    arrow = Model("arrow", (5, 5, 6))
    for z in range(6):
        w = 0 if z >= 2 else (2 - z)
        for x in range(5):
            for y in range(5):
                if z >= 2 and abs(x - 2) == 0 and abs(y - 2) == 0:
                    arrow.set(x, y, z, ARROW)
                elif z < 2 and abs(x - 2) <= 2 - z and abs(y - 2) <= 2 - z:
                    arrow.set(x, y, z, ARROW)
    arrow.offset = (0, 0, -10)
    vf.models = [m, arrow]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "core.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["core", "arrow"]
    print("verified core.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
