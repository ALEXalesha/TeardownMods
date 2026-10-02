"""RC transmitter model: red case, two gimbal sticks, screen, long antenna with a tip light."""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
RED, RED_DK, BLACK, STICK, SCREEN, TIP = 129, 130, 131, 153, 194, 193


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    for k, c in {RED: (200, 36, 30), RED_DK: (140, 24, 20), BLACK: (30, 30, 34), STICK: (190, 192, 198),
                 SCREEN: (90, 220, 255), TIP: (255, 60, 40)}.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.5", "_metal": "0.3"}
    vf.materials[SCREEN] = {"_type": "_emit", "_emit": "0.7", "_flux": "3"}
    vf.materials[TIP] = {"_type": "_emit", "_emit": "1", "_flux": "3"}
    case = Model("case", (13, 7, 4))
    for x in range(13):
        for y in range(7):
            for z in range(4):
                if (x in (0, 12)) and (y in (0, 6)):
                    continue
                idx = RED if z < 3 else RED_DK
                if x in (0, 12) and z < 2:
                    idx = BLACK  # grips
                case.set(x, y, z, idx)
    for x in range(5, 8):
        for y in range(1, 3):
            case.set(x, y, 3, SCREEN)
    for x in (3, 9):
        case.set(x, 4, 3, BLACK)
    sticks = Model("sticks", (7, 1, 3))
    for x in (0, 6):
        for z in range(3):
            sticks.set(x, 0, z, STICK)
    sticks.offset = (0, 1, 3)
    ant = Model("antenna", (1, 1, 10))
    for z in range(9):
        ant.set(0, 0, z, STICK)
    ant.set(0, 0, 9, TIP)
    ant.offset = (5, 2, 6)
    vf.models = [case, sticks, ant]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "transmitter.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["case", "sticks", "antenna"]
    print("verified transmitter.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/transmitter.vox", 0.3,
                rh=("0.18 -0.05 0.0", "0.0 90.0 0.0"), lh=("-0.18 -0.05 0.0", "0.0 -90.0 0.0"),
                poses={"fp_action": ("0.0 -0.33 -0.45", "-35.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
