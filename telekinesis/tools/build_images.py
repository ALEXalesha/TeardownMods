"""Telekinesis preview.jpg and UI textures."""
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


def outline(img, color, width=3):
    a = img.split()[3].point(lambda v: 255 if v > 10 else 0)
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1))
    ring = Image.new("RGBA", img.size, color + (0,))
    ring.putalpha(grown)
    out = Image.alpha_composite(ring.filter(ImageFilter.GaussianBlur(3)), ring)
    return Image.alpha_composite(out, img)


def build_preview():
    rnd = random.Random(6)
    img = art.vertical_gradient((W, H), (26, 20, 40, 255), (60, 50, 70, 255))
    d = ImageDraw.Draw(img)
    floor = int(H * 0.74)
    d.rectangle((0, floor, W, H), fill=(44, 40, 50, 255))
    cx, cy = 560, 270
    # swirl ring
    ring = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.ellipse((cx - 230, cy - 90, cx + 230, cy + 90), outline=(170, 100, 255, 160), width=4)
    for i in range(300):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.gauss(1, 0.06)
        x, y = cx + math.cos(a) * 230 * r, cy + math.sin(a) * 90 * r
        rd.ellipse((x - 2, y - 2, x + 2, y + 2), fill=(220, 180, 255, 200))
    img = art.add(img, ring.filter(ImageFilter.GaussianBlur(6)), 1.4)
    img = art.add(img, ring, 1.0)
    # objects on the ring with glow outlines
    kinds = ["crate", "barrel", "brick", "plank", "concrete", "crate", "glass", "barrel"]
    for i, k in enumerate(kinds):
        a = i / len(kinds) * 2 * math.pi + 0.3
        x, y = cx + math.cos(a) * 230, cy + math.sin(a) * 90
        spr = art.render_debris(k, random.Random(30 + i), px=rnd.uniform(7, 10))
        pad = Image.new("RGBA", (spr.width + 16, spr.height + 16), (0, 0, 0, 0))
        pad.alpha_composite(spr, (8, 8))
        spr = outline(pad, (180, 110, 255), 3)
        img.alpha_composite(spr, (int(x - spr.width / 2), int(y - spr.height / 2)))
    # wisps from the gauntlet
    gl = render_vox(read_vox(os.path.join(MOD, "vox", "gauntlet.vox")), px=18, yaw=200, pitch=50, glow=1.2)
    gx, gy = 110, H - gl.height - 20
    ws = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(ws)
    for i in range(6):
        a = i / 6 * 2 * math.pi
        tx, ty = cx + math.cos(a) * 230, cy + math.sin(a) * 90
        pts = [(gx + gl.width * 0.6 + (tx - gx - gl.width * 0.6) * t + math.sin(t * 9 + i) * 15, gy + 40 + (ty - gy - 40) * t) for t in [k / 20 for k in range(21)]]
        wd.line(pts, fill=(190, 120, 255, 160), width=3)
    img = art.add(img, ws.filter(ImageFilter.GaussianBlur(4)), 1.3)
    img.alpha_composite(gl, (gx, gy))
    img = art.text_with_glow(img, (W - 40, 100), "TELEKINESIS", art.font(74), glow=(160, 90, 255), anchor="rs")
    img = art.text_with_glow(img, (W - 44, 146), "Телекинез", art.font(36, bold=False), fill=(235, 220, 255), glow=(120, 60, 220), glow_r=6, anchor="rs")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_preview()
