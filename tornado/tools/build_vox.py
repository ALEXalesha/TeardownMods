"""Storm caller model: handheld unit with a radar screen and a spinning dish (separate shape)."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
CASE, CASE_DK, GRIP, DISH, SCREEN, BLIP = 137, 138, 139, 153, 194, 193


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    for k, c in {CASE: (70, 84, 96), CASE_DK: (44, 52, 60), GRIP: (28, 28, 30), DISH: (200, 204, 210),
                 SCREEN: (40, 200, 90), BLIP: (255, 220, 60)}.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.4", "_metal": "0.5"}
    vf.materials[SCREEN] = {"_type": "_emit", "_emit": "0.6", "_flux": "2"}
    vf.materials[BLIP] = {"_type": "_emit", "_emit": "1", "_flux": "3"}
    body = Model("body", (7, 9, 4))
    for x in range(7):
        for y in range(9):
            for z in range(4):
                idx = CASE if z < 3 else CASE_DK
                if y < 3 and z < 2:
                    idx = GRIP
                body.set(x, y, z, idx)
    # round radar screen on the top face, facing the player (vox y small = towards player)
    for x in range(7):
        for y in range(9):
            if math.hypot(x - 3, y - 5) <= 2.6:
                body.set(x, y, 3, SCREEN)
    body.set(4, 6, 3, BLIP)
    body.set(2, 4, 3, BLIP)
    dish = Model("dish", (7, 1, 7))
    for x in range(7):
        for z in range(7):
            d = math.hypot(x - 3, z - 3)
            if d <= 3.3:
                dish.set(x, 0, z, DISH if d > 0.8 else CASE_DK)
    dish.offset = (0, 6, 6)
    mast = Model("mast", (1, 1, 3))
    for z in range(3):
        mast.set(0, 0, z, CASE_DK)
    mast.offset = (0, 6, 3)
    vf.models = [body, dish, mast]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "stormcaller.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["body", "dish", "mast"]
    print("verified stormcaller.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/stormcaller.vox", 0.3,
                rh=("0.05 -0.05 0.25", "0.0 90.0 0.0"),
                poses={"fp_action": ("0.25 -0.4 -0.45", "-25.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
