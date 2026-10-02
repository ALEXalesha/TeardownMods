"""Trampoline Floor preview.jpg and UI textures."""
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


def build_preview():
    rnd = random.Random(15)
    img = art.vertical_gradient((W, H), (120, 190, 240, 255), (210, 230, 240, 255))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.62)
    d.rectangle((0, horizon, W, H), fill=(110, 160, 80, 255))
    pad = render_vox(read_vox(os.path.join(MOD, "vox", "pad.vox")), px=9, yaw=30, pitch=35, glow=0.4)
    img.alpha_composite(pad, (560 - pad.width // 2, horizon + 60))
    # bounce arcs with a car, crates and a barrel in the air
    arcs = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arcs)
    for k, (x0, h) in enumerate(((560, 300), (500, 220), (640, 260))):
        pts = [(x0 - 120 + 240 * t, horizon + 90 - h * 4 * t * (1 - t)) for t in [i / 30 for i in range(31)]]
        ad.line(pts, fill=(255, 255, 255, 140), width=3)
    img = Image.alpha_composite(img, arcs)
    vf, m = art.car_model((250, 120, 30))
    car = render_models(vf, [m], yaw=20, pitch=25, px=8, ss=2, glow=0.3).rotate(12, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(car, (470, 80))
    for i in range(6):
        spr = art.render_debris(rnd.choice(["crate", "barrel"]), rnd, px=rnd.uniform(6, 9))
        img.alpha_composite(spr, (rnd.randint(380, 720), rnd.randint(150, horizon)))
    # boing text burst
    burst = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(burst)
    cx, cy = 820, 300
    pts = []
    for i in range(24):
        a = i / 24 * 2 * math.pi
        r = 110 if i % 2 == 0 else 70
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.7))
    bd.polygon(pts, fill=(255, 220, 60, 255), outline=(200, 80, 20, 255))
    img = Image.alpha_composite(img, burst)
    img = art.text_with_glow(img, (cx, cy), "BOING!", art.font(46), fill=(220, 40, 30), glow=(255, 255, 255), glow_r=3, stroke=2)
    placer = render_vox(read_vox(os.path.join(MOD, "vox", "placer.vox")), px=14, yaw=200, pitch=35, glow=0.3)
    img.alpha_composite(placer, (60, H - placer.height - 30))
    img = art.text_with_glow(img, (44, 96), "TRAMPOLINE FLOOR", art.font(62), glow=(40, 120, 255), anchor="ls")
    img = art.text_with_glow(img, (48, 140), "Пол-батут", art.font(34, bold=False), fill=(230, 240, 255), glow=(30, 90, 200), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "preview.jpg"))
    print("preview.jpg", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_preview()
