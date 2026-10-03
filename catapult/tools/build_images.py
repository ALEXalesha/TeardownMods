"""Catapult thumb.jpg (16:9 in-game preview: the trebuchet and a boulder in flight over a town)
and UI textures. The square Steam preview.jpg is made from it by _shared/tdlib/workshop.py."""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import art  # noqa: E402
from render import render_models, render_vox  # noqa: E402
from voxio import read_vox, Model  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
W, H = 1024, 576


def assembled():
    """The machine as one model (frame + axle + arm in a throwing pose) for the picture."""
    vf = read_vox(os.path.join(MOD, "vox", "frame.vox"))
    frame = vf.models[0]
    m = Model("catapult", (frame.size[0], 70, 52))
    oy = (70 - frame.size[1]) // 2
    for (x, y, z), i in frame.voxels.items():
        m.set(x, y + oy, z, i)
    cx, cy, cz = frame.size[0] // 2, 70 // 2, frame.size[2]
    for x in range(1, frame.size[0] - 1):
        for dy in range(2):
            for dz in range(2):
                m.set(x, cy + dy - 1, cz + dz - 1, 137)
    # arm swung up and back (just released), bucket at the top, counterweight down front
    ang = math.radians(60)
    for t in range(-11, 34):
        y = int(round(cy + math.cos(ang) * t * -1))
        z = int(round(cz + math.sin(ang) * t))
        for dx in (-1, 0):
            if 0 <= y < 70 and 0 <= z < 52:
                m.set(cx + dx, y, z, 59 if t % 8 else 137)
    ty, tz = int(round(cy - math.cos(ang) * 33)), int(round(cz + math.sin(ang) * 33))
    for x in range(cx - 4, cx + 4):
        for y in range(ty - 4, ty + 4):
            for z in range(tz - 1, tz + 3):
                if 0 <= y < 70 and 0 <= z < 52 and (x in (cx - 4, cx + 3) or y in (ty - 4, ty + 3) or z == tz - 1):
                    m.set(x, y, z, 58)
    wy, wz = int(round(cy + math.cos(ang) * 11)), int(round(cz - math.sin(ang) * 11))
    for x in range(cx - 4, cx + 4):
        for y in range(wy - 4, wy + 4):
            for z in range(wz - 4, wz + 4):
                if 0 <= y < 70 and 0 <= z < 52:
                    m.set(x, y, z, 62 if (x + y + z) % 5 else 137)
    return vf, m


def build_preview():
    rnd = random.Random(12)
    img = art.vertical_gradient((W, H), (70, 110, 170, 255), (235, 200, 150, 255))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.8)
    # distant town getting hit
    x = 560
    while x < W:
        bw, bh = rnd.randint(40, 80), rnd.randint(40, 120)
        d.rectangle((x, horizon - bh, x + bw, horizon), fill=(110, 100, 105, 255))
        x += bw + rnd.randint(4, 14)
    d.rectangle((0, horizon, W, H), fill=(92, 120, 70, 255))
    # dust cloud of the impact
    dust = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dust)
    for i in range(40):
        r = rnd.uniform(14, 46)
        cx, cy = 820 + rnd.uniform(-70, 70), horizon - 60 + rnd.uniform(-50, 30)
        g = rnd.randint(150, 190)
        dd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(g, g - 10, g - 20, 150))
    img.alpha_composite(dust.filter(ImageFilter.GaussianBlur(4)))
    for i in range(14):
        spr = art.render_debris(rnd.choice(["brick", "plank", "concrete"]), rnd, px=rnd.uniform(2, 4))
        img.alpha_composite(spr, (int(820 + rnd.uniform(-120, 100)), int(horizon - 200 + rnd.uniform(-60, 80))))
    # the machine
    vf, m = assembled()
    cat = render_models(vf, [m], yaw=-55, pitch=18, px=6, ss=1, glow=0)
    cx0, cy0 = 30, horizon - cat.height + 40
    img.alpha_composite(cat, (cx0, cy0))
    # flight arc from the arm tip, and the boulder on it
    pts = []
    x0, y0 = cx0 + int(cat.width * 0.42), cy0 + int(cat.height * 0.06)
    for k in range(40):
        t = k / 39
        pts.append((x0 + t * (800 - x0), y0 - 170 * 4 * t * (1 - t) + (horizon - 80 - y0) * t))
    for k in range(0, len(pts) - 1, 2):
        d.line((pts[k], pts[k + 1]), fill=(255, 220, 120, 230), width=4)
    boulder = render_vox(read_vox(os.path.join(MOD, "vox", "boulder.vox")), px=9, yaw=20, pitch=20, glow=0)
    bx, by = pts[24]
    img.alpha_composite(boulder, (int(bx - boulder.width / 2), int(by - boulder.height / 2)))
    img = art.text_with_glow(img, (W - 40, 96), "CATAPULT", art.font(78), glow=(200, 120, 40), anchor="rs")
    img = art.text_with_glow(img, (W - 44, 142), "Катапульта", art.font(36, bold=False), fill=(255, 235, 210), glow=(150, 80, 20), glow_r=6, anchor="rs")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_preview()
