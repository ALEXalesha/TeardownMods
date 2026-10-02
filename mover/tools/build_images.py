"""Mover preview.jpg, icon and UI textures."""
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


def outline(img: Image.Image, color, width=3) -> Image.Image:
    a = img.split()[3].point(lambda v: 255 if v > 10 else 0)
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1))
    ring = Image.new("RGBA", img.size, color + (0,))
    ring.putalpha(grown)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out = Image.alpha_composite(out, ring.filter(ImageFilter.GaussianBlur(2)))
    out = Image.alpha_composite(out, ring)
    out = Image.alpha_composite(out, img)
    return out


def pad(img, n):
    out = Image.new("RGBA", (img.width + 2 * n, img.height + 2 * n), (0, 0, 0, 0))
    out.alpha_composite(img, (n, n))
    return out


def arrow(d: ImageDraw.ImageDraw, x0, y0, x1, y1, col, w=6):
    d.line((x0, y0, x1, y1), fill=col + (255,), width=w)
    ang = math.atan2(y1 - y0, x1 - x0)
    for s in (-1, 1):
        a = ang + math.pi + s * 0.45
        d.line((x1, y1, x1 + math.cos(a) * 22, y1 + math.sin(a) * 22), fill=col + (255,), width=w)


def build_preview():
    rnd = random.Random(3)
    img = art.vertical_gradient((W, H), (22, 30, 40, 255), (52, 62, 72, 255))
    d = ImageDraw.Draw(img)
    floor = int(H * 0.74)
    d.rectangle((0, floor, W, H), fill=(44, 46, 50, 255))
    for x in range(-400, W + 400, 60):
        d.line((x, floor, x + (x - W / 2) * 0.6, H), fill=(56, 58, 62, 255), width=1)
    # warehouse back wall with panels
    for x in range(0, W, 128):
        d.rectangle((x + 4, 120, x + 124, floor - 4), outline=(40, 50, 60, 255), width=3)
    # frozen crate stack (blue outline)
    crates = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for i, (cx, cy) in enumerate(((120, floor - 40), (190, floor - 40), (155, floor - 105))):
        spr = art.render_debris("crate", random.Random(10 + i), px=12)
        spr = outline(pad(spr, 8), (80, 150, 255), 3)
        crates.alpha_composite(spr, (int(cx - spr.width / 2), int(cy - spr.height / 2)))
    img = Image.alpha_composite(img, crates)
    # the lifted car with cyan outline
    vf, m = art.car_model((40, 120, 210))
    car = render_models(vf, [m], yaw=35, pitch=24, px=11, ss=2, glow=0.3)
    car = outline(pad(car, 10), (70, 255, 255), 4)
    cx, cy = 560, 250
    img.alpha_composite(car, (int(cx - car.width / 2), int(cy - car.height / 2)))
    # shadow on the floor
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((cx - 150, floor + 10, cx + 150, floor + 40), fill=(0, 0, 0, 110))
    img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(10)))
    # gizmo axes
    ax = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(ax)
    arrow(ad, cx, cy, cx + 150, cy + 40, (255, 70, 60))
    arrow(ad, cx, cy, cx, cy - 160, (80, 255, 100))
    arrow(ad, cx, cy, cx - 120, cy + 70, (70, 150, 255))
    ad.ellipse((cx - 110, cy - 40, cx + 110, cy + 40), outline=(255, 220, 80, 200), width=3)
    img = art.add(img, ax.filter(ImageFilter.GaussianBlur(4)), 0.8)
    img = Image.alpha_composite(img, ax)
    # gizmo gun at bottom right with a beam to the car
    vg = read_vox(os.path.join(MOD, "vox", "gizmo.vox"))
    gun = render_vox(vg, px=16, yaw=130, pitch=18, glow=0.9)
    gx, gy = W - gun.width - 40, H - gun.height - 30
    beam = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(beam)
    pts = []
    for i in range(30):
        t = i / 29
        x = gx + 40 + (cx + 40 - gx - 40) * t
        y = gy + 40 + (cy + 30 - gy - 40) * t + math.sin(t * 20) * 6 * math.sin(t * math.pi)
        pts.append((x, y))
    bd.line(pts, fill=(120, 255, 255, 255), width=4)
    img = art.add(img, beam.filter(ImageFilter.GaussianBlur(6)), 1.5)
    img = Image.alpha_composite(img, beam)
    img.alpha_composite(gun, (gx, gy))
    f1 = art.font(80)
    f2 = art.font(34, bold=False)
    img = art.text_with_glow(img, (44, 100), "MOVER", f1, glow=(40, 200, 255), anchor="ls")
    img = art.text_with_glow(img, (48, 146), "Перемещатель", f2, fill=(210, 250, 255), glow=(30, 150, 200), glow_r=6, anchor="ls")
    n = art.save_jpg(img, os.path.join(MOD, "preview.jpg"))
    print("preview.jpg", n // 1024, "KB")


def build_icon():
    vg = read_vox(os.path.join(MOD, "vox", "gizmo.vox"))
    g = render_vox(vg, px=10, yaw=130, pitch=18, glow=0.6)
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
