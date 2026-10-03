"""Time Slow preview.jpg, HUD icon and UI textures."""
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


def build_preview():
    rnd = random.Random(21)
    img = art.vertical_gradient((W, H), (18, 30, 56, 255), (40, 60, 90, 255))
    d = ImageDraw.Draw(img)
    floor = int(H * 0.75)
    d.rectangle((0, floor, W, H), fill=(30, 40, 56, 255))
    # a window frame in the middle, glass shattering outwards, frozen in time
    wx0, wy0, wx1, wy1 = 360, 110, 700, floor - 10
    d.rectangle((wx0 - 14, wy0 - 14, wx1 + 14, wy1 + 14), fill=(70, 52, 40, 255))
    d.rectangle((wx0, wy0, wx1, wy1), fill=(26, 40, 70, 255))
    shards = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shards)
    cx, cy = 530, 300
    for i in range(140):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(10, 380) ** 1.0
        x, y = cx + math.cos(a) * r * 1.4, cy + math.sin(a) * r * 0.8
        s = rnd.uniform(4, 16)
        pts = [(x + rnd.uniform(-s, s), y + rnd.uniform(-s, s)) for _ in range(3)]
        sd.polygon(pts, fill=(170, 220, 255, rnd.randint(120, 220)), outline=(230, 250, 255, 255))
        # time trail
        sd.line((x, y, x - math.cos(a) * r * 0.25, y - math.sin(a) * r * 0.15), fill=(120, 190, 255, 60), width=2)
    img = Image.alpha_composite(img, shards)
    # a bullet streak with rings, frozen
    st = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    std = ImageDraw.Draw(st)
    std.line((40, 330, 470, 305), fill=(255, 220, 160, 180), width=3)
    for k in range(6):
        x = 120 + k * 60
        std.ellipse((x - 6, 318 - 26 + k * -1.5, x + 6, 318 + 26 - k * 1.5), outline=(200, 230, 255, 120 - k * 10), width=2)
    std.ellipse((462, 298, 482, 312), fill=(255, 240, 200, 255))
    img = art.add(img, st.filter(ImageFilter.GaussianBlur(3)), 1.2)
    img = Image.alpha_composite(img, st)
    # debris
    for i in range(16):
        spr = art.render_debris(rnd.choice(["plank", "brick", "glass", "crate"]), rnd, px=rnd.uniform(3, 6))
        img.alpha_composite(spr, (rnd.randint(380, 900), rnd.randint(120, floor - 40)))
    # clock rings
    rings = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rings)
    for r, a in ((220, 70), (260, 50), (300, 30)):
        rd.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(140, 200, 255, a), width=2)
    for k in range(12):
        ang = k / 12 * 2 * math.pi
        rd.line((cx + math.cos(ang) * 205, cy + math.sin(ang) * 205, cx + math.cos(ang) * 235, cy + math.sin(ang) * 235), fill=(160, 210, 255, 90), width=3)
    img = art.add(img, rings, 1.0)
    # vignette
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = np.clip((np.sqrt(((xx / W - 0.5) * 2) ** 2 + ((yy / H - 0.5) * 2) ** 2) - 0.6) / 0.8, 0, 1)
    vig = np.zeros((H, W, 4), np.uint8)
    vig[..., 0], vig[..., 1], vig[..., 2] = 10, 20, 60
    vig[..., 3] = (v * 200).astype(np.uint8)
    img = Image.alpha_composite(img, Image.fromarray(vig, "RGBA"))
    hg = render_vox(read_vox(os.path.join(MOD, "vox", "hourglass.vox")), px=13, yaw=30, pitch=18, glow=0.8)
    img.alpha_composite(hg, (W - hg.width - 50, H - hg.height - 40))
    img = art.text_with_glow(img, (44, 100), "TIME SLOW", art.font(80), glow=(60, 140, 255), anchor="ls")
    img = art.text_with_glow(img, (48, 146), "Замедление времени", art.font(34, bold=False), fill=(220, 235, 255), glow=(40, 100, 220), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


def build_icon():
    g = render_vox(read_vox(os.path.join(MOD, "vox", "hourglass.vox")), px=6, yaw=30, pitch=18, glow=0.6)
    size = 56
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = min((size - 4) / g.width, (size - 4) / g.height)
    g2 = g.resize((int(g.width * s), int(g.height * s)), Image.LANCZOS)
    icon.alpha_composite(g2, ((size - g2.width) // 2, (size - g2.height) // 2))
    icon.save(os.path.join(MOD, "ui", "icon.png"))


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    art.vignette_png(os.path.join(MOD, "ui", "vignette.png"))
    build_icon()
    build_preview()
