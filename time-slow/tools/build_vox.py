"""Hourglass voxel model (used for the HUD icon and the preview; the mod has no hand tool)."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
WOOD, WOOD_DK, GLASS, SAND = 57, 58, 1, 194


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    vf.set_color(WOOD, (120, 74, 40))
    vf.set_color(WOOD_DK, (84, 50, 26))
    vf.set_color(GLASS, (170, 220, 255))
    vf.set_color(SAND, (120, 200, 255))
    vf.materials[GLASS] = {"_type": "_glass", "_alpha": "0.4", "_trans": "0.4"}
    vf.materials[SAND] = {"_type": "_emit", "_emit": "0.8", "_flux": "3"}
    n, h = 11, 17
    c = (n - 1) / 2
    m = Model("hourglass", (n, n, h))
    for z in range(h):
        for x in range(n):
            for y in range(n):
                r = math.hypot(x - c, y - c)
                if z <= 1 or z >= h - 2:
                    if r <= 5.2:
                        m.set(x, y, z, WOOD if z in (0, h - 1) else WOOD_DK)
                    continue
                # posts at the corners
                if abs(x - c) >= 4 and abs(y - c) >= 4 and r <= 6.2:
                    m.set(x, y, z, WOOD_DK)
                    continue
                # glass bulbs: radius narrows towards the middle
                t = abs(z - (h - 1) / 2) / ((h - 1) / 2 - 2)
                rad = 0.8 + 3.2 * min(1, t) ** 0.8
                if abs(r - rad) < 0.6:
                    m.set(x, y, z, GLASS)
                elif r < rad - 0.4:
                    # sand: bottom bulb fuller, stream in the middle
                    if z < (h - 1) / 2 - 1 and z < 6:
                        m.set(x, y, z, SAND)
                    elif z > (h - 1) / 2 + 1 and z > 11 and r < rad - 1.2:
                        m.set(x, y, z, SAND)
                    elif r < 0.8:
                        m.set(x, y, z, SAND)
    vf.models = [m]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "hourglass.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert vf.models[0].name == "hourglass" and len(vf.models[0].voxels) > 200
    print("verified hourglass.vox", vf.models[0].size, len(vf.models[0].voxels))
