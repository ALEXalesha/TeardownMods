"""Gizmo gun model: grip, body, emitter ring with red/green/blue axis prongs."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
BODY, BODY_DK, GRIP, TRIM = 137, 138, 139, 140
RED, GREEN, BLUE, CORE = 193, 194, 195, 196


def build() -> VoxFile:
    vf = VoxFile()
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    vf.set_color(BODY, (210, 214, 222))
    vf.set_color(BODY_DK, (120, 126, 138))
    vf.set_color(GRIP, (40, 42, 48))
    vf.set_color(TRIM, (250, 160, 30))
    vf.set_color(RED, (255, 60, 50))
    vf.set_color(GREEN, (70, 255, 90))
    vf.set_color(BLUE, (60, 140, 255))
    vf.set_color(CORE, (200, 240, 255))
    for i in (BODY, BODY_DK, GRIP, TRIM):
        vf.materials[i] = {"_type": "_metal", "_rough": "0.35", "_metal": "0.6"}
    for i in (RED, GREEN, BLUE):
        vf.materials[i] = {"_type": "_emit", "_emit": "0.8", "_flux": "3"}
    vf.materials[CORE] = {"_type": "_emit", "_emit": "1.0", "_flux": "4"}

    # main body along +y (forward in Teardown)
    body = Model("body", (5, 12, 5))
    for x in range(5):
        for y in range(12):
            for z in range(5):
                dx, dz = x - 2, z - 2
                r = math.sqrt(dx * dx + dz * dz)
                if r <= 2.3:
                    idx = BODY
                    if y in (3, 7):
                        idx = TRIM
                    elif r > 1.8 and (y % 2 == 0):
                        idx = BODY_DK
                    body.set(x, y, z, idx)
    # core glow at the front
    for x in range(1, 4):
        for z in range(1, 4):
            body.set(x, 11, z, CORE)
    # grip under the back
    grip = Model("grip", (3, 3, 5))
    for x in range(3):
        for y in range(3):
            for z in range(5):
                grip.set(x, y, z, GRIP)
    grip.offset = (0, -3, -4)
    # axis prongs at the front: red +x, green +z (up), blue +y (forward)
    px = Model("prong_x", (4, 1, 1))
    for x in range(4):
        px.set(x, 0, 0, RED if x == 3 else BODY_DK)
    px.offset = (4, 5, 0)
    pz = Model("prong_z", (1, 1, 4))
    for z in range(4):
        pz.set(0, 0, z, GREEN if z == 3 else BODY_DK)
    pz.offset = (0, 5, 4)
    py = Model("prong_y", (1, 3, 1))
    for y in range(3):
        py.set(0, y, 0, BLUE if y == 2 else BODY_DK)
    py.offset = (0, 7, 0)
    vf.models = [body, grip, px, pz, py]
    return vf


if __name__ == "__main__":
    path = os.path.join(MOD, "vox", "gizmo.vox")
    write_vox(path, build())
    vf = read_vox(path)
    assert [m.name for m in vf.models] == ["body", "grip", "prong_x", "prong_z", "prong_y"]
    assert all(len(m.voxels) > 0 for m in vf.models)
    print("verified gizmo.vox", [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/gizmo.vox", 0.3,
                rh=("0.0 -0.15 0.1", "0.0 90.0 0.0"), lh=("-0.05 -0.02 -0.2", "90.0 40.0 0.0"),
                poses={"fp_action": ("0.25 -0.3 -0.35", "0.0 0.0 0.0")},
                locations={"muzzle": ("0.0 0.0 -0.45", "0 0 0")})
    print("wrote prefab/tool.xml")
