"""Cutter saw model: motor body, handle, guard and a separate disc shape that spins."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
ORANGE, ORANGE_DK, BLACK, STEEL, STEEL_DK, VENT = 129, 130, 131, 153, 154, 132


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    vf.set_color(ORANGE, (236, 112, 20))
    vf.set_color(ORANGE_DK, (170, 74, 10))
    vf.set_color(BLACK, (30, 30, 34))
    vf.set_color(VENT, (60, 60, 66))
    vf.set_color(STEEL, (196, 200, 210))
    vf.set_color(STEEL_DK, (120, 124, 134))
    for i in (ORANGE, ORANGE_DK, BLACK, VENT):
        vf.materials[i] = {"_type": "_metal", "_rough": "0.6", "_metal": "0.2"}
    for i in (STEEL, STEEL_DK):
        vf.materials[i] = {"_type": "_metal", "_rough": "0.15", "_metal": "1"}
    # motor body along y (forward)
    body = Model("body", (5, 10, 5))
    for x in range(5):
        for y in range(10):
            for z in range(5):
                if math.hypot(x - 2, z - 2) <= 2.4:
                    idx = ORANGE
                    if y < 3:
                        idx = BLACK if (x + z) % 2 == 0 else VENT
                    elif y == 3 or y == 8:
                        idx = ORANGE_DK
                    body.set(x, y, z, idx)
    # side handle sticking out to the left
    handle = Model("handle", (4, 2, 2))
    for x in range(4):
        for y in range(2):
            for z in range(2):
                handle.set(x, y, z, BLACK)
    handle.offset = (-4, 2, 0)
    # guard: half ring above the disc
    guard = Model("guard", (1, 13, 7))
    for y in range(13):
        for z in range(7):
            r = math.hypot(y - 6, z - 0)
            if 5.2 <= r <= 6.6 and z >= 0:
                guard.set(0, y, z, ORANGE_DK)
    guard.offset = (-2, 9, 0)
    # disc (separate shape, spins around x)
    disc = Model("disc", (1, 11, 11))
    for y in range(11):
        for z in range(11):
            r = math.hypot(y - 5, z - 5)
            if r <= 5.3:
                idx = STEEL if r > 1.2 else STEEL_DK
                if r > 4.4 and (int(math.degrees(math.atan2(z - 5, y - 5)) // 30) % 2 == 0):
                    idx = STEEL_DK  # teeth
                disc.set(0, y, z, idx)
    disc.offset = (-3, 9, -1)
    vf.models = [body, handle, guard, disc]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "cutter.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["body", "handle", "guard", "disc"]
    assert vf.models[3].size == (1, 11, 11)
    print("verified cutter.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/cutter.vox", 0.3,
                rh=("0.05 -0.05 0.25", "0.0 90.0 0.0"), lh=("-0.35 0.0 -0.05", "90.0 40.0 0.0"),
                poses={"fp_action": ("0.25 -0.35 -0.5", "0.0 0.0 0.0")},
                locations={"blade": ("-0.1 -0.05 -0.75", "0 0 0")})
    print("wrote prefab/tool.xml")
