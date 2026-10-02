"""Drone models: quadcopter (body, arms, 4 rotors, camera), bomb, hand-held controller."""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
from voxio import Model, VoxFile, write_vox, read_vox  # noqa: E402
from prefab import tool_prefab  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
SHELL, SHELL_DK, ARM, MOTOR, ROTOR, LENS, RED, GREEN, WHITE, BATT = 137, 138, 139, 140, 141, 193, 194, 195, 196, 142
BOMB, BOMB_DK, FIN = 153, 154, 155
CTRL, CTRL_DK, STICK, SCREEN = 129, 130, 131, 197


def palette(vf: VoxFile) -> None:
    for i in range(1, 256):
        g = 40 + (i * 37) % 180
        vf.set_color(i, (g, g, g))
    cols = {SHELL: (226, 228, 232), SHELL_DK: (150, 154, 162), ARM: (44, 46, 52), MOTOR: (90, 94, 104),
            ROTOR: (30, 30, 34), LENS: (60, 140, 255), RED: (255, 40, 30), GREEN: (40, 255, 80), WHITE: (255, 250, 230),
            BATT: (230, 160, 20), BOMB: (70, 82, 60), BOMB_DK: (46, 54, 40), FIN: (120, 124, 130),
            CTRL: (60, 62, 70), CTRL_DK: (36, 38, 44), STICK: (180, 182, 190), SCREEN: (90, 200, 255)}
    for k, v in cols.items():
        vf.set_color(k, v)
        vf.materials[k] = {"_type": "_metal", "_rough": "0.4", "_metal": "0.4"}
    for k in (LENS, RED, GREEN, WHITE, SCREEN):
        vf.materials[k] = {"_type": "_emit", "_emit": "0.9", "_flux": "3"}


def drone() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    body = Model("body", (21, 21, 5))
    c = 10
    for x in range(21):
        for y in range(21):
            for z in range(5):
                dx, dy = x - c, y - c
                # central pod
                if abs(dx) <= 3 and abs(dy) <= 4 and 1 <= z <= 3:
                    idx = SHELL
                    if z == 1:
                        idx = SHELL_DK
                    if abs(dy) <= 1 and z == 3 and abs(dx) <= 2:
                        idx = BATT
                    body.set(x, y, z, idx)
                # diagonal arms
                elif z == 2 and (abs(abs(dx) - abs(dy)) <= 0) and 3 <= max(abs(dx), abs(dy)) <= 8:
                    body.set(x, y, z, ARM)
                # motor pods at the arm ends
                elif max(abs(abs(dx) - 8), abs(abs(dy) - 8)) <= 1 and 1 <= z <= 3:
                    body.set(x, y, z, MOTOR)
    # camera under the front, LEDs on the front arms
    for x in (9, 10, 11):
        body.set(x, 15, 1, SHELL_DK)
    body.set(10, 15, 0, LENS)
    body.set(10, 16, 1, LENS)
    body.set(2, 18, 3, RED)
    body.set(18, 18, 3, GREEN)
    body.set(10, 6, 0, WHITE)
    models = [body]
    for k, (sx, sy) in enumerate(((-8, 8), (8, 8), (-8, -8), (8, -8))):
        r = Model(f"rotor{k + 1}", (7, 7, 1))
        for x in range(7):
            for y in range(7):
                # two-blade propeller, rotated 45 degrees per rotor for variety
                ang = math.atan2(y - 3, x - 3) + k * math.pi / 4
                d = math.hypot(x - 3, y - 3)
                blade = abs(math.sin(ang)) < 0.35 and d <= 3.4
                if blade or d < 0.8:
                    r.set(x, y, 0, ROTOR)
        r.offset = (sx, sy, 2)
        models.append(r)
    vf.models = models
    return vf


def bomb() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    m = Model("bomb", (3, 3, 6))
    for z in range(6):
        for x in range(3):
            for y in range(3):
                if z == 5:
                    if (x == 1) != (y == 1) or (x == 1 and y == 1):
                        m.set(x, y, z, FIN)
                elif z == 0:
                    if x == 1 and y == 1:
                        m.set(x, y, z, BOMB_DK)
                else:
                    m.set(x, y, z, BOMB if z != 2 else BOMB_DK)
    vf.models = [m]
    return vf


def controller() -> VoxFile:
    vf = VoxFile()
    palette(vf)
    m = Model("controller", (11, 6, 3))
    for x in range(11):
        for y in range(6):
            for z in range(3):
                if (x in (0, 10)) and (y in (0, 5)):
                    continue
                m.set(x, y, z, CTRL if z < 2 else CTRL_DK)
    for x in range(3, 8):
        for y in range(1, 4):
            m.set(x, y, 2, SCREEN)
    sticks = Model("sticks", (9, 1, 2))
    for x in (0, 8):
        sticks.set(x, 0, 0, STICK)
        sticks.set(x, 0, 1, STICK)
    sticks.offset = (0, 0, 2)
    ant = Model("antenna", (1, 1, 6))
    for z in range(6):
        ant.set(0, 0, z, STICK)
    ant.offset = (5, 2, 4)
    vf.models = [m, sticks, ant]
    return vf


if __name__ == "__main__":
    for name, fn, names in (("drone.vox", drone, ["body", "rotor1", "rotor2", "rotor3", "rotor4"]),
                            ("bomb.vox", bomb, ["bomb"]), ("controller.vox", controller, ["controller", "sticks", "antenna"])):
        path = os.path.join(MOD, "vox", name)
        write_vox(path, fn())
        vf = read_vox(path)
        assert [m.name for m in vf.models] == names, [m.name for m in vf.models]
        assert all(len(m.voxels) > 0 for m in vf.models)
        print("verified", name, [(m.name, m.size, len(m.voxels)) for m in vf.models])
    tool_prefab(os.path.join(MOD, "prefab", "tool.xml"), "MOD/vox/controller.vox", 0.3,
                rh=("0.15 -0.05 0.0", "0.0 90.0 0.0"), lh=("-0.15 -0.05 0.0", "0.0 -90.0 0.0"),
                poses={"fp_action": ("0.0 -0.35 -0.45", "-30.0 0.0 0.0")})
    print("wrote prefab/tool.xml")
