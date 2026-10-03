"""Volcano preview.jpg (erupting cone at dusk) and UI textures."""
from __future__ import annotations

import glob
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import art  # noqa: E402
from render import render_models, render_vox  # noqa: E402
from voxio import read_vox  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
W, H = 1024, 576


def build_preview():
    rnd = random.Random(9)
    img = art.vertical_gradient((W, H), (24, 10, 18, 255), (150, 60, 30, 255))
    img = art.add(img, art.glow_spot((W, H), (620, 300), 380, (255, 110, 40), 1.8), 1.0)
    # smoke column
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(smoke)
    for i in range(70):
        y = 290 - i * 5 - rnd.uniform(0, 8)
        x = 620 + math.sin(i * 0.25) * (8 + i * 1.5) + rnd.uniform(-10, 10)
        r = 18 + i * 2.2
        g = rnd.randint(30, 55)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(g, g - 4, g - 6, 120))
    img.alpha_composite(smoke.filter(ImageFilter.GaussianBlur(6)))
    # the cone (all seven layers)
    models, vf0 = [], None
    for f in sorted(glob.glob(os.path.join(MOD, "vox", "cone_*.vox"))):
        vf = read_vox(f)
        vf0 = vf0 or vf
        models += vf.models
    cone = render_models(vf0, models, yaw=30, pitch=22, px=7, ss=1, glow=0.9)
    cx, cy = 620 - cone.width // 2, H - cone.height + 40
    img.alpha_composite(cone, (cx, cy))
    # lava bombs in arcs with glowing trails
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    top = (620, cy + 30)
    for i in range(14):
        vx = rnd.uniform(-260, 260)
        vy = rnd.uniform(-420, -300)
        tmax = rnd.uniform(0.5, 1.1)
        pts = []
        for k in range(30):
            t = tmax * k / 29
            pts.append((top[0] + vx * t, top[1] + vy * t + 0.5 * 600 * t * t))
        gd.line(pts, fill=(255, 120, 40, 140), width=3)
        x, y = pts[-1]
        gd.ellipse((x - 7, y - 7, x + 7, y + 7), fill=(255, 200, 90, 255))
    img = art.add(img, glow.filter(ImageFilter.GaussianBlur(3)), 1.0)
    img.alpha_composite(glow)
    # sparks
    d = ImageDraw.Draw(img)
    for i in range(160):
        a = rnd.uniform(-2.6, -0.5)
        r = rnd.uniform(10, 170)
        x, y = top[0] + math.cos(a) * r, top[1] + math.sin(a) * r
        d.ellipse((x - 1.5, y - 1.5, x + 1.5, y + 1.5), fill=(255, rnd.randint(150, 230), 80, 255))
    # tool and title
    core = render_vox(read_vox(os.path.join(MOD, "vox", "core.vox")), px=16, yaw=-30, pitch=25, glow=0.8)
    img.alpha_composite(core, (60, H - core.height - 40))
    img = art.text_with_glow(img, (44, 96), "VOLCANO", art.font(78), glow=(255, 90, 30), anchor="ls")
    img = art.text_with_glow(img, (48, 142), "Вулкан", art.font(36, bold=False), fill=(255, 225, 200), glow=(200, 60, 20), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_preview()
