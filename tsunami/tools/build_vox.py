"""Tsunami model: the hand-held conch horn (tool). The wave itself is drawn with sprites."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
CREAM, PINK, BROWN, DARK = 153, 154, 155, 156


def conch() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    for k, c in {CREAM: (236, 220, 196), PINK: (240, 160, 150), BROWN: (150, 100, 70), DARK: (90, 60, 50)}.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.4", "_metal": "0.0"}
    m = Model("conch", (11, 18, 11))
    c = 5
    for y in range(18):
        t = y / 17
        r = 1.0 + 4.0 * math.sin(min(1.0, t * 1.15) * math.pi * 0.95) * (1 - 0.35 * t)
        for x in range(11):
            for z in range(11):
                dx, dz = x - c, z - c
                d = math.hypot(dx, dz)
                if d <= r:
                    ang = math.atan2(dz, dx)
                    band = (ang * 2 + y * 0.9) % (2 * math.pi) < 0.9
                    idx = BROWN if band else CREAM
                    if y > 12 and d < r - 1.5:
                        idx = PINK            # the open mouth
                        if d < r - 2.5:
                            continue
                    if y < 2:
                        idx = DARK            # mouthpiece
                    m.set(x, y, z, idx)
    vf.models = [m]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "conch.vox")
    write_vox(path, conch())
    vf = read_vox(path)
    print("verified conch.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/conch.vox", 0.35,
                rh=("0.0 -0.05 0.05", "0.0 90.0 0.0"),
                poses={"fp_action": ("0.25 -0.25 -0.4", "70.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
