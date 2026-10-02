"""Trampoline pad (frame + springs + separate membrane shape) and the hand-held pad placer."""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
FRAME, FRAME_DK, SPRING, MEMBRANE, STRIPE, LIGHT = 137, 138, 124, 139, 129, 140
N = 30          # pad side in voxels (3 m at scale 1)


def palette(vf):
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    for k, c in {FRAME: (40, 110, 220), FRAME_DK: (26, 70, 150), SPRING: (190, 194, 200), MEMBRANE: (24, 24, 28),
                 STRIPE: (250, 200, 40), LIGHT: (120, 220, 255)}.items():
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.5", "_metal": "0.3"}
    vf.materials[LIGHT] = {"_type": "_emit", "_emit": "0.8", "_flux": "3"}


def pad() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    frame = Model("frame", (N, N, 3))
    for x in range(N):
        for y in range(N):
            edge = x < 2 or y < 2 or x >= N - 2 or y >= N - 2
            if edge:
                for z in range(3):
                    idx = FRAME if z < 2 else FRAME_DK
                    if z == 2 and (x + y) % 6 < 3:
                        idx = STRIPE
                    frame.set(x, y, z, idx)
            # springs between frame and membrane
            elif (x in (2, N - 3) or y in (2, N - 3)) and (x + y) % 3 == 0:
                frame.set(x, y, 1, SPRING)
    for x, y in ((1, 1), (N - 2, 1), (1, N - 2), (N - 2, N - 2)):
        frame.set(x, y, 2, LIGHT)
    membrane = Model("membrane", (N - 6, N - 6, 1))
    for x in range(N - 6):
        for y in range(N - 6):
            membrane.set(x, y, 0, MEMBRANE)
    membrane.offset = (0, 0, 0)
    vf.models = [frame, membrane]
    return vf


def placer() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    body = Model("body", (6, 9, 4))
    for x in range(6):
        for y in range(9):
            for z in range(4):
                idx = FRAME if z < 3 else FRAME_DK
                if y < 3 and z < 2:
                    idx = MEMBRANE
                body.set(x, y, z, idx)
    mini = Model("mini", (5, 5, 1))
    for x in range(5):
        for y in range(5):
            mini.set(x, y, 0, STRIPE if x in (0, 4) or y in (0, 4) else MEMBRANE)
    mini.offset = (0, 2, 3)
    vf.models = [body, mini]
    return vf


if __name__ == "__main__":
    for name, fn, names in (("pad.vox", pad, ["frame", "membrane"]), ("placer.vox", placer, ["body", "mini"])):
        path = os.path.join(MOD, "vox", name)
        write_vox(path, fn())
        vf = read_vox(path)
        assert [m.name for m in vf.models] == names
        print("verified", name, [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/placer.vox", 0.3,
                rh=("0.0 -0.1 0.15", "0.0 90.0 0.0"),
                poses={"fp_action": ("0.28 -0.35 -0.45", "-20.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
