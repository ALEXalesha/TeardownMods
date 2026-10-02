"""Seismic detonator model: casing, red button, green screen, antenna with a red tip."""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
YELLOW, DARK, GREY, STRIPE = 129, 130, 131, 132
ANT = 155
BUTTON, SCREEN, TIP = 193, 194, 195


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    vf.set_color(YELLOW, (232, 182, 38))
    vf.set_color(DARK, (38, 38, 42))
    vf.set_color(GREY, (112, 112, 118))
    vf.set_color(STRIPE, (20, 20, 22))
    vf.set_color(ANT, (168, 168, 178))
    vf.set_color(BUTTON, (255, 44, 30))
    vf.set_color(SCREEN, (70, 255, 130))
    vf.set_color(TIP, (255, 60, 40))
    for i in (YELLOW, DARK, GREY, STRIPE, ANT):
        vf.materials[i] = {"_type": "_metal", "_rough": "0.5", "_metal": "0.3"}
    vf.materials[BUTTON] = {"_type": "_emit", "_emit": "0.6", "_flux": "2"}
    vf.materials[SCREEN] = {"_type": "_emit", "_emit": "0.8", "_flux": "3"}
    vf.materials[TIP] = {"_type": "_emit", "_emit": "1.0", "_flux": "3"}

    body = Model("body", (7, 5, 10))
    sx, sy, sz = body.size
    for x in range(sx):
        for y in range(sy):
            for z in range(sz):
                edge = (x in (0, sx - 1)) + (y in (0, sy - 1)) + (z in (0, sz - 1))
                if edge >= 2 and (x in (0, sx - 1)) and (z in (0, sz - 1)):
                    continue  # rounded vertical corners
                idx = YELLOW
                if z <= 1:
                    idx = DARK  # rubber foot / grip
                elif (x + z) % 4 == 0 and z <= 4:
                    idx = STRIPE  # hazard stripes on the lower half
                body.set(x, y, z, idx)
    # screen on the face towards the player (vox y = 0 -> Teardown +z)
    for x in range(1, 6):
        for z in range(5, 8):
            body.set(x, 0, z, SCREEN if (x, z) != (1, 7) else DARK)
    # dial under the screen
    body.set(3, 0, 3, GREY)
    body.set(2, 0, 3, DARK)
    # red button on top, ringed by grey
    top = Model("button", (3, 3, 2))
    for x in range(3):
        for y in range(3):
            top.set(x, y, 0, GREY)
    top.set(1, 1, 1, BUTTON)
    top.set(1, 1, 0, BUTTON)
    top.offset = (0, 0, 6)
    # antenna at the back corner
    ant = Model("antenna", (1, 1, 7))
    for z in range(6):
        ant.set(0, 0, z, ANT)
    ant.set(0, 0, 6, TIP)
    ant.offset = (2, 1, 8)
    vf.models = [body, top, ant]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "detonator.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["body", "button", "antenna"]
    assert all(len(m.voxels) > 0 for m in vf.models)
    assert vf.materials[TIP]["_type"] == "_emit"
    print("verified detonator.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/detonator.vox", 0.25,
                rh=("0.0 -0.05 0.0", "0.0 90.0 0.0"),
                poses={"fp_action": ("0.28 -0.32 -0.42", "5.0 -10.0 0.0")})
    print("wrote prefab/tool.xml")
