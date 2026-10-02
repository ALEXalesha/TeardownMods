"""Cutter preview.jpg, icon and UI textures."""
from __future__ import annotations

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "_shared", "tdlib"))
import art  # noqa: E402
from render import render_vox  # noqa: E402
from voxio import read_vox  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
W, H = 1024, 576


def build_preview():
    rnd = random.Random(8)
    img = art.vertical_gradient((W, H), (30, 26, 24, 255), (60, 50, 44, 255))
    d = ImageDraw.Draw(img)
    # a brick wall with a diagonal kerf through it
    bw, bh = 64, 28
    for row in range(0, H // bh + 1):
        off = (row % 2) * bw // 2
        for col in range(-1, W // bw + 2):
            x = col * bw + off
            y = row * bh
            c = rnd.choice([(150, 70, 52), (138, 62, 46), (160, 80, 60), (128, 58, 44)])
            d.rectangle((x + 2, y + 2, x + bw - 2, y + bh - 2), fill=c + (255,))
    # kerf: dark band from (180, 80) to (760, 470)
    x0, y0, x1, y1 = 150, 60, 700, 440
    d.line((x0, y0, x1, y1), fill=(12, 10, 10, 255), width=16)
    d.line((x0, y0, x1, y1), fill=(40, 30, 26, 255), width=4)
    # sparks fountain at the cut end
    sp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sp)
    for i in range(260):
        a = rnd.uniform(-2.6, 0.4)
        v = rnd.uniform(40, 260)
        pts = []
        for k in range(6):
            t = k / 5
            pts.append((x1 + math.cos(a) * v * t, y1 + math.sin(a) * v * t + 140 * t * t))
        sd.line(pts, fill=(255, rnd.randint(140, 230), 60, rnd.randint(150, 255)), width=rnd.choice((1, 2)))
    img = art.add(img, sp.filter(ImageFilter.GaussianBlur(4)), 1.6)
    img = art.add(img, sp, 1.0)
    img = art.add(img, art.glow_spot((W, H), (x1, y1), 120, (255, 160, 60), 2.0), 1.3)
    # dust
    dust = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dust)
    for i in range(30):
        r = rnd.randint(20, 60)
        cx, cy = x1 + rnd.randint(-80, 80), y1 + rnd.randint(-60, 60)
        dd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(170, 150, 130, 40))
    img = Image.alpha_composite(img, dust.filter(ImageFilter.GaussianBlur(12)))
    saw = render_vox(read_vox(os.path.join(MOD, "vox", "cutter.vox")), px=17, yaw=70, pitch=20, glow=0)
    img.alpha_composite(saw, (x1 - 40, y1 - saw.height // 2 + 10))
    img = art.text_with_glow(img, (44, H - 80), "CUTTER", art.font(84), glow=(255, 120, 30), anchor="ls")
    img = art.text_with_glow(img, (48, H - 34), "Резак", art.font(36, bold=False), fill=(255, 230, 200), glow=(200, 90, 20), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "preview.jpg"))
    print("preview.jpg", n // 1024, "KB")


def build_icon():
    g = render_vox(read_vox(os.path.join(MOD, "vox", "cutter.vox")), px=10, yaw=-110, pitch=20, glow=0)
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
