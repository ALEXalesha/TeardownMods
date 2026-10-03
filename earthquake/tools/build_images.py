"""Earthquake preview.jpg, icon and UI textures."""
from __future__ import annotations

import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import art  # noqa: E402
from render import render_vox  # noqa: E402
from voxio import read_vox  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
W, H = 1024, 576


def building(rnd, w, h, color, tilt):
    im = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle((20, 20, 20 + w, 20 + h), fill=color + (255,))
    for wy in range(32, h, 26):
        for wx in range(30, w, 22):
            lit = rnd.random() < 0.35
            d.rectangle((wx, wy, wx + 10, wy + 14), fill=(255, 210, 120, 255) if lit else (40, 36, 44, 255))
    # cracks
    for k in range(rnd.randint(2, 4)):
        x = rnd.randint(24, 16 + w)
        y = rnd.randint(30, 20 + h // 2)
        pts = [(x, y)]
        for s in range(8):
            x += rnd.randint(-10, 10)
            y += rnd.randint(8, 22)
            pts.append((x, y))
        d.line(pts, fill=(15, 12, 14, 255), width=2)
    return im.rotate(tilt, resample=Image.BICUBIC, expand=True)


def build_preview():
    rnd = random.Random(11)
    img = art.vertical_gradient((W, H), (60, 40, 30, 255), (150, 110, 70, 255))
    horizon = int(H * 0.72)
    # buildings, tilting
    x = -20
    while x < W:
        bw = rnd.randint(70, 150)
        bh = rnd.randint(150, 330)
        col = rnd.choice([(92, 84, 80), (110, 96, 86), (80, 76, 84), (120, 108, 96)])
        b = building(rnd, bw, bh, col, rnd.uniform(-7, 7))
        img.alpha_composite(b, (x - 20, horizon - b.height + 30))
        x += bw + rnd.randint(-10, 15)
    d = ImageDraw.Draw(img)
    d.rectangle((0, horizon, W, H), fill=(58, 48, 40, 255))
    # ground cracks
    for k in range(5):
        x0 = rnd.randint(0, W)
        pts = [(x0, horizon)]
        y = horizon
        while y < H:
            x0 += rnd.randint(-30, 30)
            y += rnd.randint(10, 30)
            pts.append((x0, y))
        d.line(pts, fill=(20, 16, 14, 255), width=rnd.randint(2, 5))
    # dust clouds
    dust = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dust)
    for i in range(70):
        cx = rnd.randint(-50, W + 50)
        cy = horizon + rnd.randint(-120, 40)
        r = rnd.randint(30, 90)
        dd.ellipse((cx - r, cy - r * 0.7, cx + r, cy + r * 0.7), fill=(190, 160, 120, rnd.randint(40, 90)))
    dust = dust.filter(ImageFilter.GaussianBlur(14))
    img = Image.alpha_composite(img, dust)
    # falling debris
    for i in range(30):
        spr = art.render_debris(rnd.choice(["brick", "concrete", "glass", "plank"]), rnd, px=rnd.uniform(2, 4.5))
        spr = art.motion_blur(spr, 0, 14, 5)
        img.alpha_composite(spr, (rnd.randint(0, W - 40), rnd.randint(140, horizon - 20)))
    # seismograph strip
    strip = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    sd.rectangle((0, H - 92, W, H - 18), fill=(250, 245, 230, 225))
    for gx in range(0, W, 32):
        sd.line((gx, H - 92, gx, H - 18), fill=(220, 200, 190, 255))
    pts = []
    for xx in range(0, W, 3):
        t = xx / W
        env = math.sin(min(1, max(0, (t - 0.15) / 0.7)) * math.pi) ** 0.7
        y = H - 55 + math.sin(xx * 0.31) * 30 * env * (0.6 + 0.4 * math.sin(xx * 0.05)) + rnd.uniform(-5, 5) * env
        pts.append((xx, y))
    sd.line(pts, fill=(200, 30, 30, 255), width=2)
    img = Image.alpha_composite(img, strip)
    # detonator
    vf = read_vox(os.path.join(MOD, "vox", "detonator.vox"))
    det = render_vox(vf, px=17, yaw=205, pitch=22, glow=0.8)
    img.alpha_composite(det, (W - det.width - 70, H - det.height - 110))
    f1 = art.font(78)
    f2 = art.font(34, bold=False)
    img = art.text_with_glow(img, (44, 100), "EARTHQUAKE", f1, glow=(255, 140, 40), anchor="ls")
    img = art.text_with_glow(img, (48, 146), "Землетрясение", f2, fill=(255, 235, 200), glow=(200, 90, 20), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


def build_icon():
    vf = read_vox(os.path.join(MOD, "vox", "detonator.vox"))
    g = render_vox(vf, px=12, yaw=205, pitch=22, glow=0.6)
    size = 128
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = min((size - 8) / g.width, (size - 8) / g.height)
    g2 = g.resize((int(g.width * s), int(g.height * s)), Image.LANCZOS)
    icon.alpha_composite(g2, ((size - g2.width) // 2, (size - g2.height) // 2))
    icon.save(os.path.join(MOD, "ui", "icon.png"))


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_icon()
    build_preview()
