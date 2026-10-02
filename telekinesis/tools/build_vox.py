"""Telekinesis gauntlet: dark glove with brass knuckles and a glowing violet orb in the palm."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
GLOVE, GLOVE_DK, BRASS, ORB, ORB_IN = 137, 138, 153, 194, 195


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    for k, c in {GLOVE: (48, 40, 56), GLOVE_DK: (30, 26, 36), BRASS: (200, 150, 70), ORB: (170, 80, 255), ORB_IN: (240, 200, 255)}.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.5", "_metal": "0.3"}
    vf.materials[ORB] = {"_type": "_emit", "_emit": "0.8", "_flux": "3"}
    vf.materials[ORB_IN] = {"_type": "_emit", "_emit": "1", "_flux": "4"}
    glove = Model("glove", (7, 11, 4))
    for x in range(7):
        for y in range(11):
            for z in range(4):
                if y >= 8 and x % 2 == 1:
                    continue  # gaps between fingers
                idx = GLOVE if z > 0 else GLOVE_DK
                if y == 7:
                    idx = BRASS
                if y < 3:
                    idx = GLOVE_DK  # cuff
                glove.set(x, y, z, idx)
    orb = Model("orb", (5, 5, 5))
    for x in range(5):
        for y in range(5):
            for z in range(5):
                r = math.sqrt((x - 2) ** 2 + (y - 2) ** 2 + (z - 2) ** 2)
                if r <= 2.3:
                    orb.set(x, y, z, ORB_IN if r < 1.2 else ORB)
    orb.offset = (0, 0, 4)
    vf.models = [glove, orb]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "gauntlet.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["glove", "orb"]
    print("verified gauntlet.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/gauntlet.vox", 0.3,
                rh=("0.0 -0.1 0.2", "0.0 90.0 0.0"),
                poses={"fp_action": ("0.3 -0.35 -0.5", "-60.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
