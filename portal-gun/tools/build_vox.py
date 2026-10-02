"""Portal gun model: white shell, dark grip, glowing core (blue and orange halves), three prongs."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
WHITE, WHITE_DK, BLACK, GREY, BLUE, ORANGE, CORE = 137, 138, 139, 140, 193, 194, 195


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    for k, c in {WHITE: (236, 238, 240), WHITE_DK: (190, 194, 200), BLACK: (32, 32, 36), GREY: (110, 114, 122),
                 BLUE: (40, 140, 255), ORANGE: (255, 140, 30), CORE: (220, 240, 255)}.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.3", "_metal": "0.3"}
    for k in (BLUE, ORANGE, CORE):
        vf.materials[k] = {"_type": "_emit", "_emit": "0.9", "_flux": "3"}
    body = Model("body", (7, 13, 7))
    for x in range(7):
        for y in range(13):
            for z in range(7):
                r = math.hypot(x - 3, z - 3)
                rad = 3.3 if y < 9 else 3.3 - (y - 8) * 0.55
                if r <= rad:
                    idx = WHITE if y % 4 else WHITE_DK
                    if y < 3:
                        idx = BLACK
                    body.set(x, y, z, idx)
    # glowing core window on top, blue half and orange half
    for y in range(4, 9):
        body.set(3, y, 6, BLUE if y < 7 else ORANGE)
        body.set(2, y, 6, CORE if y == 6 else (BLUE if y < 7 else ORANGE))
        body.set(4, y, 6, CORE if y == 6 else (BLUE if y < 7 else ORANGE))
    grip = Model("grip", (3, 3, 5))
    for x in range(3):
        for y in range(3):
            for z in range(5):
                grip.set(x, y, z, BLACK)
    grip.offset = (0, -3, -5)
    prongs = Model("prongs", (7, 3, 7))
    for (px, pz) in ((0, 3), (6, 3), (3, 6)):
        for y in range(3):
            prongs.set(px, y, pz, GREY if y < 2 else CORE)
    prongs.offset = (0, 7, 0)
    vf.models = [body, grip, prongs]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "portalgun.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["body", "grip", "prongs"]
    print("verified portalgun.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/portalgun.vox", 0.3,
                rh=("0.0 -0.2 0.1", "0.0 90.0 0.0"), lh=("-0.05 0.0 -0.35", "90.0 40.0 0.0"),
                poses={"fp_action": ("0.25 -0.32 -0.4", "0.0 0.0 0.0")},
                locations={"muzzle": ("0.0 0.0 -0.6", "0 0 0")})
    print("wrote prefab/tool.xml")
