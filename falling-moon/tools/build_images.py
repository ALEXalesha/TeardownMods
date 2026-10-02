"""Falling Moon sprites (moon, glow), preview.jpg and UI textures."""
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


def moon_png(path, size=512, seed=1):
    rnd = random.Random(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (xx / (size - 1) - 0.5) * 2
    ny = (yy / (size - 1) - 0.5) * 2
    r = np.sqrt(nx ** 2 + ny ** 2)
    inside = r <= 1
    nz = np.sqrt(np.clip(1 - r ** 2, 0, 1))
    shade = np.clip(0.25 + 0.75 * (nx * -0.4 + ny * -0.3 + nz * 0.86), 0, 1)
    tone = np.full_like(r, 0.75)
    # maria and craters
    for i in range(40):
        cx, cy = rnd.uniform(-0.9, 0.9), rnd.uniform(-0.9, 0.9)
        cr = rnd.uniform(0.03, 0.22)
        d = np.sqrt((nx - cx) ** 2 + (ny - cy) ** 2) / cr
        if i < 6:
            tone -= 0.18 * np.clip(1 - d, 0, 1) ** 0.5
        else:
            tone -= 0.12 * ((d < 1) & (d > 0.75)) * 0 + 0.1 * np.clip(1 - d, 0, 1)
            tone += 0.12 * ((d > 0.85) & (d < 1.05))
    noise = np.random.default_rng(seed).normal(0, 0.03, (size, size))
    v = np.clip(tone * shade + noise, 0, 1)
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., 0] = (v * 235).astype(np.uint8)
    arr[..., 1] = (v * 230).astype(np.uint8)
    arr[..., 2] = (v * 222).astype(np.uint8)
    edge = np.clip((1 - r) * size / 3, 0, 1)
    arr[..., 3] = (inside * edge * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def glow_png(path, size=256):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.sqrt(((xx / (size - 1) - 0.5) * 2) ** 2 + ((yy / (size - 1) - 0.5) * 2) ** 2)
    a = np.clip(1 - r, 0, 1) ** 2.2
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., :3] = 255
    arr[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def build_preview():
    rnd = random.Random(5)
    img = art.vertical_gradient((W, H), (70, 14, 10, 255), (210, 90, 40, 255))
    moon = Image.open(os.path.join(MOD, "ui", "moon.png")).resize((560, 560), Image.LANCZOS)
    img = art.add(img, art.glow_spot((W, H), (640, 170), 420, (255, 130, 70), 1.6), 1.0)
    tint = Image.new("RGBA", moon.size, (255, 200, 170, 0))
    m2 = Image.blend(moon, Image.composite(Image.new("RGBA", moon.size, (255, 170, 130, 255)), moon, moon.split()[3]), 0.3)
    m2.putalpha(moon.split()[3])
    img.alpha_composite(m2, (360, -140))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.74)
    # city silhouette and lifting debris
    x = 0
    while x < W:
        bw, bh = rnd.randint(50, 120), rnd.randint(60, 200)
        d.rectangle((x, horizon - bh, x + bw, horizon), fill=(30, 12, 12, 255))
        for wy in range(horizon - bh + 10, horizon - 6, 18):
            for wx in range(x + 6, x + bw - 8, 14):
                if rnd.random() < 0.3:
                    d.rectangle((wx, wy, wx + 6, wy + 8), fill=(255, 190, 90, 255))
        x += bw + rnd.randint(2, 12)
    d.rectangle((0, horizon, W, H), fill=(40, 18, 14, 255))
    for i in range(24):
        spr = art.render_debris(rnd.choice(["plank", "brick", "crate", "concrete"]), rnd, px=rnd.uniform(2, 4))
        img.alpha_composite(spr, (rnd.randint(0, W - 30), rnd.randint(300, horizon - 10)))
    # countdown
    f1 = art.font(22)
    f2 = art.font(52)
    d = ImageDraw.Draw(img)
    d.text((W // 2, 470 - 330), "", font=f1)
    img = art.text_with_glow(img, (W - 150, H - 120), "IMPACT IN", f1, fill=(255, 140, 120), glow=(120, 20, 10), glow_r=4)
    img = art.text_with_glow(img, (W - 150, H - 74), "00:07", f2, glow=(200, 40, 20), glow_r=6)
    tel = render_vox(read_vox(os.path.join(MOD, "vox", "telescope.vox")), px=14, yaw=-40, pitch=20, glow=0.4)
    img.alpha_composite(tel, (40, H - tel.height - 20))
    img = art.text_with_glow(img, (44, 96), "FALLING MOON", art.font(72), glow=(255, 90, 40), anchor="ls")
    img = art.text_with_glow(img, (48, 142), "Падающая луна", art.font(34, bold=False), fill=(255, 230, 210), glow=(200, 60, 20), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "preview.jpg"))
    print("preview.jpg", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    moon_png(os.path.join(MOD, "ui", "moon.png"))
    glow_png(os.path.join(MOD, "ui", "glow.png"))
    build_preview()
