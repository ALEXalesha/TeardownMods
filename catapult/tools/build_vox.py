"""Catapult models (all spawned at scale 3, i.e. 0.3 m voxels).

The machine is assembled in Lua from symmetric parts placed with pos/rot in one prefab
string, so the result does not depend on how the game orients a model internally:
  frame.vox   static wooden A-frame trebuchet stand, symmetric front/back (the throw axis)
  axle.vox    the axle bar (part of the static frame), 26 x 4 x 4 voxels
  hub.vox     the arm's hub around the axle: same model size as the axle, so whatever origin
              convention the game uses, hub and axle shift identically and the hinge joint
              placed in the hub always lies inside the axle
  beam.vox    the throwing arm, 14.4 m, symmetric along its length
  bucket.vox  open cup at the long end of the arm
  weight.vox  hollow counterweight box at the short end
Ammo: boulder.vox (rock), barrel.vox, crate.vox, hulk.vox (a car body when the game's own
car prefab cannot be spawned). Tool: mallet.vox.
Materials follow the game's palette ranges: wood 57-72, rock 41-56, weak metal 121-136,
heavy metal 137-152, plastic 153-168, glass 1-8.
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
WOOD = [57, 58, 59, 60, 61]
WOOD_DK = 62
IRON = 137          # heavy metal: axle, bands
IRON_LT = 138
ROCK = [41, 42, 43, 44, 45]
STEEL = 121         # weak metal
RED = 122
YELLOW = 123
GLASS = 2
TYRE = 153
CHROME = 124


def palette(vf):
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    cols = {57: (150, 104, 62), 58: (138, 94, 56), 59: (160, 114, 70), 60: (128, 86, 50), 61: (145, 100, 58), WOOD_DK: (96, 64, 38),
            IRON: (62, 62, 66), IRON_LT: (96, 96, 102), 41: (120, 116, 110), 42: (104, 100, 96), 43: (136, 132, 124), 44: (96, 92, 88), 45: (148, 142, 134),
            STEEL: (70, 90, 120), RED: (180, 40, 30), YELLOW: (230, 190, 40), GLASS: (160, 200, 230), TYRE: (24, 24, 26), CHROME: (190, 190, 196)}
    for k, c in cols.items():
        vf.set_color(k, c)
    for k in WOOD + [WOOD_DK]:
        vf.materials[k] = {"_type": "_metal", "_rough": "0.85", "_metal": "0.0"}
    for k in (IRON, IRON_LT, STEEL, CHROME):
        vf.materials[k] = {"_type": "_metal", "_rough": "0.4", "_metal": "0.8"}


def wood(rnd, x, y, z):
    return rnd.choice(WOOD) if (x + y + z) % 7 else WOOD_DK


def line(m, a, b, idx_fn, t=2):
    """2x2 (t) beam of voxels from a to b (MagicaVoxel coordinates)."""
    n = int(max(abs(b[i] - a[i]) for i in range(3))) + 1
    for k in range(n):
        f = k / max(n - 1, 1)
        p = [a[i] + (b[i] - a[i]) * f for i in range(3)]
        for dx in range(t):
            for dy in range(t):
                for dz in range(t):
                    x, y, z = int(round(p[0])) + dx, int(round(p[1])) + dy, int(round(p[2])) + dz
                    if 0 <= x < m.size[0] and 0 <= y < m.size[1] and 0 <= z < m.size[2]:
                        m.set(x, y, z, idx_fn(x, y, z))


FX, FY, FZ = 26, 38, 32      # frame model size (x wide, y along the throw axis, z up)


def frame() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(1)
    m = Model("frame", (FX, FY, FZ))
    w = lambda x, y, z: wood(rnd, x, y, z)
    for x0 in (2, FX - 4):
        line(m, (x0, 0, 0), (x0, FY - 2, 0), w)                   # base rail
        line(m, (x0, 2, 2), (x0, 17, FZ - 2), w)                 # leg front
        line(m, (x0, FY - 4, 2), (x0, 19, FZ - 2), w)            # leg back
        line(m, (x0, 9, 15), (x0, FY - 11, 15), w)               # brace
        for y in range(16, 22):                                   # bearing block under the axle
            for z in range(FZ - 4, FZ):
                for x in range(x0, x0 + 2):
                    m.set(x, y, z, IRON if z == FZ - 1 else w(x, y, z))
    for y0 in (0, FY - 2, 18):
        line(m, (2, y0, 0), (FX - 3, y0, 0), w)                  # cross beams on the ground
    vf.models = [m]
    return vf


def bar(name, filled) -> VoxFile:
    """26 x 4 x 4 model: the axle (filled) or the hub (only a small block in the middle)."""
    vf = VoxFile()
    palette(vf)
    m = Model(name, (26, 4, 4))
    for x in range(26):
        for y in range(4):
            for z in range(4):
                if filled:
                    m.set(x, y, z, IRON if 1 <= y <= 2 and 1 <= z <= 2 else IRON_LT)
                elif 11 <= x <= 14:
                    m.set(x, y, z, IRON_LT if x in (11, 14) else IRON)
    vf.models = [m]
    return vf


def beam() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(3)
    m = Model("beam", (2, 48, 2))
    for y in range(48):
        for x in range(2):
            for z in range(2):
                m.set(x, y, z, IRON if y % 8 == 0 else wood(rnd, x, y, z))
    vf.models = [m]
    return vf


def bucket() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(4)
    m = Model("bucket", (9, 9, 5))
    for x in range(9):
        for y in range(9):
            for z in range(5):
                wall = x in (0, 8) or y in (0, 8) or z == 0
                if wall:
                    m.set(x, y, z, IRON if (z == 4 and (x in (0, 8) or y in (0, 8))) else wood(rnd, x, y, z))
    vf.models = [m]
    return vf


def weight() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(5)
    m = Model("weight", (8, 8, 8))
    for x in range(8):
        for y in range(8):
            for z in range(8):
                shell = x in (0, 7) or y in (0, 7) or z in (0, 7)
                if shell:
                    edge = sum(v in (0, 7) for v in (x, y, z)) >= 2
                    m.set(x, y, z, IRON if edge else wood(rnd, x, y, z))
    vf.models = [m]
    return vf


def boulder() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(6)
    m = Model("boulder", (6, 6, 6))
    for x in range(6):
        for y in range(6):
            for z in range(6):
                d = math.sqrt((x - 2.5) ** 2 + (y - 2.5) ** 2 + (z - 2.5) ** 2)
                if d <= 2.9 + rnd.uniform(-0.3, 0.2):
                    m.set(x, y, z, rnd.choice(ROCK))
    vf.models = [m]
    return vf


def barrel() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    m = Model("barrel", (4, 4, 5))
    for x in range(4):
        for y in range(4):
            for z in range(5):
                if (x - 1.5) ** 2 + (y - 1.5) ** 2 <= 4.6:
                    m.set(x, y, z, YELLOW if z == 2 else RED)
    vf.models = [m]
    return vf


def crate() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(7)
    m = Model("crate", (3, 3, 3))
    for x in range(3):
        for y in range(3):
            for z in range(3):
                m.set(x, y, z, WOOD_DK if (x != 1 and y != 1) or (x != 1 and z != 1) or (y != 1 and z != 1) else wood(rnd, x, y, z))
    vf.models = [m]
    return vf


def hulk() -> VoxFile:
    """A small car body (fallback ammo when the game's own car prefab cannot be spawned)."""
    vf = VoxFile()
    palette(vf)
    m = Model("hulk", (6, 14, 5))
    for x in range(6):
        for y in range(14):
            for z in range(5):
                body = z <= 2 and 1 <= y <= 12
                cabin = z >= 3 and 4 <= y <= 9 and 1 <= x <= 4
                wheel = z <= 1 and x in (0, 5) and (y in (2, 3) or y in (10, 11))
                if wheel:
                    m.set(x, y, z, TYRE)
                elif cabin:
                    m.set(x, y, z, GLASS if (x in (1, 4) or y in (4, 9)) and z == 3 else STEEL)
                elif body and 1 <= x <= 4:
                    m.set(x, y, z, CHROME if y in (1, 12) and z == 1 else STEEL)
    vf.models = [m]
    return vf


def mallet() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    rnd = random.Random(8)
    m = Model("mallet", (5, 5, 16))
    for z in range(16):
        if z < 11:
            for x in (2,):
                m.set(x, 2, z, wood(rnd, x, 2, z))
        else:
            for x in range(5):
                for y in range(5):
                    if (x - 2) ** 2 + (y - 2) ** 2 <= 5:
                        m.set(x, y, z, IRON if z in (11, 15) else wood(rnd, x, y, z))
    vf.models = [m]
    return vf


MODELS = {"frame.vox": frame, "axle.vox": lambda: bar("axle", True), "hub.vox": lambda: bar("hub", False), "beam.vox": beam,
          "bucket.vox": bucket, "weight.vox": weight, "boulder.vox": boulder, "barrel.vox": barrel, "crate.vox": crate,
          "hulk.vox": hulk, "mallet.vox": mallet}

if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "vox"), exist_ok=True)
    for name, fn in MODELS.items():
        path = os.path.join(MOD, "vox", name)
        write_vox(path, fn())
        vf = read_vox(path)
        used = {i for mm in vf.models for i in mm.voxels.values()}
        bad = [i for i in used if material_of(i) in (None, "reserved")]
        assert not bad, (name, bad)
        print("verified", name, [(mm.name, mm.size, len(mm.voxels)) for mm in vf.models], sorted({material_of(i) for i in used}))
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/mallet.vox", 0.3,
                rh=("0.0 -0.05 0.0", "0.0 0.0 0.0"),
                poses={"fp_action": ("0.3 -0.3 -0.45", "-30.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
