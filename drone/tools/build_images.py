"""Camera Drone preview.jpg (drone-camera view with HUD), icon, UI textures."""
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
from voxio import read_vox, Model, VoxFile  # noqa: E402

MOD = os.path.join(HERE, "..", "mod")
W, H = 1024, 576


def house(rnd) -> tuple[VoxFile, Model]:
    vf = VoxFile()
    wall = rnd.choice([(210, 200, 180), (190, 170, 150), (170, 180, 190), (220, 210, 200)])
    roof = rnd.choice([(150, 60, 50), (90, 90, 100), (120, 70, 50)])
    vf.set_color(10, wall)
    vf.set_color(11, roof)
    vf.set_color(12, (60, 80, 100))
    sx, sy, sz = rnd.randint(8, 12), rnd.randint(8, 12), rnd.randint(5, 8)
    m = Model("h", (sx, sy, sz + sx // 2))
    for x in range(sx):
        for y in range(sy):
            for z in range(sz):
                if x in (0, sx - 1) or y in (0, sy - 1) or z == sz - 1:
                    win = z % 3 == 1 and (x % 3 == 1 or y % 3 == 1) and 0 < z < sz - 1
                    m.set(x, y, z, 12 if win else 10)
            for z in range(sz, sz + sx // 2):
                if abs(x - (sx - 1) / 2) <= (sz + sx // 2 - z):
                    m.set(x, y, z, 11)
    vf.models = [m]
    return vf, m


def build_preview():
    rnd = random.Random(5)
    img = Image.new("RGBA", (W, H), (88, 110, 72, 255))
    d = ImageDraw.Draw(img)
    # grass texture and a road
    for i in range(1500):
        x, y = rnd.randint(0, W), rnd.randint(0, H)
        c = rnd.randint(70, 110)
        d.point((x, y), fill=(c - 10, c + 15, c - 30, 255))
    d.polygon([(380, 0), (520, 0), (720, H), (480, H)], fill=(70, 70, 74, 255))
    for k in range(10):
        y = k * 60
        x = 450 + (y / H) * 150
        d.rectangle((x, y, x + 6, y + 30), fill=(230, 220, 120, 255))
    # houses seen from above (high pitch)
    for i in range(9):
        vf, m = house(rnd)
        spr = render_models(vf, [m], yaw=rnd.choice((0, 90, 30, 60)), pitch=62, px=7, ss=2, glow=0)
        x = rnd.choice((rnd.randint(20, 330), rnd.randint(700, W - 150)))
        y = rnd.randint(20, H - 160)
        img.alpha_composite(spr, (x, y))
    # target marker
    cx, cy = 560, 330
    mk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    md = ImageDraw.Draw(mk)
    md.ellipse((cx - 50, cy - 26, cx + 50, cy + 26), outline=(80, 255, 110, 255), width=3)
    md.line((cx - 20, cy, cx + 20, cy), fill=(80, 255, 110, 255), width=3)
    md.line((cx, cy - 12, cx, cy + 12), fill=(80, 255, 110, 255), width=3)
    img = art.add(img, mk.filter(ImageFilter.GaussianBlur(3)), 1.2)
    img = Image.alpha_composite(img, mk)
    # falling bomb with a violet glow
    bomb = render_vox(read_vox(os.path.join(MOD, "vox", "bomb.vox")), px=9, yaw=20, pitch=60, glow=0)
    img = art.add(img, art.glow_spot((W, H), (cx - 10, cy - 110), 60, (170, 90, 255), 2), 1.4)
    img.alpha_composite(bomb, (cx - 10 - bomb.width // 2, cy - 110 - bomb.height // 2))
    # HUD
    hud = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hud)
    for (x, y, sx, sy) in ((40, 40, 1, 1), (W - 40, 40, -1, 1), (40, H - 40, 1, -1), (W - 40, H - 40, -1, -1)):
        hd.line((x, y, x + 60 * sx, y), fill=(255, 255, 255, 200), width=3)
        hd.line((x, y, x, y + 60 * sy), fill=(255, 255, 255, 200), width=3)
    hd.ellipse((70, 160, 86, 176), fill=(255, 50, 50, 255))
    f = art.font(22)
    hd.text((96, 168), "CAM", font=f, fill=(255, 255, 255, 230), anchor="lm")
    for i, t in enumerate(("BAT 76%", "SIGNAL |||.", "ALT 24.6 m", "SPD 3.2 m/s", "BOMBS 2")):
        hd.text((W - 80, 170 + i * 28), t, font=f, fill=(255, 255, 255, 230), anchor="rm")
    hd.line((W / 2 - 14, H / 2, W / 2 + 14, H / 2), fill=(255, 255, 255, 200), width=2)
    hd.line((W / 2, H / 2 - 14, W / 2, H / 2 + 14), fill=(255, 255, 255, 200), width=2)
    # scanlines + a bit of static on the right edge
    for y in range(0, H, 4):
        hd.line((0, y, W, y), fill=(0, 0, 0, 25))
    for i in range(140):
        x = rnd.randint(W - 260, W)
        y = rnd.randint(0, H)
        c = rnd.randint(150, 255)
        hd.rectangle((x, y, x + rnd.randint(4, 40), y + 1), fill=(c, c, c, rnd.randint(40, 120)))
    img = Image.alpha_composite(img, hud)
    # the drone itself, bottom left
    dr = render_vox(read_vox(os.path.join(MOD, "vox", "drone.vox")), px=11, yaw=30, pitch=30, glow=0.8)
    img.alpha_composite(dr, (40, H - dr.height - 30))
    img = art.text_with_glow(img, (44, 100), "CAMERA DRONE", art.font(70), glow=(60, 220, 120), anchor="ls")
    img = art.text_with_glow(img, (48, 142), "Дрон с камерой", art.font(32, bold=False), fill=(220, 255, 225), glow=(40, 160, 80), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "preview.jpg"))
    print("preview.jpg", n // 1024, "KB")


def rotor_png(path, size=128):
    """Spinning-rotor blur: a faint disc, two darker blade sweeps and a hub."""
    import numpy as np
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (xx / (size - 1) - 0.5) * 2
    ny = (yy / (size - 1) - 0.5) * 2
    r = np.sqrt(nx ** 2 + ny ** 2)
    ang = np.arctan2(ny, nx)
    sweep = (0.5 + 0.5 * np.cos(2 * ang)) ** 6
    a = np.where(r <= 1, 0.18 + 0.55 * sweep * np.clip(r * 1.3, 0, 1), 0)
    a = a * np.clip((1 - r) * size / 4, 0, 1)
    a = np.where(r < 0.12, 0.95, a)
    v = np.where(r < 0.12, 60, 200 - 120 * sweep)
    arr = np.zeros((size, size, 4), np.uint8)
    arr[..., 0] = v.astype(np.uint8)
    arr[..., 1] = v.astype(np.uint8)
    arr[..., 2] = (v * 1.02).clip(0, 255).astype(np.uint8)
    arr[..., 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(path)


def build_icon():
    g = render_vox(read_vox(os.path.join(MOD, "vox", "drone.vox")), px=6, yaw=30, pitch=30, glow=0.5)
    size = 128
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    s = min((size - 8) / g.width, (size - 8) / g.height)
    g2 = g.resize((int(g.width * s), int(g.height * s)), Image.LANCZOS)
    icon.alpha_composite(g2, ((size - g2.width) // 2, (size - g2.height) // 2))
    icon.save(os.path.join(MOD, "ui", "icon.png"))


if __name__ == "__main__":
    os.makedirs(os.path.join(MOD, "ui"), exist_ok=True)
    art.dot_png(os.path.join(MOD, "ui", "dot.png"))
    rotor_png(os.path.join(MOD, "ui", "rotor.png"))
    build_icon()
    build_preview()
