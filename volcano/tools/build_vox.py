"""Volcano models: the cone in 7 stacked layers (spawned one after another so it grows),
a glowing lava bomb, and the hand-held magma core.

Materials follow Teardown's palette ranges (data/built-in/palette.vox): the cone and
the bombs are rock (41-56); glowing lava is rock with an emissive MATL.
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from palette import material_of  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
ROCK = [41, 42, 43, 44, 45]           # dark basalt shades
ASH = 46
LAVA, LAVA_HOT, LAVA_CORE = 52, 53, 54  # rock with an emissive look
RB, RT, H = 36, 8, 26                   # base radius, top radius, height (voxels)
CRATER_R, CRATER_D = 7, 5
LAYERS = 7
LAYER_H = math.ceil(H / LAYERS)


def palette(vf):
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    shades = [(52, 46, 44), (64, 56, 52), (44, 40, 40), (74, 66, 60), (38, 34, 34)]
    for k, c in zip(ROCK, shades):
        vf.set_color(k, c)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.8", "_metal": "0.05"}
    vf.set_color(ASH, (96, 92, 88))
    vf.set_color(LAVA, (255, 90, 20))
    vf.set_color(LAVA_HOT, (255, 160, 40))
    vf.set_color(LAVA_CORE, (255, 230, 120))
    vf.materials[LAVA] = {"_type": "_emit", "_emit": "0.8", "_flux": "3"}
    vf.materials[LAVA_HOT] = {"_type": "_emit", "_emit": "1", "_flux": "4"}
    vf.materials[LAVA_CORE] = {"_type": "_emit", "_emit": "1", "_flux": "5"}


def cone_voxels():
    rnd = random.Random(11)
    n = 2 * RB + 1
    c = RB
    vox = {}
    streams = [rnd.uniform(0, 2 * math.pi) for _ in range(5)]
    for z in range(H):
        rel = z / (H - 1)
        r = RB + (RT - RB) * rel ** 0.85
        for x in range(n):
            for y in range(n):
                dx, dy = x - c, y - c
                d = math.hypot(dx, dy)
                rough = r + 1.5 * math.sin(math.atan2(dy, dx) * 7 + z * 0.4) * (1 - rel)
                if d > rough:
                    continue
                # crater bowl at the top
                if z >= H - CRATER_D and d < CRATER_R * (0.6 + 0.4 * (z - (H - CRATER_D)) / CRATER_D):
                    if z == H - CRATER_D:
                        vox[(x, y, z)] = LAVA_CORE
                    continue
                idx = rnd.choice(ROCK)
                if rel > 0.75 and rnd.random() < 0.2:
                    idx = ASH
                # lava streams running down the outer surface
                if d > rough - 1.6:
                    ang = math.atan2(dy, dx)
                    for s in streams:
                        wiggle = 0.12 * math.sin(z * 0.6 + s * 3)
                        if abs(((ang - s - wiggle + math.pi) % (2 * math.pi)) - math.pi) < 0.06 + 0.04 * rel and rel > 0.15:
                            idx = LAVA_HOT if rel > 0.6 else LAVA
                vox[(x, y, z)] = idx
    return vox, n


def build_layers():
    vox, n = cone_voxels()
    files = []
    for k in range(LAYERS):
        vf = VoxFile()
        palette(vf)
        m = Model(f"layer{k + 1}", (n, n, H))
        z0, z1 = k * LAYER_H, min(H, (k + 1) * LAYER_H)
        for (x, y, z), idx in vox.items():
            if z0 <= z < z1:
                m.set(x, y, z, idx)
        vf.models = [m]
        path = os.path.join(MOD, "vox", f"cone_{k + 1}.vox")
        write_vox(path, vf)
        files.append(path)
    return files


def bomb() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(5)
    m = Model("bomb", (5, 5, 5))
    for x in range(5):
        for y in range(5):
            for z in range(5):
                if (x - 2) ** 2 + (y - 2) ** 2 + (z - 2) ** 2 <= 5.5:
                    m.set(x, y, z, LAVA_HOT if rnd.random() < 0.35 else rnd.choice(ROCK))
    vf.models = [m]
    return vf


def core() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(8)
    m = Model("core", (6, 6, 6))
    for x in range(6):
        for y in range(6):
            for z in range(6):
                if abs(x - 2.5) + abs(y - 2.5) + abs(z - 2.5) <= 6:
                    crack = (x + y) % 3 == 0 and rnd.random() < 0.7
                    m.set(x, y, z, LAVA if crack else rnd.choice(ROCK))
    vf.models = [m]
    return vf


if __name__ == "__main__":
    files = build_layers()
    total = 0
    for f in files:
        vf = read_vox(f)
        used = {i for m in vf.models for i in m.voxels.values()}
        assert all(material_of(i) == "rock" for i in used), (f, used)
        total += sum(len(m.voxels) for m in vf.models)
    print(f"verified {len(files)} cone layers, {total} voxels, all rock")
    for name, fn in (("bomb.vox", bomb), ("core.vox", core)):
        path = os.path.join(MOD, "vox", name)
        write_vox(path, fn())
        vf = read_vox(path)
        assert all(material_of(i) == "rock" for m in vf.models for i in m.voxels.values())
        print("verified", name, [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/core.vox", 0.4,
                rh=("0.0 -0.1 0.0", "0.0 90.0 0.0"),
                poses={"fp_action": ("0.3 -0.35 -0.5", "0.0 20.0 0.0")})
    print("wrote prefab/tool.xml")
