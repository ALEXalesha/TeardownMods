"""Tsunami sprites (water wall, foam crest, flood sheet), preview.jpg and UI textures."""
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


def wave_png(path, w=256, h=512, seed=2):
    """The water wall, bottom to top: dark green-blue, lighter turquoise, streaks of foam
    near the top; nearly opaque so it reads as a solid mass of water."""
    rng = np.random.default_rng(seed)
    y = np.linspace(1, 0, h)[:, None] * np.ones((1, w))          # 0 bottom .. 1 top
    x = np.linspace(0, 1, w)[None, :] * np.ones((h, 1))
    streak = 0.5 + 0.5 * np.sin(x * 40 + np.sin(y * 9) * 2 + rng.uniform(0, 6))
    r = 10 + 60 * y + 40 * y ** 4 * streak
    g = 50 + 120 * y + 50 * y ** 4 * streak
    b = 60 + 110 * y + 40 * y ** 4 * streak
    foam = np.clip((y - 0.82) / 0.18, 0, 1) ** 1.5 * (0.6 + 0.4 * streak)
    r = r * (1 - foam) + 245 * foam
    g = g * (1 - foam) + 250 * foam
    b = b * (1 - foam) + 252 * foam
    a = np.clip(0.93 - 0.1 * (1 - y) ** 3, 0, 1) * 255
    arr = np.stack([r, g, b, a], -1).clip(0, 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def foam_png(path, w=256, h=96, seed=3):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    n = rng.random((h // 4 + 1, w // 4 + 1))
    n = np.kron(n, np.ones((4, 4)))[:h, :w]
    n = np.asarray(Image.fromarray((n * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2)), np.float32) / 255
    v = 1 - np.abs(yy / (h - 1) - 0.5) * 2
    a = np.clip(v * 1.6 - 0.2, 0, 1) * (0.55 + 0.45 * n)
    arr = np.zeros((h, w, 4), np.uint8)
    arr[..., :3] = (235 + 20 * n[..., None]).clip(0, 255).astype(np.uint8)
    arr[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def flood_png(path, size=256, seed=4):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    rip = 0.5 + 0.25 * np.sin(xx * 31 + np.sin(yy * 13) * 2) + 0.25 * np.sin(yy * 23 + np.sin(xx * 11) * 3)
    edge = np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy)) * 8
    a = np.clip(edge, 0, 1) * (0.55 + 0.15 * rip)
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., 0] = (60 + 60 * rip).astype(np.uint8)
    arr[..., 1] = (85 + 60 * rip).astype(np.uint8)
    arr[..., 2] = (80 + 50 * rip).astype(np.uint8)
    arr[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def build_preview():
    rnd = random.Random(6)
    img = art.vertical_gradient((W, H), (40, 60, 90, 255), (200, 160, 130, 255))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.78)
    # the wave: a tall curling wall from the left, foam on top
    wave = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wave)
    pts = [(0, horizon)]
    for i in range(0, 61):
        x = i / 60 * W * 0.92
        top = horizon - 360 * (1 - (i / 60) ** 2.2) - 30 * math.sin(i * 0.4)
        pts.append((x, top))
    pts += [(W * 0.92, horizon), (0, horizon)]
    for k in range(40):
        shade = k / 39
        poly = [(x, y + (horizon - y) * shade) for x, y in pts[1:-2]]
        col = (int(20 + 50 * (1 - shade)), int(70 + 110 * (1 - shade)), int(80 + 100 * (1 - shade)), 255)
        wd.polygon([(0, horizon)] + poly + [(W * 0.92, horizon)], fill=col)
    for i in range(0, 61):
        x = i / 60 * W * 0.92
        top = horizon - 360 * (1 - (i / 60) ** 2.2) - 30 * math.sin(i * 0.4)
        for j in range(6):
            r = rnd.uniform(6, 20)
            fx, fy = x + rnd.uniform(-12, 12), top + rnd.uniform(-14, 18)
            wd.ellipse((fx - r, fy - r, fx + r, fy + r), fill=(240, 248, 250, rnd.randint(170, 240)))
    img.alpha_composite(wave.filter(ImageFilter.GaussianBlur(1.2)))
    # spray
    spray = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(spray)
    for i in range(400):
        x = rnd.uniform(0, W * 0.95)
        top = horizon - 360 * (1 - (min(x / (W * 0.92), 1)) ** 2.2)
        y = top - rnd.uniform(0, 70)
        r = rnd.uniform(1, 4)
        sd.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, rnd.randint(60, 160)))
    img.alpha_composite(spray.filter(ImageFilter.GaussianBlur(1.5)))
    # a little town in front of it
    d = ImageDraw.Draw(img)
    x = 380
    while x < W:
        bw, bh = rnd.randint(40, 90), rnd.randint(40, 130)
        d.rectangle((x, horizon - bh, x + bw, horizon), fill=(46, 40, 44, 255))
        for wy in range(horizon - bh + 8, horizon - 6, 16):
            for wx in range(x + 5, x + bw - 7, 12):
                if rnd.random() < 0.35:
                    d.rectangle((wx, wy, wx + 5, wy + 7), fill=(255, 210, 120, 255))
        x += bw + rnd.randint(3, 14)
    d.rectangle((0, horizon, W, H), fill=(52, 58, 54, 255))
    for i in range(10):
        spr = art.render_debris(rnd.choice(["plank", "crate", "brick"]), rnd, px=rnd.uniform(2, 3.5))
        img.alpha_composite(spr, (rnd.randint(200, 700), rnd.randint(horizon - 120, horizon - 10)))
    conch = render_vox(read_vox(os.path.join(MOD, "vox", "conch.vox")), px=12, yaw=-35, pitch=20, glow=0.0)
    img.alpha_composite(conch, (W - conch.width - 50, H - conch.height - 30))
    img = art.text_with_glow(img, (W - 40, 96), "TSUNAMI", art.font(78), glow=(30, 140, 220), anchor="rs")
    img = art.text_with_glow(img, (W - 44, 142), "Цунами", art.font(36, bold=False), fill=(220, 240, 255), glow=(20, 90, 160), glow_r=6, anchor="rs")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    wave_png(os.path.join(MOD, "ui", "wave.png"))
    foam_png(os.path.join(MOD, "ui", "foam.png"))
    flood_png(os.path.join(MOD, "ui", "flood.png"))
    build_preview()
