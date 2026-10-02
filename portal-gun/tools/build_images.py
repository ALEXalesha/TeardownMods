"""Portal Gun sprites (swirl, rim), preview.jpg and UI textures."""
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


def swirl_png(path, size=256):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (xx / (size - 1) - 0.5) * 2
    ny = (yy / (size - 1) - 0.5) * 2
    r = np.sqrt(nx ** 2 + ny ** 2)
    a = np.arctan2(ny, nx)
    spiral = 0.5 + 0.5 * np.sin(a * 3 + r * 9)
    inside = np.clip((1 - r) / 0.15, 0, 1)
    alpha = inside * (0.35 + 0.65 * spiral * (0.3 + 0.7 * r)) * np.clip(r * 1.5, 0.25, 1)
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., :3] = 255
    arr[..., 3] = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def rim_png(path, size=256):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (xx / (size - 1) - 0.5) * 2
    ny = (yy / (size - 1) - 0.5) * 2
    r = np.sqrt(nx ** 2 + ny ** 2)
    ring = np.exp(-((r - 0.88) / 0.06) ** 2) + 0.35 * np.exp(-((r - 0.88) / 0.16) ** 2)
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., :3] = 255
    arr[..., 3] = (np.clip(ring, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def portal(img, cx, cy, w, h, col, sw, rm):
    s = sw.resize((w, h), Image.LANCZOS)
    tint = Image.new("RGBA", s.size, col + (255,))
    tint.putalpha(s.split()[3])
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    dark = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(dark).ellipse((0, 0, w, h), fill=(10, 10, 20, 230))
    layer.alpha_composite(dark, (cx - w // 2, cy - h // 2))
    img = Image.alpha_composite(img, layer)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    glow.alpha_composite(tint, (cx - w // 2, cy - h // 2))
    r = rm.resize((int(w * 1.15), int(h * 1.12)), Image.LANCZOS)
    rt = Image.new("RGBA", r.size, col + (255,))
    rt.putalpha(r.split()[3])
    glow.alpha_composite(rt, (cx - r.width // 2, cy - r.height // 2))
    img = art.add(img, glow.filter(ImageFilter.GaussianBlur(10)), 1.3)
    img = art.add(img, glow, 1.0)
    return img


def build_preview():
    sw = Image.open(os.path.join(MOD, "ui", "swirl.png"))
    rm = Image.open(os.path.join(MOD, "ui", "rim.png"))
    img = art.vertical_gradient((W, H), (180, 184, 188, 255), (140, 144, 150, 255))
    d = ImageDraw.Draw(img)
    floor = int(H * 0.72)
    # test chamber panels
    for x in range(0, W, 96):
        for y in range(0, floor, 96):
            d.rectangle((x + 3, y + 3, x + 93, y + 93), fill=(200, 204, 208, 255), outline=(150, 154, 160, 255), width=2)
    d.rectangle((0, floor, W, H), fill=(90, 94, 100, 255))
    for x in range(-200, W + 200, 80):
        d.line((x, floor, x + (x - W / 2) * 0.5, H), fill=(110, 114, 120, 255), width=2)
    img = portal(img, 280, 270, 140, 240, (60, 150, 255), sw, rm)
    img = portal(img, 760, 250, 140, 240, (255, 140, 30), sw, rm)
    # a crate flying out of the orange portal, arc from the blue one
    rnd = random.Random(4)
    crate = art.render_debris("crate", rnd, px=10)
    img.alpha_composite(crate, (640, 230))
    d = ImageDraw.Draw(img)
    for k in range(12):
        t = k / 11
        x = 300 + 40 * t
        y = 290 + 10 * t
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(80, 160, 255, 200))
    for k in range(14):
        t = k / 13
        x = 700 - 220 * t
        y = 260 + 180 * t * t
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(255, 150, 40, 200))
    gun = render_vox(read_vox(os.path.join(MOD, "vox", "portalgun.vox")), px=17, yaw=130, pitch=18, glow=0.9)
    img.alpha_composite(gun, (W - gun.width - 30, H - gun.height - 20))
    img = art.text_with_glow(img, (44, 100), "PORTAL GUN", art.font(76), glow=(80, 150, 255), anchor="ls")
    img = art.text_with_glow(img, (48, 146), "Портальная пушка", art.font(34, bold=False), fill=(255, 240, 220), glow=(255, 130, 30), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "preview.jpg"))
    print("preview.jpg", n // 1024, "KB")


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    swirl_png(os.path.join(MOD, "ui", "swirl.png"))
    rim_png(os.path.join(MOD, "ui", "rim.png"))
    build_preview()
