"""Build preview.jpg, the tool icon and UI textures for the Singularity Grenade."""
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


def singularity_layer(cx: float, cy: float, R: float, rnd: random.Random) -> Image.Image:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # soft violet halo
    layer = art.add(layer, art.glow_spot((W, H), (cx, cy), R * 3.2, (120, 40, 230), 1.8), 1.5)
    layer = art.add(layer, art.glow_spot((W, H), (cx, cy), R * 1.1, (220, 150, 255), 2.0), 1.0)
    d = ImageDraw.Draw(layer)
    # spiral streaks falling in
    for i in range(420):
        a0 = rnd.uniform(0, 2 * math.pi)
        r0 = R * rnd.uniform(1.2, 5.0)
        pts = []
        for k in range(10):
            t = k / 9
            r = r0 * (1 - 0.55 * t)
            a = a0 + 1.4 * t
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.42))
        c = rnd.choice([(190, 120, 255), (240, 200, 255), (140, 70, 255)])
        d.line(pts, fill=c + (rnd.randint(60, 170),), width=rnd.choice((1, 1, 2)))
    layer = layer.filter(ImageFilter.GaussianBlur(0.8))
    # accretion ring (ellipse of bright dots)
    ring = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dr = ImageDraw.Draw(ring)
    for i in range(900):
        a = rnd.uniform(0, 2 * math.pi)
        r = R * rnd.gauss(1.0, 0.08)
        x, y = cx + math.cos(a) * r * 1.7, cy + math.sin(a) * r * 0.5
        s = rnd.uniform(0.6, 2.2)
        dr.ellipse((x - s, y - s, x + s, y + s), fill=(255, 225, 255, rnd.randint(120, 255)))
    ring_glow = ring.filter(ImageFilter.GaussianBlur(5))
    layer = art.add(layer, ring_glow, 1.4)
    layer = art.add(layer, ring, 1.0)
    return layer


def build_preview() -> None:
    rnd = random.Random(7)
    img = art.vertical_gradient((W, H), (14, 8, 30, 255), (40, 24, 48, 255))
    # ground: dark street with perspective lines
    ground = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(ground)
    horizon = int(H * 0.62)
    gd.rectangle((0, horizon, W, H), fill=(26, 22, 30, 255))
    for i in range(-12, 13):
        gd.line((W / 2 + i * 22, horizon, W / 2 + i * 160, H), fill=(44, 38, 52, 255), width=1)
    for k in range(8):
        y = horizon + (H - horizon) * (k / 8) ** 1.7
        gd.line((0, y, W, y), fill=(40, 34, 48, 255), width=1)
    img = Image.alpha_composite(img, ground)
    # silhouettes of buildings
    sil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sil)
    x = 0
    while x < W:
        bw = rnd.randint(60, 140)
        bh = rnd.randint(90, 230)
        sd.rectangle((x, horizon - bh, x + bw, horizon), fill=(20, 14, 32, 255))
        for wy in range(horizon - bh + 12, horizon - 10, 22):
            for wx in range(x + 8, x + bw - 10, 18):
                if rnd.random() < 0.25:
                    sd.rectangle((wx, wy, wx + 7, wy + 10), fill=(110, 80, 150, 255))
        x += bw + rnd.randint(4, 20)
    img = Image.alpha_composite(img, sil)

    cx, cy, R = 640, 300, 54
    img = art.add(img, singularity_layer(cx, cy, R, rnd), 1.0)

    # debris spiralling in
    kinds = ["plank", "plank", "crate", "brick", "glass", "barrel", "concrete", "plank", "glass"]
    for i in range(26):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(R * 1.6, R * 7.5)
        x = cx + math.cos(a) * r * 1.3
        y = cy + math.sin(a) * r * 0.55
        size = 2.0 + 4.0 * (r / (R * 7.5))
        sprite = art.render_debris(rnd.choice(kinds), rnd, px=size)
        tx, ty = -math.sin(a), math.cos(a) * 0.45
        inward = ((cx - x) / max(r, 1), (cy - y) / max(r, 1))
        vx = (tx * 0.8 + inward[0] * 0.6) * 18
        vy = (ty * 0.8 + inward[1] * 0.6) * 18
        sprite = art.motion_blur(sprite, vx, vy, 6)
        img.alpha_composite(sprite, (int(x - sprite.width / 2), int(y - sprite.height / 2)))

    # dark core on top of everything near the centre
    core = art.glow_spot((W, H), (cx, cy), R * 0.55, (0, 0, 0), 0.6)
    img = Image.alpha_composite(img, core)
    img = art.add(img, art.glow_spot((W, H), (cx, cy), R * 0.75, (255, 220, 255), 6.0), 0.9)

    # the grenade itself, big, bottom-left, with its own glow
    vf = read_vox(os.path.join(MOD, "vox", "grenade.vox"))
    g = render_vox(vf, px=15, yaw=32, pitch=24, glow=1.2)
    img.alpha_composite(g, (70, H - g.height - 40))

    f1 = art.font(64)
    f2 = art.font(32, bold=False)
    img = art.text_with_glow(img, (44, 96), "SINGULARITY GRENADE", f1, anchor="ls")
    img = art.text_with_glow(img, (48, 142), "Гравитационная граната", f2, fill=(230, 210, 255), glow=(120, 60, 220), glow_r=6, anchor="ls")
    out = os.path.join(MOD, "thumb.jpg")
    n = art.save_jpg(img, out)
    print(f"thumb.jpg {W}x{H} {n // 1024} KB")


def build_icon() -> None:
    vf = read_vox(os.path.join(MOD, "vox", "grenade.vox"))
    g = render_vox(vf, px=12, yaw=32, pitch=24, glow=1.0)
    size = 128
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = min((size - 8) / g.width, (size - 8) / g.height)
    g2 = g.resize((int(g.width * s), int(g.height * s)), Image.LANCZOS)
    icon.alpha_composite(g2, ((size - g2.width) // 2, (size - g2.height) // 2))
    icon.save(os.path.join(MOD, "ui", "icon.png"))
    print("ui/icon.png", icon.size)


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    art.vignette_png(os.path.join(MOD, "ui", "vignette.png"))
    build_icon()
    build_preview()
