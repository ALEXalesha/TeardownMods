"""Vehicle Remote preview.jpg and UI textures."""
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
    rnd = random.Random(12)
    img = art.vertical_gradient((W, H), (120, 170, 220, 255), (200, 210, 200, 255))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.55)
    d.rectangle((0, horizon, W, H), fill=(110, 112, 108, 255))
    d.polygon([(0, H), (W, H), (W * 0.62, horizon), (W * 0.38, horizon)], fill=(70, 70, 74, 255))
    for k in range(9):
        t = k / 9
        y0 = horizon + (H - horizon) * t ** 1.6
        y1 = horizon + (H - horizon) * (t + 0.05) ** 1.6
        x0 = W / 2 - 3 - 10 * t
        d.polygon([(x0, y0), (x0 + 6 + 20 * t, y0), (x0 + 6 + 22 * t, y1), (x0, y1)], fill=(230, 220, 120, 255))
    # crates being smashed by the car
    for i in range(10):
        spr = art.render_debris(rnd.choice(["crate", "barrel", "plank"]), rnd, px=rnd.uniform(4, 7))
        img.alpha_composite(spr, (rnd.randint(560, 860), rnd.randint(horizon - 40, horizon + 120)))
    vf, m = art.car_model((220, 40, 36))
    car = render_models(vf, [m], yaw=210, pitch=26, px=13, ss=2, glow=0.5)
    img.alpha_composite(car, (430, 300))
    # signal waves from the transmitter to the car
    wv = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wv)
    for k in range(6):
        r = 30 + k * 34
        wd.arc((230 - r, 330 - r, 230 + r, 330 + r), -40, 20, fill=(255, 80, 60, 220 - k * 30), width=5)
    img = art.add(img, wv.filter(ImageFilter.GaussianBlur(3)), 1.2)
    img = Image.alpha_composite(img, wv)
    tx = render_vox(read_vox(os.path.join(MOD, "vox", "transmitter.vox")), px=15, yaw=200, pitch=40, glow=0.7)
    img.alpha_composite(tx, (60, H - tx.height - 30))
    img = art.text_with_glow(img, (44, 96), "VEHICLE REMOTE", art.font(68), glow=(255, 70, 50), anchor="ls")
    img = art.text_with_glow(img, (48, 140), "Радиоуправление", art.font(34, bold=False), fill=(255, 235, 230), glow=(200, 50, 40), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "thumb.jpg"))
    print("thumb.jpg (16:9, in-game preview)", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_preview()
