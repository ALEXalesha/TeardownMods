"""Tornado preview.jpg, icon and UI textures."""
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
from render import render_vox, render_models  # noqa: E402
from voxio import read_vox  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
W, H = 1024, 576


def build_preview():
    rnd = random.Random(14)
    img = art.vertical_gradient((W, H), (50, 58, 62, 255), (120, 126, 118, 255))
    d = ImageDraw.Draw(img)
    horizon = int(H * 0.78)
    d.rectangle((0, horizon, W, H), fill=(78, 90, 60, 255))
    # storm clouds
    cl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cd = ImageDraw.Draw(cl)
    for i in range(60):
        x, y = rnd.randint(-100, W + 100), rnd.randint(-40, 110)
        r = rnd.randint(60, 140)
        c = rnd.randint(30, 60)
        cd.ellipse((x - r, y - r * 0.5, x + r, y + r * 0.5), fill=(c, c + 4, c + 8, 160))
    img = Image.alpha_composite(img, cl.filter(ImageFilter.GaussianBlur(18)))
    # funnel made of many blurred ellipses
    fn = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fn)
    cx = 600
    top, bottom = 70, horizon
    for i in range(3200):
        rel = rnd.random() ** 1.3
        y = bottom - rel * (bottom - top)
        r = 10 + 170 * rel ** 1.6
        bend = math.sin(rel * math.pi) * 60
        x = cx + bend + rnd.uniform(-r, r)
        c = int(28 + 90 * rel)
        rr = 6 + 22 * rel
        fd.ellipse((x - rr, y - rr * 0.6, x + rr, y + rr * 0.6), fill=(c, c, c + 6, rnd.randint(90, 180)))
    img = Image.alpha_composite(img, fn.filter(ImageFilter.GaussianBlur(4)))
    # dust ring at the base
    du = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(du)
    for i in range(120):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(40, 220)
        x, y = cx + math.cos(a) * r, horizon + math.sin(a) * r * 0.2
        rr = rnd.randint(20, 50)
        dd.ellipse((x - rr, y - rr * 0.6, x + rr, y + rr * 0.6), fill=(130, 110, 85, 70))
    img = Image.alpha_composite(img, du.filter(ImageFilter.GaussianBlur(10)))
    # debris and a car being lifted
    for i in range(35):
        rel = rnd.random()
        y = horizon - rel * 400
        x = cx + rnd.uniform(-1, 1) * (40 + 160 * rel)
        spr = art.render_debris(rnd.choice(["plank", "plank", "crate", "brick", "glass", "barrel"]), rnd, px=rnd.uniform(2.5, 5))
        img.alpha_composite(spr, (int(x), int(y)))
    vf, m = art.car_model((60, 140, 200))
    car = render_models(vf, [m], yaw=130, pitch=40, px=6, ss=2, glow=0).rotate(25, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(car, (cx + 60, 250))
    # a farm house being torn
    vh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(vh)
    hd.rectangle((120, horizon - 120, 300, horizon), fill=(150, 60, 40, 255))
    hd.polygon([(110, horizon - 120), (210, horizon - 200), (310, horizon - 120)], fill=(70, 50, 40, 255))
    hd.rectangle((190, horizon - 70, 230, horizon), fill=(60, 40, 30, 255))
    img = Image.alpha_composite(img, vh)
    dev = render_vox(read_vox(os.path.join(MOD, "vox", "stormcaller.vox")), px=13, yaw=200, pitch=35, glow=0.6)
    img.alpha_composite(dev, (W - dev.width - 40, H - dev.height - 30))
    img = art.text_with_glow(img, (44, 110), "TORNADO", art.font(84), glow=(140, 170, 200), anchor="ls")
    img = art.text_with_glow(img, (48, 156), "Торнадо", art.font(36, bold=False), fill=(230, 240, 250), glow=(100, 130, 170), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "preview.jpg"))
    print("preview.jpg", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    build_preview()
