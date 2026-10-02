"""Generate the Singularity Grenade voxel model (MagicaVoxel .vox).

One file, three shapes (Teardown keeps them as separate shapes of one body):
  core  - glowing violet sphere with gunmetal caps, a cyan status light
  ringx - brass gimbal ring standing in the YZ plane
  ringz - brass gimbal ring lying flat (XY plane in MagicaVoxel = horizontal)

Palette indices follow the ranges the built-in tool models use
(121-168 metal, 185-200 metal / emissive) so Teardown treats the grenade as
metal: the singularity's own MakeHole calls (soft materials only) cannot
destroy it.
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402

OUT = os.path.join(HERE, "..", "mod", "vox")

# palette slots
BRASS, BRASS_DK, BRASS_HI = 153, 154, 155
GUN, GUN_DK, GUN_HI = 158, 159, 160
BUTTON = 185
LIGHT_CYAN, CORE_OUT, CORE_IN = 193, 194, 195


def make_palette(vf: VoxFile) -> None:
    # neutral grey ramp everywhere so unused slots look sane in MagicaVoxel
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    vf.set_color(BRASS, (196, 146, 64))
    vf.set_color(BRASS_DK, (138, 96, 40))
    vf.set_color(BRASS_HI, (236, 196, 110))
    vf.set_color(GUN, (64, 67, 78))
    vf.set_color(GUN_DK, (36, 38, 46))
    vf.set_color(GUN_HI, (104, 108, 124))
    vf.set_color(BUTTON, (214, 170, 52))
    vf.set_color(LIGHT_CYAN, (90, 232, 255))
    vf.set_color(CORE_OUT, (148, 64, 255))
    vf.set_color(CORE_IN, (236, 182, 255))
    for i in (BRASS, BRASS_DK, BRASS_HI):
        vf.materials[i] = {"_type": "_metal", "_rough": "0.25", "_metal": "0.9"}
    for i in (GUN, GUN_DK, GUN_HI, BUTTON):
        vf.materials[i] = {"_type": "_metal", "_rough": "0.45", "_metal": "0.7"}
    # Teardown: emissive needs Emission AND Power (flux) >= 2
    vf.materials[LIGHT_CYAN] = {"_type": "_emit", "_emit": "0.9", "_flux": "3"}
    vf.materials[CORE_OUT] = {"_type": "_emit", "_emit": "0.7", "_flux": "3"}
    vf.materials[CORE_IN] = {"_type": "_emit", "_emit": "1.0", "_flux": "4"}


def build_core() -> Model:
    n = 9
    c = (n - 1) / 2
    m = Model("core", (n, n, n))
    for x in range(n):
        for y in range(n):
            for z in range(n):
                dx, dy, dz = x - c, y - c, z - c
                r = math.sqrt(dx * dx + dy * dy + dz * dz)
                if r <= 2.6:
                    m.set(x, y, z, CORE_IN if r < 1.6 else CORE_OUT)
                elif r <= 4.3:
                    # caps on top and bottom, an open violet window band around the equator
                    if abs(dz) >= 1.6:
                        # alternating panel lines on the caps
                        idx = GUN if (int(math.atan2(dy, dx) / (math.pi / 4) + 8) % 2 == 0) else GUN_DK
                        if abs(dz) >= 3.6:
                            idx = GUN_HI
                        m.set(x, y, z, idx)
                    elif r <= 3.3:
                        m.set(x, y, z, CORE_OUT)
    # status light + button on top
    top = n - 1
    m.set(int(c), int(c), top, LIGHT_CYAN)
    m.set(int(c) + 1, int(c), top, BUTTON)
    m.set(int(c) - 1, int(c), top, BUTTON)
    # keep only the outer surface for performance? voxels inside are cheap at this size
    return m


def build_ring(name: str, axis: str, radius: float = 5.6, width: float = 0.8) -> Model:
    n = 13
    c = (n - 1) / 2
    if axis == "x":
        size = (2, n, n)
    else:
        size = (n, n, 2)
    m = Model(name, size)
    for a in range(n):
        for b in range(n):
            da, db = a - c, b - c
            r = math.sqrt(da * da + db * db)
            if abs(r - radius) <= width:
                ang = math.atan2(db, da)
                # brass with darker notches every 45 degrees
                notch = abs(((ang / (math.pi / 4)) % 1.0) - 0.5) < 0.12
                for t in range(2):
                    idx = BRASS_DK if notch else (BRASS_HI if t == 0 else BRASS)
                    if axis == "x":
                        m.set(t, a, b, idx)
                    else:
                        m.set(a, b, t, idx)
    return m


def build() -> VoxFile:
    vf = VoxFile()
    make_palette(vf)
    core = build_core()
    ringx = build_ring("ringx", "x")
    ringz = build_ring("ringz", "z", radius=4.9)
    # centre every model on the same point
    core.offset = (0, 0, 0)
    ringx.offset = (0, 0, 0)
    ringz.offset = (0, 0, 0)
    vf.models = [core, ringx, ringz]
    return vf


def verify(path: str) -> None:
    vf = read_vox(path)
    names = [m.name for m in vf.models]
    assert names == ["core", "ringx", "ringz"], names
    sizes = [m.size for m in vf.models]
    assert sizes == [(9, 9, 9), (2, 13, 13), (13, 13, 2)], sizes
    for m in vf.models:
        assert len(m.voxels) > 20, (m.name, len(m.voxels))
    assert vf.color_of(CORE_OUT)[:3] == (148, 64, 255)
    assert vf.materials[CORE_IN]["_type"] == "_emit" and float(vf.materials[CORE_IN]["_flux"]) >= 2
    used = {i for m in vf.models for i in m.voxels.values()}
    assert used <= {BRASS, BRASS_DK, BRASS_HI, GUN, GUN_DK, GUN_HI, BUTTON, LIGHT_CYAN, CORE_OUT, CORE_IN}, used
    print(f"verified {os.path.basename(path)}: shapes={names} sizes={sizes} voxels={[len(m.voxels) for m in vf.models]}")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "grenade.vox")
    write_vox(path, build())
    verify(path)
