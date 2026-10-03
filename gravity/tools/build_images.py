"""Gravity Change preview.jpg, HUD icon and UI textures."""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import art  # noqa: E402
from render import render_vox, render_models  # noqa: E402
from voxio import read_vox  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
W, H = 1024, 576


def planet(img, cx, cy, r, base, spots, rnd):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=base + (255,))
    for i in range(spots):
        a = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(0, r * 0.7)
        sr = rnd.uniform(r * 0.08, r * 0.25)
        x, y = cx + math.cos(a) * rr, cy + math.sin(a) * rr
        c = tuple(max(0, v - 30) for v in base)
        d.ellipse((x - sr, y - sr, x + sr, y + sr), fill=c + (255,))
    shade = art.glow_spot(img.size, (cx + r * 0.5, cy + r * 0.4), r * 1.6, (0, 0, 0), 0.5)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    layer = Image.alpha_composite(layer, Image.composite(shade, Image.new("RGBA", img.size, (0, 0, 0, 0)), mask))
    return Image.alpha_composite(img, layer)


def build_preview():
    rnd = random.Random(2)
    img = art.vertical_gradient((W, H), (8, 10, 24, 255), (30, 30, 50, 255))
    d = ImageDraw.Draw(img)
    for i in range(300):
        x, y = rnd.randint(0, W), rnd.randint(0, H)
        c = rnd.randint(120, 255)
        d.point((x, y), fill=(c, c, c, 255))
    img = planet(img, 140, 470, 120, (60, 110, 200), 8, rnd)
    img = planet(img, 860, 150, 70, (190, 190, 186), 10, rnd)
    img = planet(img, 950, 430, 50, (200, 100, 60), 6, rnd)
    floor = int(H * 0.8)
    # floating debris, a car upside down, with arrows of different gravities
    for i in range(22):
        spr = art.render_debris(rnd.choice(["crate", "barrel", "plank", "brick", "concrete"]), rnd, px=rnd.uniform(4, 8))
        spr = spr.rotate(rnd.uniform(0, 360), expand=True, resample=Image.BICUBIC)
        img.alpha_composite(spr, (rnd.randint(260, 760), rnd.randint(170, 470)))
    vf, m = art.car_model((240, 200, 40))
    car = render_models(vf, [m], yaw=40, pitch=25, px=9, ss=2, glow=0.3).rotate(160, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(car, (470, 230))
    core = render_vox(read_vox(os.path.join(MOD, "vox", "core.vox")), px=9, yaw=30, pitch=25, glow=1.0)
    img.alpha_composite(core, (W - core.width - 60, H - core.height - 20))
    img = art.text_with_glow(img, (44, 96), "GRAVITY CHANGE", art.font(66), glow=(80, 180, 255), anchor="ls")
    img = art.text_with_glow(img, (48, 140), "Смена гравитации", art.font(34, bold=False), fill=(220, 240, 255), glow=(50, 120, 220), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_preview()
